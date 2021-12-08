// SPDX-License-Identifier: MIT

pragma solidity ^0.8.0;
pragma experimental ABIEncoderV2;

import "../interfaces/IBatchTreeUpdateVerifier.sol";
import "@openzeppelin/contracts/proxy/utils/Initializable.sol";
import "hardhat/console.sol";

/// @dev This contract holds a merkle tree of all tornado cash deposit and withdrawal events
contract AnchorTrees is Initializable {
  address public immutable governance;
  //Roots Stuff
  uint32 public constant ROOT_HISTORY_SIZE = 5;
  uint32 public currentDepositRootIndex = 0;
  uint32 public currentWithdrawalRootIndex = 0;
  mapping(uint256 => bytes32) public depositRoots;
  mapping(uint256 => bytes32) public withdrawalRoots;
  // bytes32 public depositRoot;
  // bytes32 public previousDepositRoot;
  // bytes32 public withdrawalRoot;
  // bytes32 public previousWithdrawalRoot;
  //End Roots Stuff
  address public anchorProxy;
  IBatchTreeUpdateVerifier public treeUpdateVerifier;

  uint256 public constant CHUNK_TREE_HEIGHT = 8;
  uint256 public constant CHUNK_SIZE = 2**CHUNK_TREE_HEIGHT;
  uint256 public constant ITEM_SIZE = 32 + 20 + 4;
  uint256 public constant BYTES_SIZE = 32 + 32 + 4 + CHUNK_SIZE * ITEM_SIZE;
  uint256 public constant SNARK_FIELD = 21888242871839275222246405745257275088548364400416034343698204186575808495617;
  uint256 DEFAULT_ZERO_ROOT = 16640205414190175414380077665118269450294358858897019640557533278896634808665; //Need to properly fill in...

  mapping(uint256 => bytes32) public deposits;
  uint256 public depositsLength;
  uint256 public lastProcessedDepositLeaf = 0;

  mapping(uint256 => bytes32) public withdrawals;
  uint256 public withdrawalsLength;
  uint256 public lastProcessedWithdrawalLeaf = 0;

  //Start Edge Information
  uint8 public immutable maxEdges;

  struct Edge {
    uint256 chainID;
    bytes32 depositRoot;
    bytes32 withdrawalRoot;
    uint256 latestLeafIndex;
  }

  // maps sourceChainID to the index in the edge list
  mapping(uint256 => uint256) public edgeIndex;
  mapping(uint256 => bool) public edgeExistsForChain;
  Edge[] public edgeList;

  // map to store chainID => (rootIndex => [depositRoot, withdrawalRoot]) to track neighbor histories
  mapping(uint256 => mapping(uint32 => bytes32)) public neighborDepositRoots;
  mapping(uint256 => mapping(uint32 => bytes32)) public neighborWithdrawalRoots;
  // map to store the current historical [depositRoot, withdrawalRoot] index for a chainID
  mapping(uint256 => uint32) public currentNeighborDepositRootIndex;
  mapping(uint256 => uint32) public currentNeighborWithdrawalRootIndex;
  //End Edge Information

  event DepositData(address instance, bytes32 indexed hash, uint256 blockTimestamp, uint256 index);
  event WithdrawalData(address instance, bytes32 indexed hash, uint256 blockTimestamp, uint256 index);
  event VerifierUpdated(address newVerifier);
  event ProxyUpdated(address newProxy);
  event EdgeAddition(uint256 chainID, uint256 latestLeafIndex, bytes32 depositRoot, bytes32 withdrawalRoot);
  event EdgeUpdate(uint256 chainID, uint256 latestLeafIndex, bytes32 depositRoot, bytes32 withdrawalRoot);

  struct TreeLeaf {
    bytes32 hash;
    address instance;
    uint256 blockTimestamp;
  }

  modifier onlyAnchorProxy {
    require(msg.sender == anchorProxy, "Not authorized");
    _;
  }

  modifier onlyGovernance() {
    require(msg.sender == governance, "Only governance can perform this action");
    _;
  }

  constructor(
    address _governance,
    uint8 _maxEdges
  ) {
    governance = _governance;
    maxEdges = _maxEdges;
  }

  function initialize(address _anchorProxy, IBatchTreeUpdateVerifier _treeUpdateVerifier) public initializer onlyGovernance {
    anchorProxy = _anchorProxy;
    treeUpdateVerifier = _treeUpdateVerifier;

    //How to initialize deposits[0], withdrawals[0]?
    depositRoots[0] = bytes32(DEFAULT_ZERO_ROOT);
    withdrawalRoots[0] = bytes32(DEFAULT_ZERO_ROOT);
  }

  /// @dev Queue a new deposit data to be inserted into a merkle tree
  function registerDeposit(address _instance, bytes32 _commitment) public onlyAnchorProxy {
    uint256 _depositsLength = depositsLength;
    deposits[_depositsLength] = keccak256(abi.encode(_instance, _commitment, blockTimestamp()));
    emit DepositData(_instance, _commitment, blockTimestamp(), _depositsLength);
    depositsLength = _depositsLength + 1;
  }

  /// @dev Queue a new withdrawal data to be inserted into a merkle tree
  function registerWithdrawal(address _instance, bytes32 _nullifierHash) public onlyAnchorProxy {
    uint256 _withdrawalsLength = withdrawalsLength;
    withdrawals[_withdrawalsLength] = keccak256(abi.encode(_instance, _nullifierHash, blockTimestamp()));
    emit WithdrawalData(_instance, _nullifierHash, blockTimestamp(), _withdrawalsLength);
    withdrawalsLength = _withdrawalsLength + 1;
  }

  /// @dev Insert a full batch of queued deposits into a merkle tree
  /// @param _proof A snark proof that elements were inserted correctly
  /// @param _argsHash A hash of snark inputs
  /// @param _argsHash Current merkle tree root
  /// @param _newRoot Updated merkle tree root
  /// @param _pathIndices Merkle path to inserted batch
  /// @param _events A batch of inserted events (leaves)
  function updateDepositTree(
    bytes calldata _proof,
    bytes32 _argsHash,
    bytes32 _currentRoot,
    bytes32 _newRoot,
    uint32 _pathIndices,
    TreeLeaf[CHUNK_SIZE] calldata _events
  ) public {
    uint256 offset = lastProcessedDepositLeaf;
    require(_currentRoot == depositRoots[currentDepositRootIndex], "Proposed deposit root is invalid");
    require(_pathIndices == offset >> CHUNK_TREE_HEIGHT, "Incorrect deposit insert index");

    bytes memory data = new bytes(BYTES_SIZE);
    assembly {
      mstore(add(data, 0x44), _pathIndices)
      mstore(add(data, 0x40), _newRoot)
      mstore(add(data, 0x20), _currentRoot)
    }
    for (uint256 i = 0; i < CHUNK_SIZE; i++) {
      (bytes32 hash, address instance, uint256 blockTimestamp) = (_events[i].hash, _events[i].instance, _events[i].blockTimestamp);
      bytes32 leafHash = keccak256(abi.encode(instance, hash, blockTimestamp));
      bytes32 deposit = deposits[offset + i];
      require(leafHash == deposit, "Incorrect deposit");
      assembly {
        let itemOffset := add(data, mul(ITEM_SIZE, i))
        mstore(add(itemOffset, 0x7c), blockTimestamp)
        mstore(add(itemOffset, 0x5c), instance)
        mstore(add(itemOffset, 0x48), hash)
      }
      delete deposits[offset + i];
    }

    uint256 argsHash = uint256(sha256(data)) % SNARK_FIELD;
    require(argsHash == uint256(_argsHash), "Invalid args hash");
    require(treeUpdateVerifier.verifyProof(_proof, [argsHash]), "Invalid deposit tree update proof");

    uint32 newDepositRootIndex = (currentDepositRootIndex + 1) % ROOT_HISTORY_SIZE;
    currentDepositRootIndex = newDepositRootIndex;
    depositRoots[newDepositRootIndex] = _newRoot;
    lastProcessedDepositLeaf = offset + CHUNK_SIZE;
  }

  /// @dev Insert a full batch of queued withdrawals into a merkle tree
  /// @param _proof A snark proof that elements were inserted correctly
  /// @param _argsHash A hash of snark inputs
  /// @param _argsHash Current merkle tree root
  /// @param _newRoot Updated merkle tree root
  /// @param _pathIndices Merkle path to inserted batch
  /// @param _events A batch of inserted events (leaves)
  function updateWithdrawalTree(
    bytes calldata _proof,
    bytes32 _argsHash,
    bytes32 _currentRoot,
    bytes32 _newRoot,
    uint32 _pathIndices,
    TreeLeaf[CHUNK_SIZE] calldata _events
  ) public {
    uint256 offset = lastProcessedWithdrawalLeaf;
    require(_currentRoot == withdrawalRoots[currentWithdrawalRootIndex], "Proposed withdrawal root is invalid");
    require(_pathIndices == offset >> CHUNK_TREE_HEIGHT, "Incorrect withdrawal insert index");

    bytes memory data = new bytes(BYTES_SIZE);
    assembly {
      mstore(add(data, 0x44), _pathIndices)
      mstore(add(data, 0x40), _newRoot)
      mstore(add(data, 0x20), _currentRoot)
    }
    for (uint256 i = 0; i < CHUNK_SIZE; i++) {
      (bytes32 hash, address instance, uint256 blockTimestamp) = (_events[i].hash, _events[i].instance, _events[i].blockTimestamp);
      bytes32 leafHash = keccak256(abi.encode(instance, hash, blockTimestamp));
      bytes32 withdrawal = withdrawals[offset + i];
      require(leafHash == withdrawal, "Incorrect withdrawal");
      assembly {
        let itemOffset := add(data, mul(ITEM_SIZE, i))
        mstore(add(itemOffset, 0x7c), blockTimestamp)
        mstore(add(itemOffset, 0x5c), instance)
        mstore(add(itemOffset, 0x48), hash)
      }
      delete withdrawals[offset + i];
    }

    uint256 argsHash = uint256(sha256(data)) % SNARK_FIELD;
    require(argsHash == uint256(_argsHash), "Invalid args hash");
    require(treeUpdateVerifier.verifyProof(_proof, [argsHash]), "Invalid withdrawal tree update proof");

    uint32 newWithdrawalRootIndex = (currentWithdrawalRootIndex + 1) % ROOT_HISTORY_SIZE;
    currentWithdrawalRootIndex = newWithdrawalRootIndex;
    withdrawalRoots[newWithdrawalRootIndex] = _newRoot;
    lastProcessedWithdrawalLeaf = offset + CHUNK_SIZE;
  }

  /**
    @dev Whether the root is present in the root history
  */
  function isKnownDepositRoot(bytes32 _depositRoot) public view returns (bool) {
    if (_depositRoot == 0) {
      return false;
    }
    uint32 _currentDepositRootIndex = currentDepositRootIndex;
    uint32 i = _currentDepositRootIndex;
    do {
      if (_depositRoot == depositRoots[i]) {
        return true;
      }
      if (i == 0) {
        i = ROOT_HISTORY_SIZE;
      }
      i--;
    } while (i != _currentDepositRootIndex);
    return false;
  }

  /**
    @dev Whether the root is present in the root history
  */
  function isKnownWithdrawalRoot(bytes32 _withdrawalRoot) public view returns (bool) {
    if (_withdrawalRoot == 0) {
      return false;
    }
    uint32 _currentWithdrawalRootIndex = currentWithdrawalRootIndex;
    uint32 i = _currentWithdrawalRootIndex;
    do {
      if (_withdrawalRoot == withdrawalRoots[i]) {
        return true;
      }
      if (i == 0) {
        i = ROOT_HISTORY_SIZE;
      }
      i--;
    } while (i != _currentWithdrawalRootIndex);
    return false;
  }

    /** @dev */
  function getLatestNeighborRoots() public view returns (bytes32[] memory depositRoots, bytes32[] memory withdrawalRoots) {
    depositRoots = new bytes32[](maxEdges);
    withdrawalRoots = new bytes32[](maxEdges);
    for (uint256 i = 0; i < maxEdges; i++) {
      if (edgeList.length >= i + 1) {
        depositRoots[i] = edgeList[i].depositRoot;
       withdrawalRoots[i] = edgeList[i].withdrawalRoot;
      } else {
        // merkle tree height for zeros
        depositRoots[i] = bytes32(0x00); //was previously zeros(levels);
        withdrawalRoots[i] = bytes32(0x00); //was previously zeros(levels);
      }
    }
  }

  /** @dev */
  function isKnownNeighborDepositRoot(uint256 neighborChainID, bytes32 _depositRoot) public view returns (bool) {
    if (_depositRoot == 0) {
      return false;
    }
    uint32 _currentDepositRootIndex = currentNeighborDepositRootIndex[neighborChainID];
    uint32 i = _currentDepositRootIndex;
    do {
      if (_depositRoot == neighborDepositRoots[neighborChainID][i]) {
        return true;
      }
      if (i == 0) {
        i = ROOT_HISTORY_SIZE;
      }
      i--;
    } while (i != _currentDepositRootIndex);
    return false;
  }

 /** @dev */
  function isKnownNeighborWithdrawalRoot(uint256 neighborChainID, bytes32 _withdrawalRoot) public view returns (bool) {
    if (_withdrawalRoot == 0) {
      return false;
    }
    uint32 _currentWithdrawalRootIndex = currentNeighborDepositRootIndex[neighborChainID];
    uint32 i = _currentWithdrawalRootIndex;
    do {
      if (_withdrawalRoot == neighborWithdrawalRoots[neighborChainID][i]) {
        return true;
      }
      if (i == 0) {
        i = ROOT_HISTORY_SIZE;
      }
      i--;
    } while (i != _currentWithdrawalRootIndex);
    return false;
  }

  function validateRoots(bytes32[] memory _depositRoots, bytes32[] memory _withdrawalRoots) public view returns (bool) {
    require(isKnownDepositRoot(_depositRoots[0]), "Cannot find your deposit merkle root");
    require(isKnownWithdrawalRoot(_withdrawalRoots[0]), "Cannot find your withdrawal merkle root");
    require(_depositRoots.length == maxEdges + 1, "Incorrect deposit root array length");
    require(_withdrawalRoots.length == maxEdges + 1, "Incorrect withdrawal root array length");
    for (uint i = 0; i < edgeList.length; i++) {
      Edge memory _edge = edgeList[i];
      require(isKnownNeighborDepositRoot(_edge.chainID, _depositRoots[i+1]), "deposit Neighbor root not found");
      require(isKnownNeighborWithdrawalRoot(_edge.chainID, _withdrawalRoots[i+1]), "withdrawal Neighbor root not found");
    }
    return true;
  }

  function setAnchorProxyContract(address _anchorProxy) external onlyGovernance {
    anchorProxy = _anchorProxy;
    emit ProxyUpdated(_anchorProxy);
  }

  function setVerifierContract(IBatchTreeUpdateVerifier _treeUpdateVerifier) external onlyGovernance {
    treeUpdateVerifier = _treeUpdateVerifier;
    emit VerifierUpdated(address(_treeUpdateVerifier));
  }

  function blockTimestamp() public view virtual returns (uint256) {
    return block.timestamp;
  }
}
