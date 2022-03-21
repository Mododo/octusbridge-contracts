pragma ton-solidity >= 0.39.0;
pragma AbiHeader time;
pragma AbiHeader expire;
pragma AbiHeader pubkey;


import "ton-eth-bridge-token-contracts/contracts/interfaces/ITokenRoot.sol";

import "./../base/EverscaleBaseEvent.sol";
import "./../../interfaces/multivault/IMultiVaultEverscaleEventNative.sol";


/// @notice Everscale-EVM event for MultiVault native token transfer.
/// Before switching into the `Pending` status, event contract must perform
/// the following actions:
/// - Verify that the `tokenWallet` is a correct token wallet for `token`, owned by the proxy
/// - Obtain the `token` metadata (name, symbol, decimals)
/// - Rewrite the `eventData` with the correct value
contract MultiVaultEverscaleEventNative is EverscaleBaseEvent, IMultiVaultEverscaleEventNative {
    address proxy;
    address tokenWallet;
    address token;
    address remainingGasTo;
    uint128 amount;
    uint160 recipient;
    uint256 chainId;

    string name;
    string symbol;
    uint8 decimals;

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
        (
            proxy,
            tokenWallet,
            token,
            remainingGasTo,
            amount,
            recipient,
            chainId
        ) = abi.decode(
            eventInitData.voteData.eventData,
            (address, address, address, address, uint128, uint160, uint256)
        );

        ITokenRoot(token).name{
            value: 0.1 ton,
            callback: MultiVaultEverscaleEventNative.receiveTokenName
        }();

        ITokenRoot(token).symbol{
            value: 0.1 ton,
            callback: MultiVaultEverscaleEventNative.receiveTokenSymbol
        }();

        ITokenRoot(token).decimals{
            value: 0.1 ton,
            callback: MultiVaultEverscaleEventNative.receiveTokenDecimals
        }();

        ITokenRoot(token).walletOf{
            value: 0.1 ton,
            callback: MultiVaultEverscaleEventNative.receiveProxyTokenWallet
        }(proxy);
    }

    function receiveTokenName(
        string name_
    ) external override {
        require(msg.sender == token);

        name = name_;
    }

    function receiveTokenSymbol(
        string symbol_
    ) external override {
        require(msg.sender == token);

        symbol = symbol_;
    }

    function receiveTokenDecimals(
        uint8 decimals_
    ) external override {
        require(msg.sender == token);

        decimals = decimals_;
    }

    function receiveProxyTokenWallet(address tokenWallet_) external override {
        require(msg.sender == token);

        if (tokenWallet_ != tokenWallet) {
            status = Status.Rejected;
        } else {
            _updateEventData();

            status = Status.Pending;
        }

        loadRelays();
    }

    function getDecodedData() external override responsible returns(
        address proxy_,
        address tokenWallet_,
        address token_,
        address remainingGasTo_,
        uint128 amount_,
        uint160 recipient_,
        uint256 chainId_,
        string name_,
        string symbol_,
        uint8 decimals_
    ) {
        return (
            proxy,
            tokenWallet,
            token,
            remainingGasTo,
            amount,
            recipient,
            chainId,
            name,
            symbol,
            decimals
        );
    }

    function _updateEventData() internal {
        eventInitData.voteData.eventData = abi.encode(
            token.wid,
            token.value,

            name,
            symbol,
            decimals,

            amount,
            recipient,
            chainId
        );
    }
}