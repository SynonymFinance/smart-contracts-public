// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.0;

import "@solmate/utils/MerkleProofLib.sol";
import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts-upgradeable/proxy/utils/Initializable.sol";
import {OwnableUpgradeable} from "@openzeppelin/contracts-upgradeable/access/OwnableUpgradeable.sol";
import {ISSynoRewardsDistributor} from "../../interfaces/rewards/ISSynoRewardsDistributor.sol";
import {IHub} from "../../interfaces/IHub.sol";
import {sSYNO} from "../sSYNO.sol";
import {BaseStreamingRewardsDistributor} from "./BaseStreamingRewardsDistributor.sol";

abstract contract ConditionalRewardsDistributor is BaseStreamingRewardsDistributor {
    using SafeERC20 for IERC20;

    mapping(address => bool) public isEligible;
    uint256[20] private __gap;

    //
    // GETTERS
    //

    function isEligibleForRewards(address _user) public virtual view returns (bool);

    //
    // SETTERS
    //

    function setUserShares(address _user, bytes32 _poolId, uint256 _newShares) internal virtual override {
        bool currentlyEligibile = isEligibleForRewards(_user);
        if (currentlyEligibile != isEligible[_user]) {
            isEligible[_user] = currentlyEligibile;
            if (currentlyEligibile) {
                _createUserShares(_user);
            } else {
                _clearUserShares(_user);
            }
        } else if (currentlyEligibile || _newShares == 0) {
            BaseStreamingRewardsDistributor.setUserShares(_user, _poolId, _newShares);
        }
    }

    //
    // INTERNALS
    //

    function _createUserShares(address _user) internal virtual;

    function _clearUserShares(address _user) internal virtual {
        for (uint256 i = 0; i < registeredPools.length; i++) {
            bytes32 poolId = registeredPools[i];
            RewardPool storage pool = pools[poolId];
            if (pool.userShares[_user].shares > 0) {
                // clear the users share
                // using BaseStreamingRewardsDistributor to avoid computing eligibility again
                BaseStreamingRewardsDistributor.setUserShares(_user, poolId, 0);
            }
        }
    }
}
