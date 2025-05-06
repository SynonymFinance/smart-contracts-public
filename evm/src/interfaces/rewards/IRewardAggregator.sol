// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.0;

import {vlSYNO} from "../../token/vlSyno.sol";
import {IStreamingRewardsDistributor} from "./IStreamingRewardsDistributor.sol";
import {ISSynoRewardsDistributor} from "./ISSynoRewardsDistributor.sol";
import {IVlSynoRewardsDistributor} from "./IVlSynoRewardsDistributor.sol";
import {IMoneyMarketRewardsDistributor} from "./IMoneyMarketRewardsDistributor.sol";
import {IBonusSynoClaimer} from "./IBonusSynoRewardsDistributor.sol";

interface IRewardAggregator is IBonusSynoClaimer {
    struct RewardInfo {
        address token;
        uint256 claimable;
        uint256 rewardsPerSecond;
    }

    event MoneyMarketRewardsDistributorAdded(address distributor, bool isSynoBonusDistributor);
    event MoneyMarketRewardsDistributorRemoved(address distributor);
    event VlSynoMarketRewardsDistributorAdded(address distributor, bool isSynoBonusDistributor);
    event VlSynoMarketRewardsDistributorRemoved(address distributor);
    event SSynoMarketRewardsDistributorAdded(address distributor, bool isSynoBonusDistributor);
    event SSynoMarketRewardsDistributorRemoved(address distributor);

    error AggregatorNotAnAuthorizedDelegator();
    error DistributorNotFound();
    error DistributorExists();
    error TransferFailed();
    error UnsupportedToken();

    function getAllRewardInfos(address _user) external view returns (RewardInfo[] memory);
    function getRewardInfo(address _user, address _token) external view returns (RewardInfo memory);
    function getDistributorsSupportingToken(address _token) external view returns (IStreamingRewardsDistributor[] memory);
    function getRewardTokens() external view returns (address[] memory);
    function getSSynoRewardDistributors() external view returns (ISSynoRewardsDistributor[] memory);
    function getVlSynoRewardDistributors() external view returns (IVlSynoRewardsDistributor[] memory);
    function getMoneyMarketRewarddistributors() external view returns (IMoneyMarketRewardsDistributor[] memory);

    function claimAll() external;
    function claimAll(vlSYNO.LockPeriod _lockPeriod) external payable;
    function claim(address _token) external;
    function claimSyno(vlSYNO.LockPeriod _lockPeriod) external payable;
}
