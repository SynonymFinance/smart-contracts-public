// SPDX-License-Identifier: Apache 2

pragma solidity ^0.8.0;

import {vlSYNO} from "../../token/vlSyno.sol";

interface IBonusSynoClaimer {
    function getSynoAndRequiredETHAmount(address _user, vlSYNO.LockPeriod _lockPeriod) external view returns(uint256, uint256);
}

interface IBonusSynoRewardsDistributor is IBonusSynoClaimer {
    error LockPeriodNotSupported();
    error RewardTokenMustBeSyno();

    function maxRewardMultiplier() external view returns (uint256);
    function isBonusEnabled() external view returns (bool);
    function getRequiredETHAmount(uint256 synoAmount) external view returns(uint256);

    function claim(vlSYNO.LockPeriod _lockPeriod) external payable;
    function delegatedClaim(address _claimer, vlSYNO.LockPeriod _lockPeriod) external payable;
}
