// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.0;

import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import {IFlashLoanReceiver, IPool, IPoolAddressesProvider} from "@aave/core-v3/contracts/flashloan/interfaces/IFlashLoanReceiver.sol";
import {ISwapRouter} from "@uniswap/v3-periphery/contracts/interfaces/ISwapRouter.sol";
import {SwapAmountsOracle} from "../../src/libraries/SwapAmountsOracle.sol";
import {IHub, ILiquidationCalculator, Liquidator, IAssetRegistry, IWormholeTunnel} from "./Liquidator.sol";
import {ISynonymPriceOracle} from "../interfaces/ISynonymPriceOracle.sol";
import { IERC20decimals } from "../interfaces/IERC20decimals.sol";
import "@wormhole/Utils.sol";


contract LiquidatorFlashLoan is IFlashLoanReceiver, Liquidator {
    using SafeERC20 for IERC20;
    using SwapAmountsOracle for ISynonymPriceOracle;

    error NotImplemented();
    error NoDepositTakeover();
    error UnsupportedAsset();

    struct SwapRepayData {
        bytes32 asset;
        address hubChainAddress;
        uint256 need;
        uint256 have;
    }

    uint256 public constant MAX_SLIPPAGE_PRECISION = 1e4;

    // default Uniswap pool fee is 0.3%
    uint24 public poolFee = 3000;

    IPool public immutable override POOL;
    IPoolAddressesProvider public immutable override ADDRESSES_PROVIDER;
    ISwapRouter public immutable UNISWAP_ROUTER;
    ISynonymPriceOracle public immutable PRICE_ORACLE;
    IERC20 public immutable PROFIT_TOKEN;
    bytes32 public immutable PROFIT_TOKEN_ASSET_ID;
    uint8 public immutable PROFIT_TOKEN_DECIMALS;
    uint16 public immutable HUB_CHAIN_ID;
    address public profitReceiver;
    uint256 public maxSlippage;

    constructor(
        IHub _hub,
        IPool _pool,
        ISwapRouter _uniswapRouter,
        ISynonymPriceOracle _synonymPriceOracle,
        IERC20 _profitToken,
        address _profitReceiver,
        address[] memory _liquidators,
        uint256 _maxSlippage
    ) Liquidator(_hub, _liquidators) {
        require(address(_pool) != address(0), "LiquidatorFlashLoan: pool address is zero");
        require(address(_uniswapRouter) != address(0), "LiquidatorFlashLoan: uniswap router address is zero");
        require(address(_synonymPriceOracle) != address(0), "LiquidatorFlashLoan: synonym price oracle address is zero");

        POOL = _pool;
        ADDRESSES_PROVIDER = IPoolAddressesProvider(_pool.ADDRESSES_PROVIDER());
        UNISWAP_ROUTER = _uniswapRouter;
        PRICE_ORACLE = _synonymPriceOracle;
        PROFIT_TOKEN = _profitToken;
        PROFIT_TOKEN_DECIMALS = IERC20decimals(address(PROFIT_TOKEN)).decimals();
        HUB_CHAIN_ID = hub.getWormholeTunnel().chainId();
        PROFIT_TOKEN_ASSET_ID = hub.getAssetRegistry().getAssetId(HUB_CHAIN_ID, toWormholeFormat(address(PROFIT_TOKEN)));
        setProfitReceiver(_profitReceiver);
        setMaxSlippage(_maxSlippage);

        // pre-approve the router to spend WETH
        PROFIT_TOKEN.forceApprove(address(UNISWAP_ROUTER), type(uint256).max);
    }

    function setProfitReceiver(address _profitReceiver) public onlyOwner {
        require(_profitReceiver != address(0), "LiquidatorFlashLoan: profit receiver address is zero");
        require(_profitReceiver != address(this), "LiquidatorFlashLoan: profit receiver address is self (possible griefing attack)");
        profitReceiver = _profitReceiver;
    }

    function setMaxSlippage(uint256 _maxSlippage) public onlyOwner {
        require(_maxSlippage <= MAX_SLIPPAGE_PRECISION, "LiquidatorFlashLoan: max slippage too high");
        require(_maxSlippage > 0, "LiquidatorFlashLoan: max slippage too low");
        maxSlippage = _maxSlippage;
    }

    function setPoolFee(uint24 _poolFee) public onlyOwner {
        require(_poolFee > 0, "LiquidatorFlashLoan: pool fee can't be zero");
        require(_poolFee <= 10000, "LiquidatorFlashLoan: pool fee too high");
        poolFee = _poolFee;
    }

    function withdrawHubDeposit(bytes32, uint256) external pure override {
        revert NotImplemented();
    }

    function liquidation(ILiquidationCalculator.LiquidationInput memory input) public virtual override onlyLiquidator {
        uint256 nonZeroRepays = 0;
        for (uint256 i = 0; i < input.assets.length; i++) {
            if (input.assets[i].repaidAmount > 0) {
                nonZeroRepays++;
            }

            if (input.assets[i].paymentMethod == ILiquidationCalculator.PaymentMethod.DEPOSIT_TAKEOVER) {
                revert NoDepositTakeover();
            }
        }

        IAssetRegistry assetRegistry = hub.getAssetRegistry();

        address[] memory flashLoanAssets = new address[](nonZeroRepays);
        uint256[] memory flashLoanAmounts = new uint256[](nonZeroRepays);
        uint256 flashLoanIndex = 0;
        for (uint256 i = 0; i < input.assets.length; i++) {
            ILiquidationCalculator.DenormalizedLiquidationAsset memory asset = input.assets[i];
            if (asset.repaidAmount > 0) {
                address hubChainAssetAddress = fromWormholeFormat(assetRegistry.getAssetAddress(asset.assetId, HUB_CHAIN_ID));
                if (hubChainAssetAddress == address(0)) {
                    revert UnsupportedAsset();
                }
                flashLoanAssets[flashLoanIndex] = hubChainAssetAddress;
                flashLoanAmounts[flashLoanIndex] = asset.repaidAmount;
                flashLoanIndex++;
            }
        }
        // instantiated to all zeros, so no debt will be opened in Aave
        uint256[] memory interestRateModes = new uint256[](flashLoanAssets.length);
        POOL.flashLoan(
            address(this),
            flashLoanAssets,
            flashLoanAmounts,
            interestRateModes,
            address(0),
            abi.encode(input),
            0 // referral code
        );

        // the contract holds any excess in WETH
        // transfer any profits to the profit receiver
        uint256 wethBalance = PROFIT_TOKEN.balanceOf(address(this));
        if (wethBalance > 0) {
            PROFIT_TOKEN.safeTransfer(profitReceiver, wethBalance);
        }
    }

    function executeOperation(
        address[] calldata assets,
        uint256[] calldata amounts,
        uint256[] calldata premiums,
        address initiator,
        bytes calldata params
    ) external override returns (bool) {
        if (initiator != address(this) || msg.sender != address(POOL)) {
            revert InvalidFlashLoanInitiator();
        }

        if (assets.length == 0 || premiums.length == 0 || assets.length != amounts.length || assets.length != premiums.length) {
            revert InvalidFlashLoanParameters();
        }

        ILiquidationCalculator.LiquidationInput memory input = abi.decode(params, (ILiquidationCalculator.LiquidationInput));
        // liquidate as usual
        _liquidation(input);

        IAssetRegistry assetRegistry = hub.getAssetRegistry();

        SwapRepayData[] memory swapRepayData = new SwapRepayData[](input.assets.length);
        for (uint256 i = 0; i < input.assets.length; i++) {
            swapRepayData[i].asset = input.assets[i].assetId;
            swapRepayData[i].hubChainAddress = fromWormholeFormat(assetRegistry.getAssetAddress(input.assets[i].assetId, HUB_CHAIN_ID));
            swapRepayData[i].have = IERC20(swapRepayData[i].hubChainAddress).balanceOf(address(this));

            for (uint256 assetFlIdx = 0; assetFlIdx < assets.length; assetFlIdx++) {
                if (assets[assetFlIdx] == swapRepayData[i].hubChainAddress) {
                    swapRepayData[i].need = amounts[assetFlIdx] + premiums[assetFlIdx];
                    break;
                }
            }

            // no point in selling excess WETH for WETH
            // otherwise sell all excess to WETH
            if (swapRepayData[i].hubChainAddress != address(PROFIT_TOKEN) && swapRepayData[i].have > swapRepayData[i].need) {
                // swap the excess into WETH
                uint256 excess = swapRepayData[i].have - swapRepayData[i].need;
                IERC20(swapRepayData[i].hubChainAddress).forceApprove(address(UNISWAP_ROUTER), excess);
                uint256 fairAmountOut = PRICE_ORACLE.getOutputForInput(
                    input.assets[i].assetId,
                    IERC20decimals(swapRepayData[i].hubChainAddress).decimals(),
                    PROFIT_TOKEN_ASSET_ID,
                    PROFIT_TOKEN_DECIMALS,
                    excess
                );
                uint256 minAmountOut = fairAmountOut * (MAX_SLIPPAGE_PRECISION - maxSlippage) / MAX_SLIPPAGE_PRECISION;

                ISwapRouter.ExactInputSingleParams memory swapParams = ISwapRouter.ExactInputSingleParams({
                    tokenIn: swapRepayData[i].hubChainAddress,
                    tokenOut: address(PROFIT_TOKEN),
                    fee: poolFee,
                    recipient: address(this),
                    deadline: block.timestamp,
                    amountIn: excess,
                    amountOutMinimum: minAmountOut,
                    sqrtPriceLimitX96: 0 // no price limit. the minAmountOut sets the min price
                });

                // The call to `exactInputSingle` executes the swap.
                UNISWAP_ROUTER.exactInputSingle(swapParams);
                swapRepayData[i].have = swapRepayData[i].need;
            }

            if (swapRepayData[i].need > 0) {
                // approve the returned amount to the pool
                IERC20(swapRepayData[i].hubChainAddress).forceApprove(address(POOL), swapRepayData[i].need);
            }
        }

        for (uint256 i = 0; i < swapRepayData.length; i++) {
            // WETH is already there. no point to buy it
            if (swapRepayData[i].hubChainAddress != address(PROFIT_TOKEN) && swapRepayData[i].have < swapRepayData[i].need) {
                uint256 deficit = swapRepayData[i].need - swapRepayData[i].have;
                uint256 fairAmountIn = PRICE_ORACLE.getInputForOutput(
                    PROFIT_TOKEN_ASSET_ID,
                    PROFIT_TOKEN_DECIMALS,
                    swapRepayData[i].asset,
                    IERC20decimals(swapRepayData[i].hubChainAddress).decimals(),
                    deficit
                );
                uint256 maxAmountIn = fairAmountIn * (MAX_SLIPPAGE_PRECISION + maxSlippage) / MAX_SLIPPAGE_PRECISION;

                ISwapRouter.ExactOutputSingleParams memory swapParams = ISwapRouter.ExactOutputSingleParams({
                    tokenIn: address(PROFIT_TOKEN),
                    tokenOut: swapRepayData[i].hubChainAddress,
                    fee: poolFee,
                    recipient: address(this),
                    deadline: block.timestamp,
                    amountOut: deficit,
                    amountInMaximum: maxAmountIn,
                    sqrtPriceLimitX96: 0 // no price limit. the maxAmountIn sets the max price
                });

                UNISWAP_ROUTER.exactOutputSingle(swapParams);
            }
        }

        return true;
    }

}