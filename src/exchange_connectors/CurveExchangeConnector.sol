// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.28;

import {CommonExchangeConnector} from "./CommonExchangeConnector.sol";
import {IERC20, SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import {ICurvePool} from "../interface/ICurvePool.sol";

contract CurveExchangeConnector is CommonExchangeConnector {
    using SafeERC20 for IERC20;

    ICurvePool public immutable pool;
    uint256 public immutable numCoins;
    address constant ETH = 0xEeeeeEeeeEeEeeEeEeEeeEEEeeeeEeeeeeeeEEeE;

    error ZeroPool();
    error InvalidNumCoins();
    error InvalidTokenPair();

    constructor(address _pool, uint256 _numCoins) {
        require(_pool != address(0), ZeroPool());
        require(_numCoins > 0, InvalidNumCoins());
        pool = ICurvePool(_pool);
        numCoins = _numCoins;
    }

    function _swapIn(address swapAssetIn, address swapAssetOut, uint256 amountIn)
        internal
        override
        returns (uint256 amountOut)
    {
        (int128 i, int128 j) = _requireValidPair(swapAssetIn, swapAssetOut);
        return _swapOnCurve(i, j, amountIn, 0, swapAssetIn);
    }

    function _swapOut(address swapAssetIn, address swapAssetOut, uint256 maxAmountIn, uint256 amountOut)
        internal
        override
        returns (uint256 amountIn)
    {
        (int128 i, int128 j) = _requireValidPair(swapAssetIn, swapAssetOut);
        uint256 receivedAmountOut = _swapOnCurve(i, j, maxAmountIn, amountOut, swapAssetIn);
        uint256 excessAmountInSwapAssetOut = receivedAmountOut - amountOut;
        uint256 excessAmountInSwapAssetIn;
        if (excessAmountInSwapAssetOut > 0) {
            excessAmountInSwapAssetIn = _swapOnCurve(j, i, excessAmountInSwapAssetOut, 0, swapAssetOut);
        }
        amountIn = maxAmountIn - excessAmountInSwapAssetIn;
        return amountIn;
    }

    function _swapOnCurve(int128 i, int128 j, uint256 amountIn, uint256 minAmountOut, address assetIn)
        internal
        returns (uint256 amountOut)
    {
        if (assetIn == ETH) {
            amountOut = pool.get_dy(i, j, amountIn);
            pool.exchange{value: amountIn}(i, j, amountIn, minAmountOut);
        } else {
            amountOut = pool.get_dy(i, j, amountIn);
            IERC20(assetIn).forceApprove(address(pool), amountIn);
            pool.exchange(i, j, amountIn, minAmountOut);
        }
        return amountOut;
    }

    function _findTokenIndex(address token) internal view returns (int128 index) {
        for (uint256 i = 0; i < numCoins; i++) {
            if (pool.coins(i) == token) {
                return int128(int256(i));
            }
        }
        revert InvalidTokenPair();
    }

    function _requireValidPair(address assetIn, address assetOut) internal view returns (int128 i, int128 j) {
        i = _findTokenIndex(assetIn);
        j = _findTokenIndex(assetOut);
        require(i != j, InvalidTokenPair());
    }
}
