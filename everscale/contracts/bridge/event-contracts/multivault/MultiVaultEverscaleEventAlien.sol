pragma ton-solidity >= 0.39.0;
pragma AbiHeader time;
pragma AbiHeader expire;
pragma AbiHeader pubkey;


import "./../../interfaces/multivault/IMultiVaultEverscaleEventAlien.sol";
import "./../../interfaces/multivault/IProxyMultiVaultAlien.sol";
import "./../../interfaces/ITokenRootAlienEVM.sol";

import "./../base/EverscaleBaseEvent.sol";


/// @notice Everscale-EVM event for MultiVault alien token transfer.
/// Before switching into the `Pending` status, event contract must perform
/// the following actions:
/// - Obtain the `token` token source.
contract MultiVaultEverscaleEventAlien is EverscaleBaseEvent, IMultiVaultEverscaleEventAlien {
    address proxy;
    address token;
    address remainingGasTo;
    uint128 amount;
    uint160 recipient;

    uint256 base_chainId;
    uint160 base_token;

    constructor(
        address _initializer,
        TvmCell _meta
    ) EverscaleBaseEvent(_initializer, _meta) public {}

    function afterSignatureCheck(TvmSlice body, TvmCell /*message*/) private inline view returns (TvmSlice) {
        body.decode(uint64, uint32);
        TvmSlice bodyCopy = body;
        uint32 functionId = body.decode(uint32);
        if (isExternalVoteCall(functionId)){
            require(votes[msg.pubkey()] == Vote.Empty, ErrorCodes.KEY_VOTE_NOT_EMPTY);
        }
        return bodyCopy;
    }

    function close() external view {
        require(
            status != Status.Pending || now > createdAt + FORCE_CLOSE_TIMEOUT,
            ErrorCodes.EVENT_PENDING
        );

        require(msg.sender == remainingGasTo, ErrorCodes.SENDER_IS_NOT_EVENT_OWNER);
        transferAll(remainingGasTo);
    }

    function onInit() override internal {
        (proxy, token, remainingGasTo, amount, recipient) = abi.decode(
            eventInitData.voteData.eventData,
            (address, address, address, uint128, uint160)
        );

        // TODO: safe value?
        ITokenRootAlienEVM(token).meta{
            value: 1 ton,
            callback: MultiVaultEverscaleEventAlien.receiveTokenMeta
        }();
    }

    function receiveTokenMeta(
        uint256 base_chainId_,
        uint160 base_token_,
        string name,
        string symbol,
        uint8 decimals
    ) external override {
        require(msg.sender == token);

        base_chainId = base_chainId_;
        base_token = base_token_;

        IProxyMultiVaultAlien(proxy).deriveAlienTokenRoot{
            value: 1 ton,
            callback: MultiVaultEverscaleEventAlien.receiveAlienTokenRoot
        }(
            base_chainId,
            base_token,
            name,
            symbol,
            decimals
        );
    }

    function receiveAlienTokenRoot(
        address token_
    ) external override {
        // TODO: add error codes all over the multivault contracts
        require(msg.sender == proxy);

        if (token_ != token) {
            status = Status.Rejected;
        } else {
            _updateEventData();

            status = Status.Pending;
        }

        loadRelays();
    }

    function _updateEventData() internal {
        eventInitData.voteData.eventData = abi.encode(
            base_token,
            amount,
            recipient,
            base_chainId
        );
    }

    // TODO: add on-bounce all over the multivault contracts to prevent stuck in Initializing
    function getDecodedData() external override responsible returns(
        address proxy_,
        address token_,
        address remainingGasTo_,
        uint128 amount_,
        uint160 recipient_,
        uint256 base_chainId_,
        uint160 base_token_
    ) {
        return {value: 0, flag: MsgFlag.REMAINING_GAS}(
            proxy,
            token,
            remainingGasTo,
            amount,
            recipient,
            base_chainId,
            base_token
        );
    }
}