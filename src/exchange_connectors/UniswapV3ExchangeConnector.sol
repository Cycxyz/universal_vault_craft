// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.28;

import {CommonExchangeConnector} from "./CommonExchangeConnector.sol";
import {IUniswapV3SwapCallback} from "../interface/IUniswapV3SwapCallback.sol";
import {IERC20, SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import {IUniswapV3Pool} from "../interface/IUniswapV3Pool.sol";

contract UniswapV3ExchangeConnector is CommonExchangeConnector, IUniswapV3SwapCallback {
    using SafeERC20 for IERC20;

    // Hardcoded addresses on Ethereum mainnet
    IUniswapV3Pool public immutable pool;
    uint160 internal constant MIN_SQRT_RATIO = 4295128739;
    uint160 internal constant MAX_SQRT_RATIO = 1461446703485210103287273052203988822378723970342;

    error ZeroPool();
    error InvalidTokenPair();
    error InvalidCaller();
    error InvalidSwapCallback();

    constructor(address _pool) {
        require(_pool != address(0), ZeroPool());
        pool = IUniswapV3Pool(_pool);
    }

    function uniswapV3SwapCallback(int256 amount0Delta, int256 amount1Delta, bytes calldata) external override {
        require(msg.sender == address(pool), InvalidCaller());

        if (amount0Delta > 0) {
            IERC20(pool.token0()).safeTransfer(address(pool), uint256(amount0Delta));
        } else if (amount1Delta > 0) {
            IERC20(pool.token1()).safeTransfer(address(pool), uint256(amount1Delta));
        } else {
            revert InvalidSwapCallback();
        }
    }

    function _swapIn(address swapAssetIn, address swapAssetOut, uint256 amountIn)
        internal
        override
        returns (uint256 amountOut)
    {
        _requirePairValidity(swapAssetIn, swapAssetOut);
        bool zeroForOne = swapAssetIn == pool.token0();
        IERC20(swapAssetIn).forceApprove(address(pool), amountIn);
        (int256 amount0Delta, int256 amount1Delta) = pool.swap(
            address(this), zeroForOne, int256(amountIn), zeroForOne ? MIN_SQRT_RATIO + 1 : MAX_SQRT_RATIO - 1, ""
        );
        return zeroForOne ? uint256(-amount1Delta) : uint256(-amount0Delta);
    }

    function _swapOut(address swapAssetIn, address swapAssetOut, uint256 maxAmountIn, uint256 amountOut)
        internal
        override
        returns (uint256 amountIn)
    {
        _requirePairValidity(swapAssetIn, swapAssetOut);
        bool zeroForOne = swapAssetIn == pool.token0();
        IERC20(swapAssetIn).forceApprove(address(pool), maxAmountIn);
        (int256 amount0Delta, int256 amount1Delta) = pool.swap(
            address(this), zeroForOne, -int256(amountOut), zeroForOne ? MIN_SQRT_RATIO + 1 : MAX_SQRT_RATIO - 1, ""
        );
        amountIn = zeroForOne ? uint256(amount0Delta) : uint256(amount1Delta);
        require(amountIn <= maxAmountIn, SlippageExceeded());

        IERC20(swapAssetIn).forceApprove(address(pool), 0);
        return amountIn;
    }

    function _requirePairValidity(address assetIn, address assetOut) internal view {
        require(
            assetIn == pool.token0() && assetOut == pool.token1()
                || assetIn == pool.token1() && assetOut == pool.token0(),
            InvalidTokenPair()
        );
    }
}
