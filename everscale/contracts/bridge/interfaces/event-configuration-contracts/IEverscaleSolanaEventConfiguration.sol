pragma ton-solidity >= 0.39.0;

import "./IBasicEventConfiguration.sol";
import "./../event-contracts/IEverscaleSolanaEvent.sol";


interface IEverscaleSolanaEventConfiguration is IBasicEventConfiguration {
    struct EverscaleSolanaEventConfiguration {
        uint256 program;
        address eventEmitter;
        uint8 instruction;
        uint32 startTimestamp;
        uint32 endTimestamp;
        uint256 settings;
    }

    function deployEvent(
        IEverscaleSolanaEvent.EverscaleSolanaEventVoteData eventVoteData
    ) external;

    function deriveEventAddress(
        IEverscaleSolanaEvent.EverscaleSolanaEventVoteData eventVoteData
    ) external view responsible returns (address eventContract);

    function getDetails() external view responsible returns(
        BasicConfiguration _basicConfiguration,
        EverscaleSolanaEventConfiguration _networkConfiguration,
        TvmCell _meta
    );

    function setEndTimestamp(uint32 endTimestamp) external;
}
