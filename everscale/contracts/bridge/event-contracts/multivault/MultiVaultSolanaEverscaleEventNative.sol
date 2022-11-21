pragma ton-solidity >= 0.39.0;
pragma AbiHeader time;
pragma AbiHeader expire;
pragma AbiHeader pubkey;


import "ton-eth-bridge-token-contracts/contracts/interfaces/ITokenRoot.sol";

import "./../../interfaces/multivault/IMultiVaultSolanaEverscaleEventNative.sol";
import "./../../interfaces/event-configuration-contracts/ISolanaEverscaleEventConfiguration.sol";
import "./../../interfaces/ISolanaEverscaleProxyExtended.sol";

import "./../base/SolanaEverscaleBaseEvent.sol";


contract MultiVaultSolanaEverscaleEventNative is SolanaEverscaleBaseEvent, IMultiVaultSolanaEverscaleEventNative {
    address token;
    uint128 amount;
    uint64 sol_amount;
    address recipient;
    bytes payload;

    address proxy;
    address tokenWallet;

    constructor(
        address _initializer,
        TvmCell _meta
    ) SolanaEverscaleBaseEvent(_initializer, _meta) public {}

    function afterSignatureCheck(TvmSlice body, TvmCell /*message*/) private inline view returns (TvmSlice) {
        body.decode(uint64, uint32);
        TvmSlice bodyCopy = body;
        uint32 functionId = body.decode(uint32);
        if (isExternalVoteCall(functionId)){
            require(votes[msg.pubkey()] == Vote.Empty, ErrorCodes.KEY_VOTE_NOT_EMPTY);
        }
        return bodyCopy;
    }

    function onInit() override internal {
        (
            token,
            amount,
            sol_amount,
            recipient,
            payload
        ) = abi.decode(
            eventInitData.voteData.eventData,
            (address, uint128, uint64, address, bytes)
        );

        ISolanaEverscaleEventConfiguration(eventInitData.configuration).getDetails{
            value: 1 ton,
            callback: MultiVaultSolanaEverscaleEventNative.receiveConfigurationDetails
        }();
    }

    function receiveConfigurationDetails(
        ISolanaEverscaleEventConfiguration.BasicConfiguration,
        ISolanaEverscaleEventConfiguration.SolanaEverscaleEventConfiguration _networkConfiguration,
        TvmCell
    ) external override {
        require(msg.sender == eventInitData.configuration);

        proxy = _networkConfiguration.proxy;

        ITokenRoot(token).walletOf{
            value: 0.1 ton,
            callback: MultiVaultSolanaEverscaleEventNative.receiveProxyTokenWallet
        }(proxy);
    }

    function receiveProxyTokenWallet(
        address tokenWallet_
    ) external override {
        require(msg.sender == token);

        tokenWallet = tokenWallet_;

        loadRelays();
    }

    function getDecodedData() external override responsible returns(
        address token_,
        uint128 amount_,
        uint64 sol_amount_,
        address recipient_,
        address proxy_,
        address tokenWallet_,
        bytes payload_
    ) {
        return {value: 0, flag: MsgFlag.REMAINING_GAS, bounce: false}(
            token,
            amount,
            sol_amount_,
            recipient,
            proxy,
            tokenWallet,
            payload_
        );
    }

    function onConfirm() internal override {
        TvmCell meta = abi.encode(
            tokenWallet,
            amount,
            recipient
        );

        ISolanaEverscaleProxyExtended(eventInitData.configuration).onEventConfirmedExtended{
            flag: MsgFlag.ALL_NOT_RESERVED
        }(eventInitData, meta, initializer);
    }
}
