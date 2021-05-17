pragma ton-solidity ^0.43.0;

import "./IEvent.sol";


interface IEventNotificationReceiver is IEvent {
    function notifyEthereumEventStatusChanged(EthereumEventStatus status) external;
    function notifyTonEventStatusChanged(TonEventStatus status) external;
}
