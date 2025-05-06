// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.0;

import {ISSynoRewardsDistributor} from "../../interfaces/rewards/ISSynoRewardsDistributor.sol";

contract MockSSynoRewardsDistributor is ISSynoRewardsDistributor {
    event StakeChangeCalled(address user);

    function handleSSynoStakeChange(address _user) external override {
        emit StakeChangeCalled(_user);
    }
}