// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.0;

import "@solmate/utils/MerkleProofLib.sol";
import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts-upgradeable/proxy/utils/Initializable.sol";
import {OwnableUpgradeable} from "@openzeppelin/contracts-upgradeable/access/OwnableUpgradeable.sol";
import {IMoneyMarketRewardsDistributor} from "../../interfaces/rewards/IMoneyMarketRewardsDistributor.sol";
import {IHub, HubSpokeStructs} from "../../interfaces/IHub.sol";
import {MoneyMarketRewardsDistributor, PoolSide} from "./MoneyMarketRewardsDistributor.sol";
import {BonusSynoRewardsDistributor, vlSYNO} from "./BonusSynoRewardsDistributor.sol";
import {BaseStreamingRewardsDistributor} from "./BaseStreamingRewardsDistributor.sol";

contract MoneyMarketSynoDistributor is BonusSynoRewardsDistributor, MoneyMarketRewardsDistributor {
    using SafeERC20 for IERC20;

    uint256[20] private __gap;

    function initialize(address _rewardToken, address _hub, address _vlSyno) public virtual initializer {
        MoneyMarketRewardsDistributor.initialize(_rewardToken, _hub);
        BonusSynoRewardsDistributor.initialize_BonusSynoRewardsDistributor(_vlSyno);
    }

    function setFutureFlow(bytes32 _poolId, uint256 _startTime, uint256 _rewardsPerSecondInFlowPrecision) public virtual override(BaseStreamingRewardsDistributor, MoneyMarketRewardsDistributor) {
        MoneyMarketRewardsDistributor.setFutureFlow(_poolId, _startTime, _rewardsPerSecondInFlowPrecision);
    }
}
