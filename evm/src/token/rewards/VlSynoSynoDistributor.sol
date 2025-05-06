// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.0;

import "@solmate/utils/MerkleProofLib.sol";
import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts-upgradeable/proxy/utils/Initializable.sol";
import {OwnableUpgradeable} from "@openzeppelin/contracts-upgradeable/access/OwnableUpgradeable.sol";
import {IVlSynoRewardsDistributor} from "../../interfaces/rewards/IVlSynoRewardsDistributor.sol";
import {IHub} from "../../interfaces/IHub.sol";
import {vlSYNO} from "../vlSyno.sol";
import {BaseSinglePoolRewardsDistributor, BaseStreamingRewardsDistributor} from "./BaseSinglePoolRewardsDistributor.sol";
import {VlSynoRewardsDistributor} from "./VlSynoRewardsDistributor.sol";
import {BonusSynoRewardsDistributor} from "./BonusSynoRewardsDistributor.sol";

contract VlSynoSynoDistributor is BonusSynoRewardsDistributor, VlSynoRewardsDistributor {
    using SafeERC20 for IERC20;

    function initialize(address _rewardToken, address _vlSyno) public virtual override initializer {
        VlSynoRewardsDistributor.initialize(_rewardToken, _vlSyno);
        BonusSynoRewardsDistributor.initialize_BonusSynoRewardsDistributor(_vlSyno);
    }

    function _registerPool(bytes32 _poolId) internal virtual override(BaseSinglePoolRewardsDistributor, BaseStreamingRewardsDistributor) {
        BaseSinglePoolRewardsDistributor._registerPool(_poolId);
    }
}
