// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.28;

import {IExchangeConnector} from "../interface/IExchangeConnector.sol";
import {ICurvePool} from "../interface/ICurvePool.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";

contract CurveExchangeConnector is IExchangeConnector {
    using SafeERC20 for IERC20;

    ICurvePool public immutable pool;
    uint256 public immutable numCoins;

    error InvalidTokenPair();
    error TokenNotFound();
    error SlippageExceeded();
    error InvalidPool();

    constructor(address _pool, uint256 _numCoins) {
        require(_pool != address(0), InvalidPool());
        require(_numCoins > 0, InvalidPool());
        pool = ICurvePool(_pool);
        numCoins = _numCoins;
    }

    receive() external payable {}

    function _findTokenIndex(address token) internal view returns (int128 index) {
        for (uint256 i = 0; i < numCoins; i++) {
            if (pool.coins(i) == token) {
                return int128(int256(i));
            }
        }
        revert TokenNotFound();
    }

    function _requireValidPair(address assetIn, address assetOut) internal view returns (int128 i, int128 j) {
        i = _findTokenIndex(assetIn);
        j = _findTokenIndex(assetOut);
        require(i != j, InvalidTokenPair());
    }

    function exchangeIn(address assetIn, address assetOut, uint256 amountIn, uint256 minAmountOut)
        external
        override
        returns (uint256 amountOut)
    {
        (int128 i, int128 j) = _requireValidPair(assetIn, assetOut);
        
        IERC20(assetIn).safeTransferFrom(msg.sender, address(this), amountIn);
        SafeERC20.forceApprove(IERC20(assetIn), address(pool), amountIn);

        amountOut = pool.exchange(i, j, amountIn, minAmountOut);
        require(amountOut >= minAmountOut, SlippageExceeded());

        IERC20(assetOut).safeTransfer(msg.sender, amountOut);
    }

    function exchangeOut(address assetIn, address assetOut, uint256 amountOut, uint256 maxAmountIn)
        external
        override
        returns (uint256 amountIn)
    {
        (int128 i, int128 j) = _requireValidPair(assetIn, assetOut);
        
        IERC20(assetIn).safeTransferFrom(msg.sender, address(this), maxAmountIn);
        SafeERC20.forceApprove(IERC20(assetIn), address(pool), maxAmountIn);
        
        uint256 received = pool.exchange(i, j, maxAmountIn, amountOut);
        require(received >= amountOut, SlippageExceeded());

        IERC20(assetOut).safeTransfer(msg.sender, amountOut);

        uint256 excess = received - amountOut;
        if (excess > 0) {
            SafeERC20.forceApprove(IERC20(assetOut), address(pool), excess);
            uint256 refunded = pool.exchange(j, i, excess, 0);
            IERC20(assetIn).safeTransfer(msg.sender, refunded);
            amountIn = maxAmountIn - refunded;
        } else {
            amountIn = maxAmountIn;
        }
    }
}
