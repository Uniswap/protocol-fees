// SPDX-License-Identifier: MIT
// We use a floating point pragma here so it can be used within other projects that interact with the ZKsync ecosystem without using our exact pragma version.
pragma solidity ^0.8.21;

// NOTICE:
//
// THIS IS IMPORTED STRAIGHT FROM ZKSYNCS CONTRACTS REPOSITORY.
// 
// https://github.com/matter-labs/era-contracts/blob/5e7d0b405b49f42131565a291a82f22565f72e33/l1-contracts/contracts/bridgehub/IBridgehub.sol
// https://github.com/matter-labs/era-contracts/blob/5e7d0b405b49f42131565a291a82f22565f72e33/l1-contracts/contracts/common/Messaging.sol

/// @dev The enum that represents the transaction execution status
/// @param Failure The transaction execution failed
/// @param Success The transaction execution succeeded
enum TxStatus {
    Failure,
    Success
}

/// @dev The log passed from L2
/// @param l2ShardId The shard identifier, 0 - rollup, 1 - porter
/// All other values are not used but are reserved for the future
/// @param isService A boolean flag that is part of the log along with `key`, `value`, and `sender` address.
/// This field is required formally but does not have any special meaning
/// @param txNumberInBatch The L2 transaction number in a Batch, in which the log was sent
/// @param sender The L2 address which sent the log
/// @param key The 32 bytes of information that was sent in the log
/// @param value The 32 bytes of information that was sent in the log
// Both `key` and `value` are arbitrary 32-bytes selected by the log sender
struct L2Log {
    uint8 l2ShardId;
    bool isService;
    uint16 txNumberInBatch;
    address sender;
    bytes32 key;
    bytes32 value;
}

/// @dev An arbitrary length message passed from L2
/// @notice Under the hood it is `L2Log` sent from the special system L2 contract
/// @param txNumberInBatch The L2 transaction number in a Batch, in which the message was sent
/// @param sender The address of the L2 account from which the message was passed
/// @param data An arbitrary length message
struct L2Message {
    uint16 txNumberInBatch;
    address sender;
    bytes data;
}

struct L2TransactionRequestDirect {
    uint256 chainId;
    uint256 mintValue;
    address l2Contract;
    uint256 l2Value;
    bytes l2Calldata;
    uint256 l2GasLimit;
    uint256 l2GasPerPubdataByteLimit;
    bytes[] factoryDeps;
    address refundRecipient;
}

struct L2TransactionRequestTwoBridgesOuter {
    uint256 chainId;
    uint256 mintValue;
    uint256 l2Value;
    uint256 l2GasLimit;
    uint256 l2GasPerPubdataByteLimit;
    address refundRecipient;
    address secondBridgeAddress;
    uint256 secondBridgeValue;
    bytes secondBridgeCalldata;
}

struct L2TransactionRequestTwoBridgesInner {
    bytes32 magicValue;
    address l2Contract;
    bytes l2Calldata;
    bytes[] factoryDeps;
    bytes32 txDataHash;
}

struct BridgehubMintCTMAssetData {
    uint256 chainId;
    bytes32 baseTokenAssetId;
    bytes ctmData;
    bytes chainData;
}

struct BridgehubBurnCTMAssetData {
    uint256 chainId;
    bytes ctmData;
    bytes chainData;
}

/// @author Matter Labs
/// @custom:security-contact security@matterlabs.dev
interface IBridgehub {
    /// @notice pendingAdmin is changed
    /// @dev Also emitted when new admin is accepted and in this case, `newPendingAdmin` would be zero address
    event NewPendingAdmin(address indexed oldPendingAdmin, address indexed newPendingAdmin);

    /// @notice Admin changed
    event NewAdmin(address indexed oldAdmin, address indexed newAdmin);

    /// @notice CTM asset registered
    event AssetRegistered(
        bytes32 indexed assetInfo,
        address indexed _assetAddress,
        bytes32 indexed additionalData,
        address sender
    );

    event SettlementLayerRegistered(uint256 indexed chainId, bool indexed isWhitelisted);

    /// @notice Starts the transfer of admin rights. Only the current admin or owner can propose a new pending one.
    /// @notice New admin can accept admin rights by calling `acceptAdmin` function.
    /// @param _newPendingAdmin Address of the new admin
    function setPendingAdmin(address _newPendingAdmin) external;

    /// @notice Accepts transfer of admin rights. Only pending admin can accept the role.
    function acceptAdmin() external;

    /// Getters
    function chainTypeManagerIsRegistered(address _chainTypeManager) external view returns (bool);

    function chainTypeManager(uint256 _chainId) external view returns (address);

    function assetIdIsRegistered(bytes32 _baseTokenAssetId) external view returns (bool);

    function baseToken(uint256 _chainId) external view returns (address);

    function baseTokenAssetId(uint256 _chainId) external view returns (bytes32);

    function messageRoot() external view returns (address);

    function getZKChain(uint256 _chainId) external view returns (address);

    function getAllZKChains() external view returns (address[] memory);

    function getAllZKChainChainIDs() external view returns (uint256[] memory);

    function migrationPaused() external view returns (bool);

    function admin() external view returns (address);

    function assetRouter() external view returns (address);

    /// Mailbox forwarder

    function proveL2MessageInclusion(
        uint256 _chainId,
        uint256 _batchNumber,
        uint256 _index,
        L2Message calldata _message,
        bytes32[] calldata _proof
    ) external view returns (bool);

    function proveL2LogInclusion(
        uint256 _chainId,
        uint256 _batchNumber,
        uint256 _index,
        L2Log memory _log,
        bytes32[] calldata _proof
    ) external view returns (bool);

    function proveL1ToL2TransactionStatus(
        uint256 _chainId,
        bytes32 _l2TxHash,
        uint256 _l2BatchNumber,
        uint256 _l2MessageIndex,
        uint16 _l2TxNumberInBatch,
        bytes32[] calldata _merkleProof,
        TxStatus _status
    ) external view returns (bool);

    function requestL2TransactionDirect(
        L2TransactionRequestDirect calldata _request
    ) external payable returns (bytes32 canonicalTxHash);

    function requestL2TransactionTwoBridges(
        L2TransactionRequestTwoBridgesOuter calldata _request
    ) external payable returns (bytes32 canonicalTxHash);

    function l2TransactionBaseCost(
        uint256 _chainId,
        uint256 _gasPrice,
        uint256 _l2GasLimit,
        uint256 _l2GasPerPubdataByteLimit
    ) external view returns (uint256);

    //// Registry

    function createNewChain(
        uint256 _chainId,
        address _chainTypeManager,
        bytes32 _baseTokenAssetId,
        uint256 _salt,
        address _admin,
        bytes calldata _initData,
        bytes[] calldata _factoryDeps
    ) external returns (uint256 chainId);

    function addChainTypeManager(address _chainTypeManager) external;

    function removeChainTypeManager(address _chainTypeManager) external;

    function addTokenAssetId(bytes32 _baseTokenAssetId) external;

    function setAddresses(
        address _sharedBridge,
        address _l1CtmDeployer,
        address _messageRoot,
        address _chainAssetHandler
    ) external;

    function setChainAssetHandler(address _chainAssetHandler) external;

    event NewChain(uint256 indexed chainId, address chainTypeManager, address indexed chainGovernance);

    event ChainTypeManagerAdded(address indexed chainTypeManager);

    event ChainTypeManagerRemoved(address indexed chainTypeManager);

    event BaseTokenAssetIdRegistered(bytes32 indexed assetId);

    function whitelistedSettlementLayers(uint256 _chainId) external view returns (bool);

    function registerSettlementLayer(uint256 _newSettlementLayerChainId, bool _isWhitelisted) external;

    function settlementLayer(uint256 _chainId) external view returns (uint256);

    // function finalizeMigrationToGateway(
    //     uint256 _chainId,
    //     address _baseToken,
    //     address _sharedBridge,
    //     address _admin,
    //     uint256 _expectedProtocolVersion,
    //     ZKChainCommitment calldata _commitment,
    //     bytes calldata _diamondCut
    // ) external;

    function forwardTransactionOnGateway(
        uint256 _chainId,
        bytes32 _canonicalTxHash,
        uint64 _expirationTimestamp
    ) external;

    function ctmAssetIdFromChainId(uint256 _chainId) external view returns (bytes32);

    function ctmAssetIdFromAddress(address _ctmAddress) external view returns (bytes32);

    function l1CtmDeployer() external view returns (address);

    function ctmAssetIdToAddress(bytes32 _assetInfo) external view returns (address);

    function setCTMAssetAddress(bytes32 _additionalData, address _assetAddress) external;

    function L1_CHAIN_ID() external view returns (uint256);

    function chainAssetHandler() external view returns (address);

    function registerAlreadyDeployedZKChain(uint256 _chainId, address _hyperchain) external;

    function registerLegacyChain(uint256 _chainId) external;

    function pauseMigration() external;

    function unpauseMigration() external;

    function forwardedBridgeBurnSetSettlementLayer(
        uint256 _chainId,
        uint256 _newSettlementLayerChainId
    ) external returns (address zkChain, address ctm);

    function forwardedBridgeMint(
        bytes32 _assetId,
        uint256 _chainId,
        bytes32 _baseTokenAssetId
    ) external returns (address zkChain, address ctm);

    function registerNewZKChain(uint256 _chainId, address _zkChain, bool _checkMaxNumberOfZKChains) external;

    function forwardedBridgeRecoverFailedTransfer(uint256 _chainId) external returns (address zkChain, address ctm);
}