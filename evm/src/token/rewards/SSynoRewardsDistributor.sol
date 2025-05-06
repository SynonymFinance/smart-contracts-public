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

contract SSynoRewardsDistributor is ISSynoRewardsDistributor, BaseSinglePoolRewardsDistributor {
    using SafeERC20 for IERC20;

    sSYNO sSyno;

    /// @custom:oz-upgrades-unsafe-allow constructor
    constructor() BaseSinglePoolRewardsDistributor(keccak256("sSYNO")) {}

    function initialize(address _rewardToken, sSYNO _sSyno) public virtual initializer {
        BaseStreamingRewardsDistributor.initialize(_rewardToken);
        sSyno = _sSyno;
    }

    //
    // INTERACTIONS
    //

    function handleSSynoStakeChange(address _user) external override {
        setUserShares(
            _user,
            POOL_ID,
            sSyno.balanceOf(_user)
        );
    }
}
