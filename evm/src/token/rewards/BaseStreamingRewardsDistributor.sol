// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.0;

import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {Initializable} from "@openzeppelin/contracts-upgradeable/proxy/utils/Initializable.sol";
import {OwnableUpgradeable} from "@openzeppelin/contracts-upgradeable/access/OwnableUpgradeable.sol";
import {PausableUpgradeable} from "@openzeppelin/contracts-upgradeable/utils/PausableUpgradeable.sol";

import {IMoneyMarketRewardsDistributor} from "../../interfaces/rewards/IMoneyMarketRewardsDistributor.sol";
import {ISSynoRewardsDistributor} from "../../interfaces/rewards/ISSynoRewardsDistributor.sol";
import {IVlSynoRewardsDistributor} from "../../interfaces/rewards/IVlSynoRewardsDistributor.sol";
import {IStreamingRewardsDistributor, IPausable} from "../../interfaces/rewards/IStreamingRewardsDistributor.sol";
import {IHub} from "../../interfaces/IHub.sol";

abstract contract BaseStreamingRewardsDistributor is IStreamingRewardsDistributor, Initializable, OwnableUpgradeable, PausableUpgradeable {
    using SafeERC20 for IERC20;

    uint256 public constant FLOW_PRECISION = 1e18;

    struct RewardPool {
        Shares totalShares;
        uint256 lastUpdate;
        FlowConfig currentFlow;
        FlowConfig futureFlow;
        FlowConfig[] pastFlows;
        mapping(address => Shares) userShares;
        uint256[20] __gap;
    }

    bytes32[] registeredPools;
    mapping(bytes32 => bool) public isPoolRegistered;

    // pool id => RewardPool
    mapping(bytes32 => RewardPool) pools;
    // user => claimable
    mapping(address => uint256) userClaims;
    uint256 totalClaimableInFlowPrecision;
    uint256 public totalClaimed;

    mapping(address => bool) public isAuthorizedClaimDelegator;


    IERC20 public override rewardToken;

    uint256[50] private __gap;

    modifier forwardAllPools() {
        for (uint256 i = 0; i < registeredPools.length; i++) {
            _forwardPool(registeredPools[i]);
        }
        _;
    }

    modifier forwardPool(bytes32 _poolId) {
        _forwardPool(_poolId);
        _;
    }

    modifier onlyClaimDelegator {
        if (!isAuthorizedClaimDelegator[msg.sender]) {
            revert UnauthorizedDelegator();
        }
        _;
    }

    /// @custom:oz-upgrades-unsafe-allow constructor
    constructor() {
        _disableInitializers();
    }

    function initialize(address _rewardToken) public virtual initializer {
        OwnableUpgradeable.__Ownable_init(msg.sender);
        PausableUpgradeable.__Pausable_init();
        rewardToken = IERC20(_rewardToken);
    }

    //
    // GETTERS
    //

    function paused() public view override(IPausable, PausableUpgradeable) returns (bool) {
        return PausableUpgradeable.paused();
    }

    function getPoolShares(bytes32 _id) public view override returns (Shares memory) {
        return pools[_id].totalShares;
    }

    function getUserShares(address _user, bytes32 _id) public view override returns (Shares memory) {
        return pools[_id].userShares[_user];
    }

    function getCurrentFlow(bytes32 _id) public view override returns (FlowConfig memory) {
        return _shouldSwitchToFutureFlow(_id) ? pools[_id].futureFlow : pools[_id].currentFlow;
    }

    function getFutureFlow(bytes32 _id) public view override returns (FlowConfig memory) {
        return pools[_id].futureFlow;
    }

    function getPastFlows(bytes32 _id) public view override returns (FlowConfig[] memory) {
        return pools[_id].pastFlows;
    }

    function getPastFlowCount(bytes32 _id) public view override returns (uint256) {
        return pools[_id].pastFlows.length;
    }

    function getPastFlow(bytes32 _id, uint256 _idx) public view override returns (FlowConfig memory) {
        return pools[_id].pastFlows[_idx];
    }

    function getFlowRate(bytes32 _poolId) public virtual view override returns (uint256) {
        return pools[_poolId].totalShares.shares > 0 ? getCurrentFlow(_poolId).rewardsPerSecond / FLOW_PRECISION : 0;
    }

    function getUserFlowRate(address _user, bytes32 _poolId) public virtual view override returns (uint256) {
        RewardPool storage pool = pools[_poolId];
        if (pool.userShares[_user].shares == 0) {
            return 0;
        }

        return getFlowRate(_poolId) * pool.userShares[_user].shares / pool.totalShares.shares;
    }

    function getTotalUserFlowRate(address _user) public view override returns (uint256) {
        uint256 total = 0;
        for (uint256 i = 0; i < registeredPools.length; i++) {
            total += getUserFlowRate(_user, registeredPools[i]);
        }
        return total;
    }

    function getTotalFlowRate() public view override returns (uint256) {
        uint256 total = 0;
        for (uint256 i = 0; i < registeredPools.length; i++) {
            total += getFlowRate(registeredPools[i]);
        }
        return total;
    }

    function getTotalClaimableRewards() public virtual view override returns (uint256) {
        uint256 total = 0;
        for (uint256 i = 0; i < registeredPools.length; i++) {
            bytes32 poolId = registeredPools[i];
            Shares memory forwarded = _getForwardedPoolShares(poolId);
            Shares storage current = pools[poolId].totalShares;
            total += forwarded.shares * (forwarded.accruedRewardsPerShare - current.accruedRewardsPerShare);
        }
        return (total + totalClaimableInFlowPrecision) / FLOW_PRECISION;
    }

    function getClaimableRewards(address _user) public virtual view override returns (uint256 total) {
        uint256 claimable = 0;
        for (uint256 i = 0; i < registeredPools.length; i++) {
            bytes32 poolId = registeredPools[i];
            Shares memory poolShares = _getForwardedPoolShares(poolId);
            claimable += pools[poolId].userShares[_user].shares * (poolShares.accruedRewardsPerShare - pools[poolId].userShares[_user].accruedRewardsPerShare);
        }
        return claimable / FLOW_PRECISION + userClaims[_user];
    }

    function getRewardSurplus() public view override returns (uint256) {
        uint256 totalClaimable = getTotalClaimableRewards();
        uint256 balance = rewardToken.balanceOf(address(this));
        return totalClaimable > balance ? 0 : balance - totalClaimable;
    }

    function getTimeToRewardDeficit() public view override returns (uint256) {
        uint256 flowRate = getTotalFlowRate();
        if (flowRate == 0) {
            return type(uint256).max;
        }
        return getRewardSurplus() / flowRate;
    }

    //
    // SETTERS
    //

    function setIsAuthorizedDelegator(address _delegator, bool _authorized) external onlyOwner {
        if (isAuthorizedClaimDelegator[_delegator] == _authorized) {
            revert InvalidInput();
        }

        isAuthorizedClaimDelegator[_delegator] = _authorized;
        emit AuthorizedDelegatorStatusChanged(_delegator, _authorized);
    }

    /**
     * @dev a helper setter to set a flow based on an amount of tokens distributed over a period of time instead of a tokens per second rate.
     *      calls the base setter internally with rewards per second as _tokensToDistribute / _duration in FLOW_PRECISION
     */
    function setFutureFlow(bytes32 _poolId, uint256 _startTime, uint256 _duration, uint256 _tokensToDistribute) public onlyOwner {
        setFutureFlow(_poolId, _startTime, _tokensToDistribute * FLOW_PRECISION / _duration);
    }

    function setFutureFlow(bytes32 _poolId, uint256 _startTime, uint256 _rewardsPerSecondInFlowPrecision) public virtual onlyOwner whenNotPaused forwardPool(_poolId) {
        _setFutureFlow(_poolId, _startTime, _rewardsPerSecondInFlowPrecision);
    }

    function setFutureFlows(
        uint256 _startTime,
        uint256 _duration,
        bytes32[] memory _poolIds,
        uint256[] memory _tokensToDistribute
    ) public onlyOwner {
        if (_poolIds.length != _tokensToDistribute.length) {
            revert ArrayLengthMismatch();
        }

        for (uint256 i = 0; i < _poolIds.length; i++) {
            setFutureFlow(_poolIds[i], _startTime, _duration, _tokensToDistribute[i]);
        }
    }

    function setUserShares(address _user, bytes32 _poolId, uint256 _newShares) internal virtual whenNotPaused {
        _handleAccrual(_user, _poolId);
        uint256 newTotal = pools[_poolId].totalShares.shares - pools[_poolId].userShares[_user].shares + _newShares;
        pools[_poolId].userShares[_user].shares = _newShares;
        pools[_poolId].totalShares.shares = newTotal;
        emit UserSharesChanged(_poolId, _user, _newShares, newTotal);
    }

    function setPaused(bool _paused) external onlyOwner {
        if (_paused) {
            _pause();
        } else {
            _unpause();
        }
    }

    //
    // INTERACTIONS
    //

    function claim() external override whenNotPaused {
        _claim(msg.sender);
    }

    function delegatedClaim(address _user) external override whenNotPaused {
        if (!isAuthorizedClaimDelegator[msg.sender]) {
            revert UnauthorizedDelegator();
        }
        _claim(_user);
    }

    function withdraw(uint256 _amount) external onlyOwner {
        if (_amount > getRewardSurplus()) {
            revert InsufficientRewardTokenBalance();
        }

        rewardToken.safeTransfer(msg.sender, _amount);
    }

    //
    // INTERNALS
    //

    function _setFutureFlow(bytes32 _poolId, uint256 _startTime, uint256 _rewardsPerSecondInFlowPrecision) internal forwardPool(_poolId) {
        if (_startTime < block.timestamp) {
            revert FutureTimeRequired();
        }

        _registerPool(_poolId);

        // set current flow with a future date if current flow is not set
        FlowConfig storage flow;
        if (pools[_poolId].currentFlow.startTimestamp == 0) {
            flow = pools[_poolId].currentFlow;
        } else {
            flow = pools[_poolId].futureFlow;
        }

        flow.startTimestamp = _startTime;
        flow.rewardsPerSecond = _rewardsPerSecondInFlowPrecision;

        emit FutureFlowSet(_poolId, _startTime, _rewardsPerSecondInFlowPrecision);
    }

    function _registerPool(bytes32 _poolId) internal virtual {
        if (!isPoolRegistered[_poolId]) {
            registeredPools.push(_poolId);
            isPoolRegistered[_poolId] = true;
            emit PoolRegistered(_poolId);
        }
    }

    function _accountForClaim(address _claimer) internal returns (uint256) {
        for (uint256 i = 0; i < registeredPools.length; i++) {
            _handleAccrual(_claimer, registeredPools[i]);
        }

        uint256 claimed = userClaims[_claimer];
        if (rewardToken.balanceOf(address(this)) < claimed) {
            revert InsufficientRewardTokenBalance();
        }
        totalClaimed += claimed;
        totalClaimableInFlowPrecision -= claimed * FLOW_PRECISION;
        userClaims[_claimer] = 0;

        return claimed;
    }

    function _claim(address _claimer) internal returns (uint256) {
        uint256 claimed = _accountForClaim(_claimer);
        if (claimed == 0) {
            revert NothingToClaim();
        }

        rewardToken.safeTransfer(_claimer, claimed);
        emit Claimed(_claimer, address(rewardToken), claimed);

        return claimed;
    }

    function _handleAccrual(address _user, bytes32 _poolId) internal virtual forwardPool(_poolId) {
        Shares storage poolShares = pools[_poolId].totalShares;
        Shares storage _userShares = pools[_poolId].userShares[_user];
        uint256 claimed = _userShares.shares * (poolShares.accruedRewardsPerShare - _userShares.accruedRewardsPerShare);
        _userShares.accruedRewardsPerShare = poolShares.accruedRewardsPerShare;

        claimed /= FLOW_PRECISION;
        userClaims[_user] += claimed;
    }

    function _shouldSwitchToFutureFlow(bytes32 _poolId) private view returns (bool) {
        return pools[_poolId].futureFlow.startTimestamp > 0 && block.timestamp >= pools[_poolId].futureFlow.startTimestamp;
    }

    function _getForwardedPoolShares(bytes32 _poolId) private view returns (Shares memory) {
        RewardPool storage pool = pools[_poolId];
        Shares memory poolShares = pool.totalShares;
        if (poolShares.shares > 0 && block.timestamp > pool.currentFlow.startTimestamp) {
            FlowConfig memory currentFlow = pool.currentFlow;
            uint256 lastUpdate = pool.lastUpdate;
            if (_shouldSwitchToFutureFlow(_poolId)) {
                uint256 timeFromUpdateToEpochEnd = pool.futureFlow.startTimestamp - lastUpdate;
                poolShares.accruedRewardsPerShare += currentFlow.rewardsPerSecond * timeFromUpdateToEpochEnd / poolShares.shares;
                lastUpdate = pool.futureFlow.startTimestamp;
                currentFlow = pool.futureFlow;
            }

            uint256 timeElapsed = block.timestamp - lastUpdate;
            poolShares.accruedRewardsPerShare += currentFlow.rewardsPerSecond * timeElapsed / poolShares.shares;
        }

        return poolShares;
    }

    function _forwardPool(bytes32 _poolId) private {
        RewardPool storage pool = pools[_poolId];
        if (pool.lastUpdate < block.timestamp) {
            Shares memory forwarded = _getForwardedPoolShares(_poolId);
            totalClaimableInFlowPrecision += forwarded.shares * (forwarded.accruedRewardsPerShare - pool.totalShares.accruedRewardsPerShare);
            pool.totalShares = forwarded;
            pool.lastUpdate = block.timestamp;
            if (_shouldSwitchToFutureFlow(_poolId)) {
                pool.pastFlows.push(pool.currentFlow);
                pool.currentFlow = pool.futureFlow;
                pool.futureFlow.startTimestamp = 0;
                pool.futureFlow.rewardsPerSecond = 0;
            }
        }
    }
}
