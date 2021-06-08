pragma ton-solidity ^0.39.0;
pragma AbiHeader expire;


import "./interfaces/IStakingPool.sol";
import "./interfaces/IUserData.sol";
import "./interfaces/IUpgradableByRequest.sol";
import "./interfaces/IElection.sol";

import "./libraries/StakingErrors.sol";
import "./libraries/StakingConsts.sol";
import "./libraries/Gas.sol";
import "./libraries/MsgFlag.sol";
import "./libraries/PlatformTypes.sol";

import "./utils/Platform.sol";


contract Election is IElection {
    event ElectionCodeUpgraded(uint32 code_version);

    uint32 public current_version;
    TvmCell public platform_code;

    address public root;
    uint128 public round_num;

    struct Node {
        uint256 prev_node;
        uint256 next_node;
        MembershipRequest request;
    }

    // this array contains 2-way linked list by request tokens
    // nodes are connected in descending order by tokens
    // 0 position node is 'origin' and acting as a special pointer to start/end of list
    Node[] requests_nodes;
    // sorted list starts with this idx
    uint256 public list_start_idx;

    mapping (address => MembershipRequest) public requests;

    bool public election_ended;

    // Cant be deployed directly
    constructor() public { revert(); }

    // return sorted list of requests
    function getRequests(uint256 limit) public view responsible returns (MembershipRequest[]) {
        limit = math.min(limit, requests_nodes.length - 1);
        MembershipRequest[] _requests = new MembershipRequest[](limit);
        Node cur_node = requests_nodes[list_start_idx];
        uint128 counter = 0;

        while (counter < limit && cur_node.request.tokens != 0) {
            _requests[counter] = cur_node.request;
            counter++;
            cur_node = requests_nodes[cur_node.next_node];
        }

        return { value: 0, bounce: false, flag: MsgFlag.REMAINING_GAS }_requests;
    }

    function applyForMembership(
        address ton_addr,
        uint256 eth_addr,
        uint128 tokens,
        address send_gas_to,
        uint32 code_version
    ) external override onlyUserData(ton_addr) {
        require (tokens > 0, StakingErrors.BAD_RELAY_MEMBERSHIP_REQUEST);
        require (ton_addr.value != 0, StakingErrors.EXTERNAL_ADDRESS);
        require (!election_ended, StakingErrors.ELECTION_ENDED);

        tvm.rawReserve(Gas.ELECTION_INITIAL_BALANCE, 2);

        if (code_version > current_version) {
            send_gas_to.transfer(0, false, MsgFlag.ALL_NOT_RESERVED);
            return;
        }

        Node new_node = Node(0, 0, MembershipRequest(ton_addr, eth_addr, tokens));
        // if there is not requests
        if (list_start_idx == 0) {
            requests_nodes.push(new_node);
            uint256 new_idx = requests_nodes.length - 1;

            list_start_idx = new_idx;
            requests[ton_addr] = new_node.request;
            send_gas_to.transfer({ value: 0, flag: MsgFlag.ALL_NOT_RESERVED });
        // this gus already applied for membership
        } else if (requests[ton_addr].tokens != 0) {
            send_gas_to.transfer({ value: 0, flag: MsgFlag.ALL_NOT_RESERVED });
        // new request, add to sorted list
        } else {
            requests[ton_addr] = new_node.request;
            requests_nodes.push(new_node);
            uint256 new_idx = requests_nodes.length - 1;

            uint256 cur_node_idx = list_start_idx;

            while (cur_node_idx != 0) {
                Node cur_node = requests_nodes[cur_node_idx];

                if (tokens >= cur_node.request.tokens) {
                    // current node is head
                    if (cur_node.prev_node == 0) {
                        requests_nodes[new_idx].next_node = cur_node_idx;
                        requests_nodes[cur_node_idx].prev_node = new_idx;
                        list_start_idx = new_idx;
                    // insert new node between cur and prev nodes
                    } else {
                        requests_nodes[new_idx].next_node = cur_node_idx;
                        requests_nodes[cur_node_idx].prev_node = new_idx;

                        requests_nodes[new_idx].prev_node = cur_node.prev_node;
                        requests_nodes[cur_node.prev_node].next_node = new_idx;
                    }

                    break;
                }

                // we reached end of list
                // it means this request has lowest tokens and should be added to tail
                if (cur_node.next_node == 0) {
                    requests_nodes[cur_node_idx].next_node = new_idx;
                    requests_nodes[new_idx].prev_node = cur_node_idx;
                }

                cur_node_idx = cur_node.next_node;
            }

        }

        IUserData(msg.sender).relayMembershipRequestAccepted{ value: 0, flag: MsgFlag.ALL_NOT_RESERVED }(
            round_num, tokens, eth_addr, send_gas_to
        );
    }

    function finish(address send_gas_to) external override onlyRoot {
        require (!election_ended, StakingErrors.ELECTION_ENDED);

        tvm.rawReserve(Gas.ELECTION_INITIAL_BALANCE, 2);
        election_ended = true;

        MembershipRequest[] top_requests = getRequests(StakingConsts.relaysCount);
        IStakingPool(root).onElectionEnded{ value: 0, flag: MsgFlag.ALL_NOT_RESERVED }(round_num, top_requests, send_gas_to);
    }

    function upgrade(TvmCell code, uint32 new_version, address send_gas_to) external onlyRoot {
        if (new_version == current_version) {
            tvm.rawReserve(Gas.ELECTION_INITIAL_BALANCE, 2);
            send_gas_to.transfer({ value: 0, flag: MsgFlag.ALL_NOT_RESERVED });
        } else {
            emit ElectionCodeUpgraded(new_version);

            TvmBuilder builder;

            builder.store(root);
            builder.store(round_num);
            builder.store(current_version);
            builder.store(new_version);
            builder.store(send_gas_to);

            builder.store(requests_nodes);
            builder.store(list_start_idx);
            builder.store(requests);
            builder.store(election_ended);

            builder.store(platform_code);

            // set code after complete this method
            tvm.setcode(code);

            // run onCodeUpgrade from new code
            tvm.setCurrentCode(code);
            onCodeUpgrade(builder.toCell());
        }
    }

    function onCodeUpgrade(TvmCell upgrade_data) private {
        tvm.resetStorage();
        tvm.rawReserve(Gas.ELECTION_INITIAL_BALANCE, 2);

        TvmSlice s = upgrade_data.toSlice();
        (address root_, , address send_gas_to) = s.decode(address, uint8, address);
        root = root_;

        platform_code = s.loadRef();

        TvmSlice initialData = s.loadRefAsSlice();
        round_num = initialData.decode(uint128);

        TvmSlice params = s.loadRefAsSlice();
        current_version = params.decode(uint32);

        // create origin node after contract initialization
        requests_nodes.push(Node(0, 0, MembershipRequest(address.makeAddrNone(), 0, 0)));

        IStakingPool(root).onElectionStarted{ value: 0, flag: MsgFlag.ALL_NOT_RESERVED }(round_num, send_gas_to);
    }

    function _buildUserDataParams(address user) private inline pure returns (TvmCell) {
        TvmBuilder builder;
        builder.store(user);
        return builder.toCell();
    }

    function _buildInitData(uint8 type_id, TvmCell _initialData) private inline view returns (TvmCell) {
        return tvm.buildStateInit({
            contr: Platform,
            varInit: {
                root: address(this),
                platformType: type_id,
                initialData: _initialData,
                platformCode: platform_code
            },
            pubkey: 0,
            code: platform_code
        });
    }

    function getUserDataAddress(address user) public view responsible returns (address) {
        return { value: 0, bounce: false, flag: MsgFlag.REMAINING_GAS } address(tvm.hash(_buildInitData(
            PlatformTypes.UserData,
            _buildUserDataParams(user)
        )));
    }

    modifier onlyUserData(address user) {
        address expectedAddr = getUserDataAddress(user);
        require (expectedAddr == msg.sender, StakingErrors.NOT_USER_DATA);
        _;
    }

    modifier onlyRoot() {
        require(msg.sender == root, StakingErrors.NOT_ROOT);
        _;
    }

}
