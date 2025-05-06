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
import {BaseSinglePoolRewardsDistributor} from "./BaseSinglePoolRewardsDistributor.sol";
import {BaseStreamingRewardsDistributor} from "./BaseStreamingRewardsDistributor.sol";
import {SSynoRewardsDistributor} from "./SSynoRewardsDistributor.sol";
import {BonusSynoRewardsDistributor, vlSYNO} from "./BonusSynoRewardsDistributor.sol";

contract SSynoSynoDistributor is BonusSynoRewardsDistributor, SSynoRewardsDistributor {
    using SafeERC20 for IERC20;

    function initialize(address _rewardToken, address _sSyno, address _vlSyno) public virtual initializer {
        SSynoRewardsDistributor.initialize(_rewardToken, sSYNO(_sSyno));
        BonusSynoRewardsDistributor.initialize_BonusSynoRewardsDistributor(_vlSyno);
    }

    function _registerPool(bytes32 _poolId) internal virtual override(BaseSinglePoolRewardsDistributor, BaseStreamingRewardsDistributor) {
        BaseSinglePoolRewardsDistributor._registerPool(_poolId);
    }
}
