pragma ton-solidity >= 0.39.0;


contract TokenCellEncoder {
    function encodeEthereumBurnPayload(
        uint160 ethereumAddress,
        uint32 chainId
    ) public pure returns(
        TvmCell data
    ) {
        TvmBuilder builder;

        builder.store(ethereumAddress, chainId);

        data = builder.toCell();
    }

    function decodeEthereumBurnPayload(
        TvmCell data
    ) public pure returns(
        uint160 ethereumAddress,
        uint32 chainId
    ) {
        (ethereumAddress, chainId) = data.toSlice().decode(uint160, uint32);
    }

    function encodeSolanaBurnPayload(
        uint256 solanaOwnerAddress
    ) public pure returns(
        TvmCell data
    ) {
        TvmBuilder builder;

        builder.store(solanaOwnerAddress);

        data = builder.toCell();
    }

    function decodeSolanaBurnPayload(
        TvmCell data
    ) public pure returns(
        uint256 solanaOwnerAddress
    ) {
        solanaOwnerAddress = data.toSlice().decode(uint256);
    }
}
