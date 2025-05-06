// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.0;

import "@solmate/utils/MerkleProofLib.sol";
import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts-upgradeable/proxy/utils/Initializable.sol";
import {OwnableUpgradeable} from "@openzeppelin/contracts-upgradeable/access/OwnableUpgradeable.sol";
import {IVlSynoRewardsDistributor} from "../../interfaces/rewards/IVlSynoRewardsDistributor.sol";
import {IHub} from "../../interfaces/IHub.sol";
import {vlSYNO} from "../vlSyno.sol";
import {BaseSinglePoolRewardsDistributor, BaseStreamingRewardsDistributor} from "./BaseSinglePoolRewardsDistributor.sol";

contract VlSynoRewardsDistributor is IVlSynoRewardsDistributor, BaseSinglePoolRewardsDistributor {
    using SafeERC20 for IERC20;

    vlSYNO vlSyno;

    /// @custom:oz-upgrades-unsafe-allow constructor
    constructor() BaseSinglePoolRewardsDistributor(keccak256("vlSYNO")) {}

    function initialize(address _rewardToken, address _vlSyno) public virtual initializer {
        BaseStreamingRewardsDistributor.initialize(_rewardToken);
        vlSyno = vlSYNO(_vlSyno);
    }

    //
    // INTERACTIONS
    //

    function handleVlSynoStakeChange(address _user) public override {
        setUserShares(
            _user,
            POOL_ID,
            vlSyno.vlPower(_user)
        );
    }

    function handleVlSynoStakeExpired(address _user, uint256 _index) external override {
        handleVlSynoStakeExpired(_user, _index, msg.sender);
    }

    /**
     * @dev since there is no on-chain interaction when the vlSYNO stake expires we don't know
     *      when the users vlPower changes from its full amount to zero. until we reduce their
     *      shares, the user will accrue unearned rewards. this function introduces a liquidation-like
     *      mechanic where anybody can point to an expired vlSYNO stake to earn any rewards from
     *      the stake's expiration time up to the current time and return the shares to their true value.
     *
     *      there should be a bot to do that. the incentive is to wait just long enough for the reward
     *      to cover the gas cost plus some profit, but it's winner take all, so if you wait too long
     *      some other liquidator could sweep it, so the expired stakes shouldn't linger too long.
     */
    function handleVlSynoStakeExpired(address _user, uint256 _index, address _claimer) public override {
        uint256 oldTotalShares = pools[POOL_ID].totalShares.shares;
        uint256 stakeShares = vlSyno.getVlPowerOfStake(_user, _index);

        // this will revert if the Stake is not expired or already handled
        // this also calls handleVlSynoStakeChange and updates the shares
        vlSyno.handleExpiredStake(_user, _index);

        // handle penalty
        uint256 timeSinceStakeEnd = block.timestamp - vlSyno.getStakeExpirationTimestamp(_user, _index);
        uint256 penalty = getCurrentFlow().rewardsPerSecond * timeSinceStakeEnd * stakeShares / (oldTotalShares * FLOW_PRECISION);

        if (userClaims[_user] < penalty) {
            // this can only happen if an epoch changed during the vlSynoStakeChange
            // and the new epoch flow is less than the previous epoch flow
            // moreover the previous penalized user claim would have to be insufficient to cover the difference
            penalty = userClaims[_user];
        }

        userClaims[_user] -= penalty;
        userClaims[_claimer] += penalty;
    }

    function seed(address[] calldata _users) external {
        for (uint256 i = 0; i < _users.length; i++) {
            handleVlSynoStakeChange(_users[i]);
        }
    }
}
