// SPDX-License-Identifier: Apache 2
pragma solidity ^0.8.0;

interface ISSynoRewardsDistributor {
    function handleSSynoStakeChange(address _user) external;
}
