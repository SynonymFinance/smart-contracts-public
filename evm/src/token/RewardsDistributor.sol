// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.0;

import "@solmate/utils/MerkleProofLib.sol";
import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts-upgradeable/proxy/utils/Initializable.sol";
import {OwnableUpgradeable} from "@openzeppelin/contracts-upgradeable/access/OwnableUpgradeable.sol";

/**
 * @title RewardsDistributor
 * @dev Contract for claiming rewards via merkle proofs. One deployment per reward token.
 */
contract RewardsDistributor is Initializable, OwnableUpgradeable {
    using SafeERC20 for IERC20;

    address public token;
    uint256 public currentEpoch; // 1-based

    mapping(uint256 => bytes32) public roots; // epoch => root
    mapping(uint256 => mapping(address => bool)) public isClaimed; // epoch => account => claimed?

    /**
     * @notice Allows the caller tokens from the merkle tree, given they provide a valid `proof` for the `epoch`
     * @param proof Merkle proof of the claim
     * @param epoch Epoch of the claim
     * @param index Index of the claim
     * @param amount Amount of tokens to claim
     */
    struct ClaimInput {
        bytes32[] proof;
        uint256 epoch;
        uint256 index;
        uint256 amount;
    }

    error AlreadyClaimed();
    error InvalidEpoch();
    error InvalidProof();
    error InvalidRoot();

    event Claimed(uint256 indexed epoch, address indexed recipient, uint256 amount);
    event RootAdded(address indexed admin, uint256 indexed epoch, uint256 totalAllocation, bytes32 root);

    /// @custom:oz-upgrades-unsafe-allow constructor
    constructor() {
        _disableInitializers();
    }

    function initialize(address _token) public initializer {
        OwnableUpgradeable.__Ownable_init(msg.sender);
        __RewardsDistributor_init(_token);
    }

    function __RewardsDistributor_init(address _token) internal onlyInitializing {
        token = _token;
    }

    function claim(ClaimInput[] calldata inputs) virtual external {
        uint256 totalAmount = 0;
        for (uint256 i = 0; i < inputs.length; i++) {
            ClaimInput calldata input = inputs[i];
            address recipient = msg.sender;

            _verifyMerkleProof(input, recipient);

            isClaimed[input.epoch][recipient] = true;

            totalAmount += input.amount;

            emit Claimed(input.epoch, recipient, input.amount);
        }

        IERC20(token).safeTransfer(msg.sender, totalAmount);
    }

    /**
     * @notice Adds a new merkle root for the new epoch
     * @param _merkleRoot Merkle root to add
     * @param _totalAllocation Total amount of tokens to be distributed in this epoch
     */
    function newRoot(bytes32 _merkleRoot, uint256 _totalAllocation) external onlyOwner {
        if (_merkleRoot == bytes32(0) || _totalAllocation == 0) revert InvalidRoot();

        uint256 _epoch = ++currentEpoch;
        roots[_epoch] = _merkleRoot;

        IERC20(token).safeTransferFrom(msg.sender, address(this), _totalAllocation);

        emit RootAdded(msg.sender, _epoch, _totalAllocation, _merkleRoot);
    }

    function _verifyMerkleProof(ClaimInput calldata input, address recipient) internal view {
        if (isClaimed[input.epoch][recipient]) {
            revert AlreadyClaimed();
        }

        if (roots[input.epoch] == bytes32(0)) {
            revert InvalidEpoch();
        }

        bytes32 leaf = keccak256(abi.encodePacked(input.index, recipient, token, input.amount));

        if (!MerkleProofLib.verify(input.proof, roots[input.epoch], leaf)) {
            revert InvalidProof();
        }
    }

    function setCurrentEpoch(uint256 _epoch) external onlyOwner {
        currentEpoch = _epoch;
    }
}
