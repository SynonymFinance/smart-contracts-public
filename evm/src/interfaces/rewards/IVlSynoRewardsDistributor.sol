// SPDX-License-Identifier: Apache 2
pragma solidity ^0.8.0;

interface IVlSynoRewardsDistributor {
    function handleVlSynoStakeChange(address _user) external;
    function handleVlSynoStakeExpired(address _user, uint256 _stakeId) external;
    function handleVlSynoStakeExpired(address _user, uint256 _stakeId, address _claimer) external;
}
