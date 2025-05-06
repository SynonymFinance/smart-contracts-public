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
import {MoneyMarketRewardsDistributor} from "./MoneyMarketRewardsDistributor.sol";
import {ConditionalRewardsDistributor} from "./ConditionalRewardsDistributor.sol";

abstract contract ConditionalMoneyMarketRewardsDistributor is ConditionalRewardsDistributor, MoneyMarketRewardsDistributor {
    using SafeERC20 for IERC20;

    uint256[20] private __gap;

    //
    // SETTERS
    //

    function setUserShares(address _user, bytes32 _poolId, uint256 _newShares) internal virtual override(BaseStreamingRewardsDistributor, ConditionalRewardsDistributor) {
        ConditionalRewardsDistributor.setUserShares(_user, _poolId, _newShares);
    }

    function setFutureFlow(bytes32 _poolId, uint256 _startTime, uint256 _rewardsPerSecondInFlowPrecision) public virtual override(BaseStreamingRewardsDistributor, MoneyMarketRewardsDistributor) {
        MoneyMarketRewardsDistributor.setFutureFlow(_poolId, _startTime, _rewardsPerSecondInFlowPrecision);
    }

    //
    // INTERNALS
    //

    function _createUserShares(address _user) internal virtual override {
        for (uint256 i = 0; i < supportedMarkets.length; i++) {
            // it's enough to trigger the money market balance change handler
            handleBalanceChange(_user, supportedMarkets[i]);
        }
    }
}
