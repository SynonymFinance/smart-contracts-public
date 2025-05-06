// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.0;


import {IHub, HubSpokeStructs} from "../../interfaces/IHub.sol";
import {ConditionalMoneyMarketRewardsDistributor, MoneyMarketRewardsDistributor} from "./ConditionalMoneyMarketRewardsDistributor.sol";

contract JitoSolRewardsDistributor is ConditionalMoneyMarketRewardsDistributor {
    bytes32 jitoSolAssetId;
    uint256[20] __gap;

    function initialize(address _rewardToken, address _hub, bytes32 _jitoSolAssetId) public virtual initializer {
        MoneyMarketRewardsDistributor.initialize(_rewardToken, _hub);
        jitoSolAssetId = _jitoSolAssetId;
    }

    //
    // GETTERS
    //

    function isEligibleForRewards(address _user) public virtual view override returns (bool) {
        return hub.getVaultAmounts(_user, jitoSolAssetId).borrowed > 0;
    }
}
