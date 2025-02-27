# DAO



> DAO contract for Everscale-EVM bridge



*Executes proposals confirmed in Everscale Bridge DAO. Proposals are submitted in form of payloads and signatures*

## Methods

### bridge

```solidity
function bridge() external view returns (address)
```






#### Returns

| Name | Type | Description |
|---|---|---|
| _0 | address | undefined |

### cache

```solidity
function cache(bytes32) external view returns (bool)
```





#### Parameters

| Name | Type | Description |
|---|---|---|
| _0 | bytes32 | undefined |

#### Returns

| Name | Type | Description |
|---|---|---|
| _0 | bool | undefined |

### configuration

```solidity
function configuration() external view returns (int128 wid, uint256 addr)
```






#### Returns

| Name | Type | Description |
|---|---|---|
| wid | int128 | undefined |
| addr | uint256 | undefined |

### decodeEthActionsEventData

```solidity
function decodeEthActionsEventData(bytes payload) external pure returns (int8 _wid, uint256 _addr, uint32 chainId, struct IDAO.EthAction[] actions)
```





#### Parameters

| Name | Type | Description |
|---|---|---|
| payload | bytes | undefined |

#### Returns

| Name | Type | Description |
|---|---|---|
| _wid | int8 | undefined |
| _addr | uint256 | undefined |
| chainId | uint32 | undefined |
| actions | IDAO.EthAction[] | undefined |

### execute

```solidity
function execute(bytes payload, bytes[] signatures) external nonpayable returns (bytes[] responses)
```

Execute set of actions.



#### Parameters

| Name | Type | Description |
|---|---|---|
| payload | bytes | Encoded Everscale event with payload details |
| signatures | bytes[] | Payload signatures |

#### Returns

| Name | Type | Description |
|---|---|---|
| responses | bytes[] | Bytes-encoded payload action responses |

### getChainID

```solidity
function getChainID() external view returns (uint256)
```






#### Returns

| Name | Type | Description |
|---|---|---|
| _0 | uint256 | undefined |

### initialize

```solidity
function initialize(address _owner, address _bridge) external nonpayable
```

Initializer



#### Parameters

| Name | Type | Description |
|---|---|---|
| _owner | address | DAO owner. Should be used only for initial set up, than ownership should be transferred to DAO itself. |
| _bridge | address | Bridge address |

### owner

```solidity
function owner() external view returns (address)
```



*Returns the address of the current owner.*


#### Returns

| Name | Type | Description |
|---|---|---|
| _0 | address | undefined |

### renounceOwnership

```solidity
function renounceOwnership() external nonpayable
```



*Leaves the contract without owner. It will not be possible to call `onlyOwner` functions anymore. Can only be called by the current owner. NOTE: Renouncing ownership will leave the contract without an owner, thereby removing any functionality that is only available to the owner.*


### setBridge

```solidity
function setBridge(address _bridge) external nonpayable
```



*Update bridge address*

#### Parameters

| Name | Type | Description |
|---|---|---|
| _bridge | address | New bridge address |

### setConfiguration

```solidity
function setConfiguration(IEverscale.EverscaleAddress _configuration) external nonpayable
```





#### Parameters

| Name | Type | Description |
|---|---|---|
| _configuration | IEverscale.EverscaleAddress | undefined |

### transferOwnership

```solidity
function transferOwnership(address newOwner) external nonpayable
```



*Transfers ownership of the contract to a new account (`newOwner`). Can only be called by the current owner.*

#### Parameters

| Name | Type | Description |
|---|---|---|
| newOwner | address | undefined |



## Events

### Initialized

```solidity
event Initialized(uint8 version)
```





#### Parameters

| Name | Type | Description |
|---|---|---|
| version  | uint8 | undefined |

### OwnershipTransferred

```solidity
event OwnershipTransferred(address indexed previousOwner, address indexed newOwner)
```





#### Parameters

| Name | Type | Description |
|---|---|---|
| previousOwner `indexed` | address | undefined |
| newOwner `indexed` | address | undefined |

### UpdateBridge

```solidity
event UpdateBridge(address indexed bridge)
```





#### Parameters

| Name | Type | Description |
|---|---|---|
| bridge `indexed` | address | undefined |

### UpdateConfiguration

```solidity
event UpdateConfiguration(IEverscale.EverscaleAddress configuration)
```





#### Parameters

| Name | Type | Description |
|---|---|---|
| configuration  | IEverscale.EverscaleAddress | undefined |



