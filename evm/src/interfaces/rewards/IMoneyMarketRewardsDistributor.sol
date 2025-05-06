// SPDX-License-Identifier: Apache 2

pragma solidity ^0.8.0;

import {IHub} from "../IHub.sol";

interface IMoneyMarketRewardsDistributor {
    event MarketSupportAdded(bytes32 indexed token);
    event MarketSupportRemoved(bytes32 indexed token);
    event UserSharesMigrated(address indexed user, bytes32 indexed pool);

    function handleBalanceChange(address _user, bytes32 _assetId) external;
    function migrateShares(address _user, bytes32 _assetId) external;
}
