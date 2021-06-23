pragma ton-solidity ^0.39.0;


interface IBasicEventConfiguration {
    enum EventType { Ethereum, TON }

    struct BasicConfiguration {
        bytes eventABI;
        address staking;
        uint128 eventInitialBalance;
        TvmCell eventCode;
        TvmCell meta;
        uint32 chainId;
    }
}
