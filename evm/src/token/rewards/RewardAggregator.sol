// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.0;

import "@solmate/utils/MerkleProofLib.sol";
import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts-upgradeable/proxy/utils/Initializable.sol";
import {OwnableUpgradeable} from "@openzeppelin/contracts-upgradeable/access/OwnableUpgradeable.sol";
import {PausableUpgradeable} from "@openzeppelin/contracts-upgradeable/utils/PausableUpgradeable.sol";

import {IPausable} from "../../interfaces/IPausable.sol";
import {IVlSynoRewardsDistributor} from "../../interfaces/rewards/IVlSynoRewardsDistributor.sol";
import {ISSynoRewardsDistributor} from "../../interfaces/rewards/ISSynoRewardsDistributor.sol";
import {IMoneyMarketRewardsDistributor} from "../../interfaces/rewards/IMoneyMarketRewardsDistributor.sol";
import {IStreamingRewardsDistributor} from "../../interfaces/rewards/IStreamingRewardsDistributor.sol";
import {IBonusSynoRewardsDistributor, IBonusSynoClaimer, vlSYNO} from "../../interfaces/rewards/IBonusSynoRewardsDistributor.sol";
import {IRewardAggregator} from "../../interfaces/rewards/IRewardAggregator.sol";
import {BaseStreamingRewardsDistributor} from "./BaseStreamingRewardsDistributor.sol";

contract RewardAggregator is IRewardAggregator, IVlSynoRewardsDistributor, ISSynoRewardsDistributor, IMoneyMarketRewardsDistributor, Initializable, OwnableUpgradeable, PausableUpgradeable {
    using SafeERC20 for IERC20;

    IMoneyMarketRewardsDistributor[] moneyMarketRewardDistributors;
    IVlSynoRewardsDistributor[] vlSynoRewardDistributors;
    ISSynoRewardsDistributor[] sSynoRewardDistributors;

    address[] rewardTokens;
    address syno;
    mapping(address => IStreamingRewardsDistributor[]) distributorsSupportingToken;
    mapping(address => bool) isBonusSynoRewardsDistributor;

    /// @custom:oz-upgrades-unsafe-allow constructor
    constructor() {
        _disableInitializers();
    }

    function initialize(address _syno) public virtual initializer {
        OwnableUpgradeable.__Ownable_init(msg.sender);
        syno = _syno;
    }

    //
    // GETTERS
    //

    function getAllRewardInfos(address _user) external view returns (RewardInfo[] memory infos) {
        infos = new RewardInfo[](rewardTokens.length);
        for (uint256 i = 0; i < rewardTokens.length; i++) {
            infos[i] = getRewardInfo(_user, rewardTokens[i]);
        }
    }

    function getRewardInfo(address _user, address _token) public view returns (RewardInfo memory info) {
        if (!isRewardTokenSupported(_token)) {
            revert UnsupportedToken();
        }

        info.token = _token;

        IStreamingRewardsDistributor[] storage dList = distributorsSupportingToken[_token];
        for (uint256 i = 0; i < dList.length; i++) {
            info.claimable += dList[i].getClaimableRewards(_user);
            info.rewardsPerSecond += dList[i].getTotalUserFlowRate(_user);
        }
    }

    function isRewardTokenSupported(address _token) public view returns (bool) {
        return distributorsSupportingToken[_token].length > 0;
    }

    function getSynoAndRequiredETHAmount(address _user, vlSYNO.LockPeriod _lockPeriod) external view override returns(uint256, uint256) {
        uint256 totalSyno = 0;
        uint256 totalEth = 0;
        IStreamingRewardsDistributor[] storage dList = distributorsSupportingToken[syno];
        for (uint256 i = 0; i < dList.length; i++) {
            if (isBonusSynoRewardsDistributor[address(dList[i])]) {
                IBonusSynoRewardsDistributor bonusDist = IBonusSynoRewardsDistributor(address(dList[i]));
                (uint256 addedSyno, uint256 addedEth) = bonusDist.getSynoAndRequiredETHAmount(_user, _lockPeriod);
                totalSyno += addedSyno;
                totalEth += addedEth;
            }
        }

        return (totalSyno, totalEth);
    }

    function getDistributorsSupportingToken(address _token) external view override returns (IStreamingRewardsDistributor[] memory) {
        return distributorsSupportingToken[_token];
    }

    function getRewardTokens() external view returns (address[] memory) {
        return rewardTokens;
    }

    function getSSynoRewardDistributors() external view returns (ISSynoRewardsDistributor[] memory) {
        return sSynoRewardDistributors;
    }

    function getVlSynoRewardDistributors() external view returns (IVlSynoRewardsDistributor[] memory) {
        return vlSynoRewardDistributors;
    }

    function getMoneyMarketRewarddistributors() external view returns (IMoneyMarketRewardsDistributor[] memory) {
        return moneyMarketRewardDistributors;
    }

    //
    // SETTERS
    //

    function addMoneyMarketRewardsDistributor(IMoneyMarketRewardsDistributor _dist) external onlyOwner {
        for (uint256 i = 0; i < moneyMarketRewardDistributors.length; i++) {
            if (address(moneyMarketRewardDistributors[i]) == address(_dist)) {
                revert DistributorExists();
            }
        }

        _handleDistributorAdd(IStreamingRewardsDistributor(address(_dist)));
        moneyMarketRewardDistributors.push(_dist);
        emit MoneyMarketRewardsDistributorAdded(address(_dist), isBonusSynoRewardsDistributor[address(_dist)]);
    }

    function removeMoneyMarketRewardsDistributor(IMoneyMarketRewardsDistributor _dist) external onlyOwner {
        for (uint256 i = 0; i < moneyMarketRewardDistributors.length; i++) {
            if (address(moneyMarketRewardDistributors[i]) == address(_dist)) {
                _handleDistributorRemove(IStreamingRewardsDistributor(address(_dist)));
                moneyMarketRewardDistributors[i] = moneyMarketRewardDistributors[moneyMarketRewardDistributors.length - 1];
                moneyMarketRewardDistributors.pop();
                emit MoneyMarketRewardsDistributorRemoved(address(_dist));
                return;
            }
        }

        revert DistributorNotFound();
    }

    function addVlSynoRewardsDistributor(IVlSynoRewardsDistributor _dist) external onlyOwner {
        for (uint256 i = 0; i < vlSynoRewardDistributors.length; i++) {
            if (address(vlSynoRewardDistributors[i]) == address(_dist)) {
                revert DistributorExists();
            }
        }

        _handleDistributorAdd(IStreamingRewardsDistributor(address(_dist)));
        vlSynoRewardDistributors.push(_dist);
        emit VlSynoMarketRewardsDistributorAdded(address(_dist), isBonusSynoRewardsDistributor[address(_dist)]);
    }

    function removeVlSynoRewardsDistributor(IVlSynoRewardsDistributor _dist) external onlyOwner {
        for (uint256 i = 0; i < vlSynoRewardDistributors.length; i++) {
            if (address(vlSynoRewardDistributors[i]) == address(_dist)) {
                _handleDistributorRemove(IStreamingRewardsDistributor(address(_dist)));
                vlSynoRewardDistributors[i] = vlSynoRewardDistributors[vlSynoRewardDistributors.length - 1];
                vlSynoRewardDistributors.pop();
                emit VlSynoMarketRewardsDistributorRemoved(address(_dist));
                return;
            }
        }

        revert DistributorNotFound();
    }

    function addSSynoRewardsDistributor(ISSynoRewardsDistributor _dist) external onlyOwner {
        for (uint256 i = 0; i < sSynoRewardDistributors.length; i++) {
            if (address(sSynoRewardDistributors[i]) == address(_dist)) {
                revert DistributorExists();
            }
        }

        _handleDistributorAdd(IStreamingRewardsDistributor(address(_dist)));
        sSynoRewardDistributors.push(_dist);
        emit SSynoMarketRewardsDistributorAdded(address(_dist), isBonusSynoRewardsDistributor[address(_dist)]);
    }

    function removeSSynoRewardsDistributor(ISSynoRewardsDistributor _dist) external onlyOwner {
        for (uint256 i = 0; i < sSynoRewardDistributors.length; i++) {
            if (address(sSynoRewardDistributors[i]) == address(_dist)) {
                _handleDistributorRemove(IStreamingRewardsDistributor(address(_dist)));
                sSynoRewardDistributors[i] = sSynoRewardDistributors[sSynoRewardDistributors.length - 1];
                sSynoRewardDistributors.pop();
                emit SSynoMarketRewardsDistributorRemoved(address(_dist));
                return;
            }
        }

        revert DistributorNotFound();
    }

    //
    // INTERACTIONS
    //

    function claimAll() external override {
        for (uint256 i = 0; i < rewardTokens.length; i++) {
            claim(rewardTokens[i]);
        }
    }

    function claimAll(vlSYNO.LockPeriod _lockPeriod) external payable override {
        for (uint256 i = 0; i < rewardTokens.length; i++) {
            if (rewardTokens[i] == syno) {
                claimSyno(_lockPeriod);
            } else {
                claim(rewardTokens[i]);
            }
        }
    }

    function claim(address _token) public override {
        IStreamingRewardsDistributor[] storage dList = distributorsSupportingToken[_token];
        for (uint256 i = 0; i < dList.length; i++) {
            if (dList[i].getClaimableRewards(msg.sender) > 0) {
                dList[i].delegatedClaim(msg.sender);
            }
        }
    }

    function claimSyno(vlSYNO.LockPeriod _lockPeriod) public payable override {
        IStreamingRewardsDistributor[] storage dList = distributorsSupportingToken[syno];
        uint256 valueLeft = msg.value;
        for (uint256 i = 0; i < dList.length; i++) {
            if (dList[i].getClaimableRewards(msg.sender) == 0) {
                continue;
            }

            if (isBonusSynoRewardsDistributor[address(dList[i])]) {
                IBonusSynoRewardsDistributor bonusDist = IBonusSynoRewardsDistributor(address(dList[i]));
                (, uint256 requiredEth) = bonusDist.getSynoAndRequiredETHAmount(msg.sender, _lockPeriod);
                if (requiredEth > valueLeft) {
                    requiredEth = valueLeft;
                }
                IBonusSynoRewardsDistributor(address(dList[i])).delegatedClaim{value: requiredEth}(msg.sender, _lockPeriod);
                valueLeft -= requiredEth;
            } else {
                dList[i].delegatedClaim(msg.sender);
            }
        }

        // return any leftovers
        if (valueLeft > 0) {
            (bool success,) = msg.sender.call{value: valueLeft}("");
            if (!success) {
                revert TransferFailed();
            }
        }
    }

    function handleVlSynoStakeChange(address _user) public override {
        for (uint256 i = 0; i < vlSynoRewardDistributors.length; i++) {
            if (!_isPaused(address(vlSynoRewardDistributors[i]))) {
                vlSynoRewardDistributors[i].handleVlSynoStakeChange(_user);
            }
        }
    }

    function handleVlSynoStakeExpired(address _user, uint256 _index) external override {
        handleVlSynoStakeExpired(_user, _index, msg.sender);
    }

    function handleVlSynoStakeExpired(address _user, uint256 _index, address _claimer) public override {
        for (uint256 i = 0; i < vlSynoRewardDistributors.length; i++) {
            if (!_isPaused(address(vlSynoRewardDistributors[i]))) {
                vlSynoRewardDistributors[i].handleVlSynoStakeExpired(_user, _index, _claimer);
            }
        }
    }

    function handleSSynoStakeChange(address _user) external override {
        for (uint256 i = 0; i < sSynoRewardDistributors.length; i++) {
            if (!_isPaused(address(sSynoRewardDistributors[i]))) {
                sSynoRewardDistributors[i].handleSSynoStakeChange(_user);
            }
        }
    }

    function handleBalanceChange(address _user, bytes32 _asset) external override {
        for (uint256 i = 0; i < moneyMarketRewardDistributors.length; i++) {
            if (!_isPaused(address(moneyMarketRewardDistributors[i]))) {
                moneyMarketRewardDistributors[i].handleBalanceChange(_user, _asset);
            }
        }
    }

    function migrateShares(address _user, bytes32 _asset) external override {
        for (uint256 i = 0; i < moneyMarketRewardDistributors.length; i++) {
            if (!_isPaused(address(moneyMarketRewardDistributors[i]))) {
                moneyMarketRewardDistributors[i].migrateShares(_user, _asset);
            }
        }
    }

    //
    // INTERNALS
    //

    function _handleDistributorAdd(IStreamingRewardsDistributor _dist) internal {
        if (!_dist.isAuthorizedClaimDelegator(address(this))) {
            revert AggregatorNotAnAuthorizedDelegator();
        }
        address rewardToken = address(_dist.rewardToken());
        if (distributorsSupportingToken[rewardToken].length == 0) {
            // token previously unsupported
            rewardTokens.push(rewardToken);
        }
        distributorsSupportingToken[rewardToken].push(_dist);
        if (_isBonusSynoRewardsDistributor(address(_dist))) {
            isBonusSynoRewardsDistributor[address(_dist)] = true;
        }
    }

    function _handleDistributorRemove(IStreamingRewardsDistributor _dist) internal {
        address rewardToken = address(_dist.rewardToken());
        if (distributorsSupportingToken[rewardToken].length == 1) {
            // token loses support
            for (uint256 i = 0; i < rewardTokens.length; i++) {
                if (rewardTokens[i] == rewardToken) {
                    rewardTokens[i] = rewardTokens[rewardTokens.length - 1];
                    rewardTokens.pop();
                    break;
                }
            }
        }
        // remove the distributor
        IStreamingRewardsDistributor[] storage dList = distributorsSupportingToken[rewardToken];
        for (uint256 i = 0; i < dList.length; i++) {
            if (dList[i] == _dist) {
                dList[i] = dList[dList.length - 1];
                dList.pop();
                isBonusSynoRewardsDistributor[address(_dist)] = false; // clear bonus lookup
                return;
            }
        }
    }

    function _isBonusSynoRewardsDistributor(address _distributor) internal returns (bool success) {
        (success,) = _distributor.call(abi.encodeWithSelector(IBonusSynoRewardsDistributor.maxRewardMultiplier.selector));
    }

    function _isPaused(address _distributor) internal view returns (bool) {
        return IPausable(_distributor).paused();
    }
}
