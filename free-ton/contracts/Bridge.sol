pragma solidity >= 0.6.0;
pragma AbiHeader expire;
pragma AbiHeader pubkey;


import "./event-configuration-contracts/EthereumEventConfiguration.sol";
import "./event-configuration-contracts/TonEventConfiguration.sol";

import "./interfaces/IEvent.sol";
import "./interfaces/IBridge.sol";
import "./interfaces/IEventConfiguration.sol";

import "./utils/AccountsOwnable.sol";
import "./utils/TransferUtils.sol";


/*
    @title FT Bridge contract
    @summary
*/
contract Bridge is AccountsOwnable, TransferUtils, IBridge {
    uint16 static _randomNonce;

    BridgeConfiguration bridgeConfiguration;

    struct EventConfiguration {
        mapping(address => bool) votes;
        address addr;
        bool status;
        IEventConfiguration.EventType _type;
    }

    mapping(uint32 => EventConfiguration) eventConfigurations;
    event EventConfigurationCreationVote(uint32 id, address relay, bool vote);
    event EventConfigurationCreationEnd(uint32 id, bool active, address addr, IEventConfiguration.EventType _type);

    struct EventConfigurationUpdate {
        mapping(address => bool) votes;
        uint32 targetID;
        address addr;
        IEventConfiguration.BasicConfigurationInitData basicInitData;
        IEventConfiguration.EthereumEventConfigurationInitData ethereumInitData;
        IEventConfiguration.TonEventConfigurationInitData tonInitData;
    }
    mapping(uint32 => EventConfigurationUpdate) eventConfigurationsUpdate;
    event EventConfigurationUpdateVote(uint32 id, address relay, bool vote);
    event EventConfigurationUpdateEnd(uint32 id, bool active, address addr, IEventConfiguration.EventType _type);

    mapping(BridgeConfiguration => mapping(address => bool)) bridgeConfigurationVotes;
    event BridgeConfigurationUpdateVote(BridgeConfiguration _bridgeConfiguration, address relay, Vote vote);
    event BridgeConfigurationUpdateEnd(BridgeConfiguration _bridgeConfiguration, bool status);

    mapping(BridgeRelay => mapping(address => bool)) bridgeRelayVotes;
    event BridgeRelaysUpdateVote(BridgeRelay target, address relay, Vote vote);
    event BridgeRelaysUpdateEnd(BridgeRelay target, bool status);

    /*
        @dev Throws an error if bridge currently inactive
    */
    modifier onlyActive() {
        require(bridgeConfiguration.active == true, BRIDGE_NOT_ACTIVE);
        _;
    }

    /*
        @dev Throws and error is event configuration has less confirmations than required or more rejects than allowed
    */
    modifier onlyActiveConfiguration(uint32 id) {
        require(eventConfigurations[id].status == true, EVENT_CONFIGURATION_NOT_ACTIVE);
        _;
    }

    /*
        @param _relayAccounts List of relays accounts
        @param _relayEthereumAccounts List of relays Ethereum accounts
        @param _bridgeConfiguration Initial Bridge configuration
    */
    constructor(
        address[] _relayAccounts,
        uint160[] _relayEthereumAccounts,
        BridgeConfiguration _bridgeConfiguration
    ) public {
        require(tvm.pubkey() == msg.pubkey(), WRONG_TVM_KEY);
        require(_relayAccounts.length == _relayEthereumAccounts.length, KEYS_DIFFERENT_SHAPE);
        tvm.accept();

        for (uint i=0; i < _relayAccounts.length; i++) {
            _grantOwnership(_relayAccounts[i], _relayEthereumAccounts[i]);
        }

        bridgeConfiguration = _bridgeConfiguration;
        bridgeConfiguration.active = true;
    }

    /*
        @notice Initialize adding new event configuration
        @dev Called only by relay.
        @dev Event configuration ID should not exist, revert otherwise
        @param id Event configuration id
        @param addr Address of event configuration contract
        @param _type Type of event configuration (Ethereum or TON)
    */
    function initializeEventConfigurationCreation(
        uint32 id,
        address addr,
        IEventConfiguration.EventType _type
    )
        public
        onlyActive
        onlyOwnerAddress(msg.sender)
        transferAfterRest(msg.sender)
    {
        require(!eventConfigurations.exists(id), EVENT_CONFIGURATION_ALREADY_EXISTS);

        address relay = msg.sender;

        EventConfiguration _eventConfiguration;
        _eventConfiguration.addr = addr;
        _eventConfiguration._type = _type;
        _eventConfiguration.votes[relay] = true;

        eventConfigurations[id] = _eventConfiguration;

        emit EventConfigurationCreationVote(id, relay, true);
    }

    /*
        @notice Vote for specific configuration.
        @dev Event configuration ID should exist, revert otherwise
        @param id Event configuration ID
        @param vote Confirm of reject
    */
    function voteForEventConfigurationCreation(
        uint32 id,
        bool vote
    )
        public
        onlyActive
        onlyOwnerAddress(msg.sender)
        transferAfterRest(msg.sender)
    {
        require(eventConfigurations.exists(id), EVENT_CONFIGURATION_NOT_EXISTS);

        EventConfiguration _eventConfiguration = eventConfigurations[id];
        _eventConfiguration.votes[msg.sender] = vote;
        eventConfigurations[id] = _eventConfiguration;

        // Get results results
        (address[] confirmRelays, address[] rejectRelays,,) = getEventConfigurationDetails(id);

        // - Check voting results and make updates if necessary
        if (
            // -- Relay voted for confirmation AND enough confirmations received AND configuration not confirmed before
            // -- Enable configuration
            confirmRelays.length >= bridgeConfiguration.bridgeUpdateRequiredConfirmations &&
            vote == true &&
            eventConfigurations[id].status == false
        ) {
            eventConfigurations[id].status = true;

            emit EventConfigurationCreationEnd(
                id,
                true,
                eventConfigurations[id].addr,
                eventConfigurations[id]._type
            );
        } else if (
            // -- Relay voted for reject AND enough rejects received
            // -- Remove configuration
            rejectRelays.length >= bridgeConfiguration.bridgeUpdateRequiredRejects &&
            vote == false
        ) {
            emit EventConfigurationCreationEnd(
                id,
                false,
                eventConfigurations[id].addr,
                eventConfigurations[id]._type
            );

            delete eventConfigurations[id];
        }
    }

    /*
        @notice Get details about specific event configuration
        @param id Event configuration id
        @returns confirmRelays List of relays, who have confirmed this configuration
        @returns rejectRelays List of relays, who have rejected this configuration
        @returns addr Address of the event configuration contract
        @returns status Current status of the configuration (active or not)
    */
    function getEventConfigurationDetails(
        uint32 id
    ) public view returns (
        address[] confirmRelays,
        address[] rejectRelays,
        address addr,
        bool status
    ) {
        for ((address relay, bool vote): eventConfigurations[id].votes) {
            if (vote == true) {
                confirmRelays.push(relay);
            } else {
                rejectRelays.push(relay);
            }
        }

        addr = eventConfigurations[id].addr;
        status = eventConfigurations[id].status;
    }

    /*
        @notice Get list of active event configuration contracts
        @returns ids List of ids
        @returns addrs List of addresses
        @returns _types List of types
    */
    function getActiveEventConfigurations() public view returns (
        uint32[] ids,
        address[] addrs,
        IEventConfiguration.EventType[] _types
    ) {

        for ((uint32 id, EventConfiguration configuration): eventConfigurations) {
            if (configuration.status) {
                ids.push(id);
                addrs.push(configuration.addr);
                _types.push(configuration._type);
            }
        }
    }

    /*
        @notice Get all event configurations.
        @returns ids List of ids
        @returns addrs List of addresses
        @returns statuses List of status
        @returns _types List of types
    */
    function getEventConfigurations() public view returns (
        uint32[] ids,
        address[] addrs,
        bool[] statuses,
        IEventConfiguration.EventType[] _types
    ) {
        for ((uint32 id, EventConfiguration configuration): eventConfigurations) {
            ids.push(id);
            addrs.push(configuration.addr);
            statuses.push(configuration.status);
            _types.push(configuration._type);
        }
    }

    /*
        @notice Confirm Ethereum event instance.
        @dev Called only by relay
        @param eventVoteData Ethereum event vote data
        @param configurationID Ethereum Event configuration ID
    */
    function confirmEthereumEvent(
        IEvent.EthereumEventVoteData eventVoteData,
        uint32 configurationID
    )
        public
        view
        onlyActive
        onlyOwnerAddress(msg.sender)
        transferAfterRest(msg.sender)
        onlyActiveConfiguration(configurationID)
    {
        EthereumEventConfiguration(eventConfigurations[configurationID].addr).confirmEvent{value: 1 ton}(
            eventVoteData,
            msg.sender
        );
    }

    /*
        @notice Reject Ethereum event instance.
        @dev Called only by relay. Only rejects already existing EthereumEvent contract, not deploy it.
        @param eventVoteData Ethereum event vote data
        @param configurationID Ethereum Event configuration ID
    */
    function rejectEthereumEvent(
        IEvent.EthereumEventVoteData eventVoteData,
        uint32 configurationID
    )
        public
        view
        onlyActive
        onlyOwnerAddress(msg.sender)
        transferAfterRest(msg.sender)
        onlyActiveConfiguration(configurationID)
    {
        EthereumEventConfiguration(eventConfigurations[configurationID].addr).rejectEvent{value: 1 ton}(
            eventVoteData,
            msg.sender
        );
    }

    /*
        @notice Confirm TON event instance.
        @dev Called only by relay
        @param eventVoteData Ton event vote data
        @param eventDataSignature Relay's signature of the corresponding TonEvent structure
        @param configurationID Ton Event configuration ID
    */
    function confirmTonEvent(
        IEvent.TonEventVoteData eventVoteData,
        bytes eventDataSignature,
        uint32 configurationID
    )
        public
        view
        onlyActive
        onlyOwnerAddress(msg.sender)
        transferAfterRest(msg.sender)
        onlyActiveConfiguration(configurationID)
    {
        TonEventConfiguration(eventConfigurations[configurationID].addr).confirmEvent{value: 1 ton}(
            eventVoteData,
            eventDataSignature,
            msg.sender
        );
    }

    /*
        @notice Reject TON event instance.
        @dev Called only by relay. Only reject already existing TonEvent contract, not deploy it.
        @param eventVoteData Ton event vote data
        @param configurationID Ton Event configuration ID
    */
    function rejectTonEvent(
        IEvent.TonEventVoteData eventVoteData,
        uint32 configurationID
    )
        public
        view
        onlyActive
        onlyOwnerAddress(msg.sender)
        transferAfterRest(msg.sender)
        onlyActiveConfiguration(configurationID)
    {
        TonEventConfiguration(eventConfigurations[configurationID].addr).rejectEvent{value: 1 ton}(
            eventVoteData,
            msg.sender
        );
    }

    /*
        @notice Convert Vote structure to the decision of voter.
        @dev Since signature needs to mirror voting in Ethereum bridge
        It should be empty if relay reject the voting
        His vote just won't be passed to Ethereum
        @returns vote Voting decision
    */
    function getVotingDirection(Vote _vote) public pure returns(bool vote) {
        if (_vote.signature.length == 0) {
            vote = false;
        } else {
            vote = true;
        }
    }

    /*
        @notice Vote for Bridge configuration update
        @dev Can be called only by relay
        @param _bridgeConfiguration New bridge configuration
        @param _vote Vote structure. Signature and payload are empty for reject.
    */
    function updateBridgeConfiguration(
        BridgeConfiguration _bridgeConfiguration,
        Vote _vote
    )
        public
        onlyOwnerAddress(msg.sender)
        transferAfterRest(msg.sender)
    {
        emit BridgeConfigurationUpdateVote(_bridgeConfiguration, msg.sender, _vote);

        bool vote = getVotingDirection(_vote);

        bridgeConfigurationVotes[_bridgeConfiguration][msg.sender] = vote;

        // Check the results
        (address[] confirmRelays, address[] rejectRelays) = getBridgeConfigurationVotes(_bridgeConfiguration);

        // - If enough confirmations received - update configuration and remove voting
        if (confirmRelays.length == bridgeConfiguration.bridgeUpdateRequiredConfirmations) {
            bridgeConfiguration = _bridgeConfiguration;
            _removeBridgeConfigurationVoting(_bridgeConfiguration);

            emit BridgeConfigurationUpdateEnd(_bridgeConfiguration, true);
        }

        // - If enough rejects received - remove voting
        if (rejectRelays.length == bridgeConfiguration.bridgeUpdateRequiredRejects) {
            _removeBridgeConfigurationVoting(_bridgeConfiguration);

            emit BridgeConfigurationUpdateEnd(_bridgeConfiguration, false);
        }
    }

    /*
        @notice Garbage collector for update configuration voting
        @dev Called each time voting ends and remove it details from the storage
    */
    function _removeBridgeConfigurationVoting(
        BridgeConfiguration _bridgeConfiguration
    ) internal {
        delete bridgeConfigurationVotes[_bridgeConfiguration];
    }

    /*
        @notice Get list of votes for specific bridge configuration update
        @param _bridgeConfiguration Bridge configuration
        @returns confirmRelays List of relay addresses who confirmed the update
        @returns rejectRelays List of relay addresses who rejected the update
    */
    function getBridgeConfigurationVotes(
        BridgeConfiguration _bridgeConfiguration
    ) public view returns(
        address[] confirmRelays,
        address[] rejectRelays
    ) {
        for ((address relay, bool vote): bridgeConfigurationVotes[_bridgeConfiguration]) {
            if (vote == true) {
                confirmRelays.push(relay);
            } else {
                rejectRelays.push(relay);
            }
        }
    }


    /*
        @notice Initialize event configuration update. Allows to update event configuration contract address.
        And make a call to the event configuration contract, which updates initial data.
        @dev Update id should not be used before
        @dev Basic init data and init data would be send to event configuration in case of confirmation
        @dev If you don't want to change them - just copy already existing and use them
        @dev If you want to update Ethereum event configuration, fill the tonInitData with dummy data,
        it won't be used anyway. The same works for TON configuration update.
        @param id Update id
        @param targetID Id of the event configuration to update
        @param addr New event configuration address
        @param basicInitData New basic init data
        @param ethereumInitData New Ethereum event configuration init data
        @param tonInitData New TON event configuration init data
    */
    function initializeUpdateEventConfiguration(
        uint32 id,
        uint32 targetID,
        address addr,
        IEventConfiguration.BasicConfigurationInitData basicInitData,
        IEventConfiguration.EthereumEventConfigurationInitData ethereumInitData,
        IEventConfiguration.TonEventConfigurationInitData tonInitData
    )
        public
        onlyActive
        onlyOwnerAddress(msg.sender)
        transferAfterRest(msg.sender)
    {
        require(!eventConfigurationsUpdate.exists(id), EVENT_CONFIGURATION_UPDATE_ALREADY_EXISTS);
        require(eventConfigurations.exists(targetID), EVENT_CONFIGURATION_NOT_EXISTS);

        address relay = msg.sender;

        EventConfigurationUpdate update;
        update.targetID = targetID;
        update.addr = addr;
        update.basicInitData = basicInitData;
        update.ethereumInitData = ethereumInitData;
        update.tonInitData = tonInitData;
        update.votes[relay] = true;

        eventConfigurationsUpdate[id] = update;

        emit EventConfigurationCreationVote(id, relay, true);
    }

    /*
        @notice Vote for event configuration update.
        @dev If voting finished successfully - update an event configuration contract address. And send new (basicInitData, initData)
        to the event configuration contract, depending of it's type
        @dev Called only by relay
        @param id Update ID
        @param vote Confirm / reject
    */
    function voteForUpdateEventConfiguration(
        uint32 id,
        bool vote
    )
        public
        onlyActive
        onlyOwnerAddress(msg.sender)
        transferAfterRest(msg.sender)
    {
        require(eventConfigurationsUpdate.exists(id), EVENT_CONFIGURATION_UPDATE_NOT_EXISTS);

        address relay = msg.sender;

        EventConfigurationUpdate update = eventConfigurationsUpdate[id];
        update.votes[relay] = vote;
        eventConfigurationsUpdate[id] = update;

        emit EventConfigurationUpdateVote(id, relay, vote);

        // Check the results
        (address[] confirmRelays, address[] rejectRelays,,,,,) = getUpdateEventConfigurationDetails(id);

        // - Enough confirmations received, update event configuration
        if (confirmRelays.length == bridgeConfiguration.bridgeUpdateRequiredConfirmations) {
            // -- Update event configuration address
            eventConfigurations[update.targetID].addr = update.addr;

            // -- Send new configuration to the event config contract
            if (eventConfigurations[update.targetID]._type == IEventConfiguration.EventType.Ethereum) {
                EthereumEventConfiguration(eventConfigurations[update.targetID].addr).updateInitData{value: 1 ton}(
                    update.basicInitData,
                    update.ethereumInitData
                );
            } else {
                TonEventConfiguration(eventConfigurations[update.targetID].addr).updateInitData{value: 1 ton}(
                    update.basicInitData,
                    update.tonInitData
                );
            }

            emit EventConfigurationUpdateEnd(
                id,
                true,
                eventConfigurations[update.targetID].addr,
                eventConfigurations[update.targetID]._type
            );

            _removeUpdateEventConfiguration(id);
        }

        if (rejectRelays.length == bridgeConfiguration.bridgeUpdateRequiredRejects) {
            emit EventConfigurationUpdateEnd(
                id,
                false,
                eventConfigurations[update.targetID].addr,
                eventConfigurations[update.targetID]._type
            );

            _removeUpdateEventConfiguration(id);
        }
    }

    /*
        @notice Get details for specific configuration update
        @param id Update event configuration ID
        @returns confirmRelays List of relay addresses who have confirmed update
        @returns rejectRelays List of relay addresses who have rejected update
        @returns targetID Target event configuration id
        @returns addr New event configuration contract address
        @param basicInitData New basic init data
        @param ethereumInitData New Ethereum event configuration init data
        @param tonInitData New TON event configuration init data
    */
    function getUpdateEventConfigurationDetails(
        uint32 id
    ) public view returns(
        address[] confirmRelays,
        address[] rejectRelays,
        uint targetID,
        address addr,
        IEventConfiguration.BasicConfigurationInitData basicInitData,
        IEventConfiguration.EthereumEventConfigurationInitData ethereumInitData,
        IEventConfiguration.TonEventConfigurationInitData tonInitData
    ) {

        for ((address relay, bool vote): eventConfigurationsUpdate[id].votes) {
            if (vote == true) {
                confirmRelays.push(relay);
            } else {
               rejectRelays.push(relay);
            }
        }

        basicInitData = eventConfigurationsUpdate[id].basicInitData;
        ethereumInitData = eventConfigurationsUpdate[id].ethereumInitData;
        tonInitData = eventConfigurationsUpdate[id].tonInitData;
        targetID = eventConfigurationsUpdate[id].targetID;
        addr = eventConfigurationsUpdate[id].addr;
    }

    /*
        @notice Garbage collector for event configuration update
        @dev removes the update details
    */
    function _removeUpdateEventConfiguration(uint32 id) internal {
        delete eventConfigurationsUpdate[id];
    }


    /*
        @notice Vote for Bridge relays update
        @dev Called only by relay
        @param target Target relay structure
        @param _vote Vote structure. Signature and payload are empty for reject.
    */
    function updateBridgeRelays(
        BridgeRelay target,
        Vote _vote
    )
        public
        onlyOwnerAddress(msg.sender)
        transferAfterRest(msg.sender)
    {
        emit BridgeRelaysUpdateVote(target, msg.sender, _vote);

        bool vote = getVotingDirection(_vote);

        bridgeRelayVotes[target][msg.sender] = vote;

        // Check the results
        (address[] confirmRelays, address[] rejectRelays) = getBridgeRelayVotes(target);

        // - If enough confirmations received - update configuration and remove voting
        if (confirmRelays.length == bridgeConfiguration.bridgeUpdateRequiredConfirmations) {
            address targetAccount = address.makeAddrStd(target.wid, target.addr);

            if (target.action) {
                _grantOwnership(targetAccount, target.ethereumAccount);
            } else {
                _removeOwnership(targetAccount);
            }

            _removeBridgeRelayVoting(target);

            emit BridgeRelaysUpdateEnd(target, true);
        }

        // - If enough rejects received - remove voting
        if (rejectRelays.length == bridgeConfiguration.bridgeUpdateRequiredRejects) {
            _removeBridgeRelayVoting(target);

            emit BridgeRelaysUpdateEnd(target, false);
        }
    }

    /*
        @notice Get list of relays who voted for specific Bridge relay update
        @param target Target relay structure
        @returns confirmRelays List of relay addresses who confirmed the update
        @returns rejectRelays List of relay addresses who rejected the update
    */
    function getBridgeRelayVotes(
        BridgeRelay target
    ) public view returns(
        address[] confirmRelays,
        address[] rejectRelays
    ) {
        for ((address relay, bool vote): bridgeRelayVotes[target]) {
            if (vote == true) {
                confirmRelays.push(relay);
            } else {
                rejectRelays.push(relay);
            }
        }
    }


    /*
        @notice Garbage collector for bridge update relay
        @dev Called each time voting ends and remove it's details from the storage
    */
    function _removeBridgeRelayVoting(
        BridgeRelay target
    ) internal {
        delete bridgeRelayVotes[target];
    }

    /*
        @notice Get Bridge details.
        @returns _bridgeConfiguration Current bridge configuration
    */
    function getDetails() public view returns (
        BridgeConfiguration _bridgeConfiguration
    ) {
        return (
            bridgeConfiguration
        );
    }
}
