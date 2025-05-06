// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.0;

import "@solmate/utils/MerkleProofLib.sol";
import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts-upgradeable/proxy/utils/Initializable.sol";
import {OwnableUpgradeable} from "@openzeppelin/contracts-upgradeable/access/OwnableUpgradeable.sol";
import {IMoneyMarketRewardsDistributor} from "../../interfaces/rewards/IMoneyMarketRewardsDistributor.sol";
import {IHub, HubSpokeStructs, IAssetRegistry, IWormholeTunnel} from "../../interfaces/IHub.sol";
import {BaseStreamingRewardsDistributor} from "./BaseStreamingRewardsDistributor.sol";

import "@wormhole/Utils.sol";

enum PoolSide {
    DEPOSIT,
    BORROW
}

contract MoneyMarketRewardsDistributor is IMoneyMarketRewardsDistributor, BaseStreamingRewardsDistributor {
    using SafeERC20 for IERC20;

    error MarketNotSupported();
    error OnlyHub();

    uint256 public constant DEPOSIT_POOL_ID_PREFIX = 0;
    uint256 public constant BORROW_POOL_ID_PREFIX = 2**252;

    IHub hub;
    address[] _deprecated_supportedMarkets;
    mapping(address => bool) _deprecated_isMarketSupported;

    bytes32[] supportedMarkets;
    mapping(bytes32 => bool) isMarketSupported;
    mapping(bytes32 => bytes32) poolIdToAssetId;
    mapping(bytes32 => bool) poolMigrated;

    uint256[16] private __gap;

    modifier onlyHub() {
        if (msg.sender != address(hub)) {
            revert OnlyHub();
        }
        _;
    }


    function initialize(address _rewardToken, address _hub) public virtual initializer {
        BaseStreamingRewardsDistributor.initialize(_rewardToken);
        hub = IHub(_hub);
    }

    //
    // GETTERS
    //

    function getPoolId(bytes32 _assetId, PoolSide _side) public pure returns (bytes32) {
        uint256 prefix = _side == PoolSide.DEPOSIT ? DEPOSIT_POOL_ID_PREFIX : BORROW_POOL_ID_PREFIX;
        return bytes32(prefix | uint256(_assetId << 8 >> 8)); // zero the most significant byte of token
    }

    function getPoolAssetAndSideFromPoolId(bytes32 _poolId) public view returns (bytes32 asset, PoolSide side) {
        side = uint256(_poolId) & BORROW_POOL_ID_PREFIX == BORROW_POOL_ID_PREFIX ? PoolSide.BORROW : PoolSide.DEPOSIT;
        asset = poolIdToAssetId[_poolId];
    }

    function getCurrentFlow(bytes32 _assetId, PoolSide _side) public view returns (FlowConfig memory) {
        return getCurrentFlow(getPoolId(_assetId, _side));
    }

    function getFlowRate(bytes32 _assetId, PoolSide _side) public view returns (uint256) {
        return getFlowRate(getPoolId(_assetId, _side));
    }

    function getMarketFlowRate(bytes32 _assetId) public view returns (uint256) {
        return getFlowRate(_assetId, PoolSide.DEPOSIT) + getFlowRate(_assetId, PoolSide.BORROW);
    }

    function getUserFlowRate(address _user, bytes32 _assetId, PoolSide _side) public view returns (uint256) {
        return getUserFlowRate(_user, getPoolId(_assetId, _side));
    }

    function getUserMarketFlowRate(address _user, bytes32 _assetId) public view returns (uint256) {
        return getUserFlowRate(_user, _assetId, PoolSide.DEPOSIT) + getUserFlowRate(_user, _assetId, PoolSide.BORROW);
    }

    function setFutureFlow(bytes32 _poolId, uint256 _startTime, uint256 _rewardsPerSecondInFlowPrecision) public virtual override {
        (bytes32 asset,) = getPoolAssetAndSideFromPoolId(_poolId);
        if (asset == bytes32(0)) {
            revert MarketNotSupported();
        }
        super.setFutureFlow(_poolId, _startTime, _rewardsPerSecondInFlowPrecision);
    }

    //
    // SETTERS
    //

    function setFuturePoolRewards(
        uint256 _startTime,
        uint256 _duration,
        bytes32[] calldata _assets,
        uint256[] calldata _depositTotalRewards,
        uint256[] calldata _borrowTotalRewards
    ) external onlyOwner {
        if (_assets.length != _depositTotalRewards.length || _assets.length != _borrowTotalRewards.length) {
            revert ArrayLengthMismatch();
        }

        bytes32[] memory poolIds = new bytes32[](_assets.length * 2);
        uint256[] memory amounts = new uint256[](_assets.length * 2);
        for (uint256 i = 0; i < _assets.length; i++) {
            bytes32 asset = _assets[i];
            _registerMarket(asset);
            poolIds[2 * i] = getPoolId(asset, PoolSide.DEPOSIT);
            amounts[2 * i] = _depositTotalRewards[i];
            poolIds[2 * i + 1] = getPoolId(asset, PoolSide.BORROW);
            amounts[2 * i + 1] = _borrowTotalRewards[i];
        }

        setFutureFlows(_startTime, _duration, poolIds, amounts);
    }

    //
    // INTERACTIONS
    //

    function handleBalanceChange(address _user, bytes32 _asset) public override {
        HubSpokeStructs.DenormalizedVaultAmount memory userAmounts = hub.getVaultAmounts(_user, _asset);
        setUserShares(
            _user,
            getPoolId(_asset, PoolSide.DEPOSIT),
            userAmounts.deposited
        );
        setUserShares(
            _user,
            getPoolId(_asset, PoolSide.BORROW),
            userAmounts.borrowed
        );
    }

    function seed(address[] calldata _users) external {
        for (uint256 i = 0; i < _users.length; i++) {
            for (uint256 j = 0; j < supportedMarkets.length; j++) {
                handleBalanceChange(_users[i], supportedMarkets[j]);
            }
        }
    }

    function addMarketSupport(bytes32 _asset) external onlyOwner {
        _registerMarket(_asset);
    }

    function migrateShares(address _user, bytes32 _assetId) external onlyHub {
        IAssetRegistry ar = hub.getAssetRegistry();
        IWormholeTunnel wh = hub.getWormholeTunnel();
        uint16 hubChainId = wh.chainId();
        bytes32 usdcId = ar.getAssetId("USDC");
        uint16[] memory chains = ar.getSupportedChains();
        for (uint256 cIdx = 0; cIdx < chains.length; cIdx++) {
            address whWrappedAddress = wh.getTokenAddressOnThisChain(chains[cIdx], ar.getAssetAddress(_assetId, chains[cIdx]));
            if (whWrappedAddress == address(0)) {
                // asset not supported on this spoke
                continue;
            }
            if (_assetId == usdcId && chains[cIdx] != hubChainId && whWrappedAddress == address(wh.USDC())) {
                // WH tunnel maps all CCTP USDC to a single ARB address, so we have to exclude the duplicates
                // ARB USDC is accounted for as Hub chain USDC
                continue;
            }
            bytes32 oldDepositPool = getPoolId(toWormholeFormat(whWrappedAddress), PoolSide.DEPOSIT);
            bytes32 oldBorrowPool = getPoolId(toWormholeFormat(whWrappedAddress), PoolSide.BORROW);
            bytes32 newDepositPool = getPoolId(_assetId, PoolSide.DEPOSIT);
            bytes32 newBorrowPool = getPoolId(_assetId, PoolSide.BORROW);

            _registerMarket(_assetId);
            _migratePool(oldDepositPool, newDepositPool);
            _migratePool(oldBorrowPool, newBorrowPool);

            if (getUserShares(_user, oldDepositPool).shares > 0) {
                _migrateUserShares(oldDepositPool, newDepositPool, _user);
            }
            if (getUserShares(_user, oldBorrowPool).shares > 0) {
                _migrateUserShares(oldBorrowPool, newBorrowPool, _user);
            }
        }
        emit UserSharesMigrated(_user, _assetId);
    }

    //
    // INTERNALS
    //

    function _migratePool(bytes32 _oldId, bytes32 _newId) internal {
        if (!poolMigrated[_oldId]) {
            _setFutureFlow(_newId, block.timestamp + 1, getCurrentFlow(_newId).rewardsPerSecond + getCurrentFlow(_oldId).rewardsPerSecond);
            pools[_newId].totalShares.shares += pools[_oldId].totalShares.shares;
            poolMigrated[_oldId] = true;
        }
    }

    function _migrateUserShares(bytes32 _oldId, bytes32 _newId, address _user) internal {
        pools[_newId].userShares[_user].shares += pools[_oldId].userShares[_user].shares;
        pools[_oldId].userShares[_user].shares = 0;
        emit UserSharesChanged(_oldId, _user, 0, pools[_oldId].totalShares.shares);
        emit UserSharesChanged(_newId, _user, pools[_newId].userShares[_user].shares, pools[_newId].totalShares.shares);
    }

    function _registerMarket(bytes32 _asset) internal {
        if (!isMarketSupported[_asset]) {
            supportedMarkets.push(_asset);
            isMarketSupported[_asset] = true;
            poolIdToAssetId[getPoolId(_asset, PoolSide.BORROW)] = _asset;
            poolIdToAssetId[getPoolId(_asset, PoolSide.DEPOSIT)] = _asset;
            emit MarketSupportAdded(_asset);
        }
    }

    function removeMarket(bytes32 _asset) external onlyOwner {
        for (uint256 i = 0; i < supportedMarkets.length; i++) {
            if (supportedMarkets[i] == _asset) {
                supportedMarkets[i] = supportedMarkets[supportedMarkets.length - 1];
                supportedMarkets.pop();
                break;
            }
        }
        isMarketSupported[_asset] = false;
        emit MarketSupportRemoved(_asset);
    }
}
