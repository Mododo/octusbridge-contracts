pragma ton-solidity >= 0.39.0;

/*
    Ad hoc contract, used to perform encode / decode TvmCell.
    Not implemented in the Everscale-SDK at the moment of creation.
    @important Not strictly connected to the ERC20<->TIP3 token transfers, just an example.
*/
contract ProxyTokenTransferCellEncoder {
    function encodeEthereumEverscaleEventData(
        uint256 tokens,
        int128 wid,
        uint256 owner_addr
    ) public pure returns(
        TvmCell data
    ) {
        TvmBuilder builder;

        builder.store(tokens, wid, owner_addr);

        data = builder.toCell();
    }

    function encodeSolanaEverscaleEventData(
        uint64 tokens,
        address owner_addr
    ) public pure returns(
        TvmCell data
    ) {
        TvmBuilder builder;

        builder.store(tokens, owner_addr);

        data = builder.toCell();
    }

    function decodeEthereumEverscaleEventData(
        TvmCell data
    ) public pure returns(
        uint128 tokens,
        int8 wid,
        uint256 owner_addr
    ) {
        (
            uint256 _amount,
            int128 _wid,
            uint256 _addr
        ) = data.toSlice().decode(uint256, int128, uint256);
        return (uint128(_amount), int8(_wid), _addr);
    }

    function decodeSolanaEverscaleEventData(
        TvmCell data
    ) public pure returns(
        uint64 tokens,
        address owner_addr
    ) {
        (
            tokens,
            owner_addr
        ) = data.toSlice().decode(uint64, address);
    }

    function encodeEverscaleEthereumEventData(
        int8 wid,
        uint addr,
        uint128 tokens,
        uint160 ethereum_address,
        uint32 chainId
    ) public pure returns(
        TvmCell data
    ) {
        TvmBuilder builder;

        builder.store(wid, addr, tokens, ethereum_address, chainId);

        data = builder.toCell();
    }

    function encodeEverscaleSolanaEventData(
        address senderAddress,
        uint64 tokens,
        uint256 solanaOwnerAddress,
        string solanaTokenSymbol
    ) public pure returns(
        TvmCell data
    ) {
        TvmBuilder builder;

        builder.store(senderAddress, tokens, solanaOwnerAddress, solanaTokenSymbol);

        data = builder.toCell();
    }

    function decodeEverscaleEthereumEventData(
        TvmCell data
    ) public pure returns(
        int8 wid,
        uint addr,
        uint128 tokens,
        uint160 ethereum_address,
        uint32 chainId
    ) {
        (
            wid,
            addr,
            tokens,
            ethereum_address,
            chainId
        ) = data.toSlice().decode(int8, uint, uint128, uint160, uint32);
    }

    function decodeEverscaleSolanaEventData(
        TvmCell data
    ) public pure returns(
        address senderAddress,
        uint64 tokens,
        uint256 solanaOwnerAddress,
        string solanaTokenSymbol
    ) {
        (
            senderAddress,
            tokens,
            solanaOwnerAddress,
            solanaTokenSymbol
        ) = data.toSlice().decode(address, uint64, uint256, string);
    }
}
