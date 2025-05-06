// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.0;

import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {IPausable} from "../IPausable.sol";

interface IStreamingRewardsDistributor is IPausable {
    struct FlowConfig {
        uint256 rewardsPerSecond;
        uint256 startTimestamp;
        uint256[20] __gap;
    }

    struct Shares {
        uint256 shares;
        uint256 accruedRewardsPerShare;
        uint256[20] __gap;
    }

    function getPoolShares(bytes32 _id) external view returns (Shares memory);
    function getUserShares(address _user, bytes32 _id) external view returns (Shares memory);
    function getCurrentFlow(bytes32 _id) external view returns (FlowConfig memory);
    function getFutureFlow(bytes32 _id) external view returns (FlowConfig memory);
    function getPastFlows(bytes32 _id) external view returns (FlowConfig[] memory);
    function getPastFlowCount(bytes32 _id) external view returns (uint256);
    function getPastFlow(bytes32 _id, uint256 _idx) external view returns (FlowConfig memory);
    function getFlowRate(bytes32 _poolId) external view returns (uint256);
    function getUserFlowRate(address _user, bytes32 _poolId) external view returns (uint256);
    function getTotalUserFlowRate(address _user) external view returns (uint256);
    function getTotalFlowRate() external view returns (uint256);
    function getTotalClaimableRewards() external view returns (uint256);
    function getClaimableRewards(address _user) external view returns (uint256);
    function getRewardSurplus() external view returns (uint256);
    function getTimeToRewardDeficit() external view returns (uint256);
    function isPoolRegistered(bytes32) external view returns (bool);
    function totalClaimed() external view returns (uint256);
    function rewardToken() external view returns (IERC20);
    function isAuthorizedClaimDelegator(address) external view returns (bool);

    function claim() external;
    function delegatedClaim(address _user) external;

    event AuthorizedDelegatorStatusChanged(address indexed delegator, bool status);
    event Claimed(address indexed recipient, address indexed token, uint256 amount);
    event FutureFlowSet(bytes32 indexed poolId, uint256 startTime, uint256 rewardsPerSecond);
    event PoolRegistered(bytes32 indexed poolId);
    event UserSharesChanged(bytes32 indexed poolId, address indexed user, uint256 userShares, uint256 poolShares);

    error ArrayLengthMismatch();
    error FutureTimeRequired();
    error InsufficientRewardTokenBalance();
    error InvalidInput();
    error NothingToClaim();
    error UnauthorizedDelegator();
}
