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

abstract contract BaseSinglePoolRewardsDistributor is BaseStreamingRewardsDistributor {
    using SafeERC20 for IERC20;

    error SinglePoolAllowed();

    bytes32 public immutable POOL_ID;

    /// @custom:oz-upgrades-unsafe-allow constructor
    constructor(bytes32 _poolId) {
        POOL_ID = _poolId;
    }

    //
    // GETTERS
    //

    function getCurrentFlow() public view returns (FlowConfig memory) {
        return getCurrentFlow(POOL_ID);
    }

    //
    // SETTERS
    //

    function setFuturePoolRewards(
        uint256 _startTime,
        uint256 _duration,
        uint256 _amount
    ) external onlyOwner {
        setFutureFlow(POOL_ID, _startTime, _duration, _amount);
    }

    //
    // INTERNALS
    //

    function _registerPool(bytes32 _poolId) internal virtual override {
        if (_poolId != POOL_ID) {
            revert SinglePoolAllowed();
        }

        super._registerPool(_poolId);
    }
}
