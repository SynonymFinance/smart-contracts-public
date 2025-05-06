// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.0;

import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts-upgradeable/proxy/utils/Initializable.sol";
import {OwnableUpgradeable} from "@openzeppelin/contracts-upgradeable/access/OwnableUpgradeable.sol";

import {IBonusSynoRewardsDistributor} from "../../interfaces/rewards/IBonusSynoRewardsDistributor.sol";
import {SynoBalancerPoolHelper, IBalancerPoolToken, IBalancerQueries, _asIAsset, WeightedPoolUserData} from "../SynoBalancerPoolHelper.sol";
import {vlSYNO} from "../vlSyno.sol";
import {BaseStreamingRewardsDistributor} from "./BaseStreamingRewardsDistributor.sol";

abstract contract BonusSynoRewardsDistributor is IBonusSynoRewardsDistributor, BaseStreamingRewardsDistributor {
    using SafeERC20 for IERC20;
    using SynoBalancerPoolHelper for IBalancerPoolToken;

    uint256 public override maxRewardMultiplier;
    vlSYNO private vlSynoInternal;
    uint256[50] private __gap;

    // this is not a standalone contract, so it only has an internal initializer
    function initialize_BonusSynoRewardsDistributor(address _vlSyno) internal onlyInitializing {
        vlSynoInternal = vlSYNO(_vlSyno);
        if (address(vlSynoInternal.getSyno()) != address(rewardToken)) {
            revert RewardTokenMustBeSyno();
        }

        maxRewardMultiplier = 3;
    }

    //
    // GETTERS
    //

    function isBonusEnabled() public view override returns (bool) {
        return maxRewardMultiplier > 0;
    }

    function getRequiredETHAmount(uint256 synoAmount) public view override returns(uint256) {
        return _getPoolToken()._calculateRequiredETHAmount(synoAmount);
    }

    /**
     * @dev Returns the amount of ETH that needs to be provided.
     * @param baseAmount base syno claim amount
     * @param lockPeriod for vlSYNO lock.
     */
    function getSynoAndRequiredETHAmount(uint256 baseAmount, vlSYNO.LockPeriod lockPeriod) public view returns(uint256, uint256) {
        uint256 bonus = _calculateSynoBonusAmount(lockPeriod, baseAmount);

        uint256 requiredETHAmount = getRequiredETHAmount(baseAmount + bonus);

        return (baseAmount + bonus, requiredETHAmount);
    }

    /**
     * @dev Returns the amount of ETH that needs to be provided.
     * @param _user the user to look up the amounts for
     * @param _lockPeriod for vlSYNO lock.
     */
    function getSynoAndRequiredETHAmount(address _user, vlSYNO.LockPeriod _lockPeriod) public view override returns(uint256, uint256) {
        return getSynoAndRequiredETHAmount(getClaimableRewards(_user), _lockPeriod);
    }

    function getClaimableRewards(address _user, vlSYNO.LockPeriod _lockPeriod) public virtual view returns (uint256 total) {
        uint256 base = getClaimableRewards(_user);
        return base + _calculateSynoBonusAmount(_lockPeriod, base);
    }

    //
    // INTERACTIONS
    //

    /**
     * @dev Claim rewards with bonus, need 20% ETH value of the claimed SYNO.
     * @param _lockPeriod vlSyno Lock period.
     */
    function claim(vlSYNO.LockPeriod _lockPeriod) external payable override  {
        _claim(msg.sender, _lockPeriod);
    }

    function delegatedClaim(address _claimer, vlSYNO.LockPeriod _lockPeriod) external override onlyClaimDelegator payable {
        _claim(_claimer, _lockPeriod);
    }

    //
    // INTERNALS
    //

    function _claim(address _claimer, vlSYNO.LockPeriod _lockPeriod) internal {
        uint256 ethAmount = msg.value;
        IBalancerPoolToken poolToken = _getPoolToken();

        uint256 baseClaim = _accountForClaim(_claimer);

        // Calculate required amount of ETH
        // NOTE: Can't use getSynoAndRequiredETHAmount(_claimer, _lockPeriod) here, because _accountForClaim changed the state!
        (uint256 synoAmount, uint256 requiredETHAmount) = getSynoAndRequiredETHAmount(baseClaim, _lockPeriod);

        // Scale down syno amount if eth amount was specified to low. If it is more than required just make it max bonus.
        if(ethAmount < requiredETHAmount) {
            synoAmount = synoAmount * ethAmount / requiredETHAmount;

            // If less than min bonus, just use the base amount
            if(synoAmount < baseClaim) {
                synoAmount = baseClaim;
            }
        }

        // Join Pool
        uint256 receivedBalancerLPTokens = poolToken._joinBalancerPool(synoAmount, ethAmount);

        // Stake LP Tokens in VLSyno Pool
        poolToken.approve(address(vlSynoInternal), receivedBalancerLPTokens);
        vlSynoInternal.stake(receivedBalancerLPTokens, _lockPeriod, _claimer);

        emit Claimed(_claimer, address(rewardToken), synoAmount);
    }

    function _calculateSynoBonusAmount(vlSYNO.LockPeriod lockPeriod, uint256 baseAmount) internal view returns(uint256) {
        if (lockPeriod == vlSYNO.LockPeriod.ONE_MONTH) {
            return 0;
        }

        if (lockPeriod == vlSYNO.LockPeriod.THREE_MONTHS) {
            return baseAmount;
        }

        if (lockPeriod == vlSYNO.LockPeriod.SIX_MONTHS) {
            return baseAmount * maxRewardMultiplier * 60 / 100;
        }

        if (lockPeriod == vlSYNO.LockPeriod.TWELVE_MONTHS) {
            return baseAmount * maxRewardMultiplier;
        }

        revert LockPeriodNotSupported();
    }

    function _calculateBaseAmount(uint256 amount) internal view returns(uint256) {
        return amount / (1 + maxRewardMultiplier);
    }

    function _getPoolToken() internal view returns (IBalancerPoolToken) {
        return IBalancerPoolToken(vlSynoInternal.poolToken());
    }
}
