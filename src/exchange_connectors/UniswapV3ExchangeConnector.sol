// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.28;

import {IExchangeConnector} from "../interface/IExchangeConnector.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";

interface IUniswapV3Pool {
    function token0() external view returns (address);
    function token1() external view returns (address);
    function swap(
        address recipient,
        bool zeroForOne,
        int256 amountSpecified,
        uint160 sqrtPriceLimitX96,
        bytes calldata data
    ) external returns (int256 amount0, int256 amount1);
}

interface IUniswapV3SwapCallback {
    function uniswapV3SwapCallback(int256 amount0Delta, int256 amount1Delta, bytes calldata data) external;
}

contract UniswapV3ExchangeConnector is IExchangeConnector, IUniswapV3SwapCallback {
    using SafeERC20 for IERC20;

    IUniswapV3Pool public immutable pool;

    error InvalidPool();
    error InvalidTokenPair();
    error InsufficientInputAmount();
    error InvalidOutputAmount();
    error SlippageExceeded();
    error InvalidCaller();
    error InvalidSwapCallback();
    error InvalidToken();

    constructor(address _uniswapV3Pool) {
        require(_uniswapV3Pool != address(0), InvalidPool());
        pool = IUniswapV3Pool(_uniswapV3Pool);
    }

    function exchangeOut(address assetIn, address assetOut, uint256 amountOut, uint256 maxAmountIn)
        external
        payable
        override
        returns (uint256 amountIn)
    {
        address token0 = pool.token0();
        address token1 = pool.token1();

        require(
            (assetIn == token0 && assetOut == token1) || (assetIn == token1 && assetOut == token0), InvalidTokenPair()
        );

        bool zeroForOne = assetIn == token0;

        IERC20(assetIn).safeTransferFrom(msg.sender, address(this), maxAmountIn);

        bytes memory data = abi.encode(assetIn);

        (int256 amount0Delta, int256 amount1Delta) = pool.swap(msg.sender, zeroForOne, -int256(amountOut), 0, data);

        if (zeroForOne) {
            amountIn = uint256(-amount0Delta);
            uint256 actualAmountOut = uint256(amount1Delta);
            require(actualAmountOut == amountOut, InvalidOutputAmount());
        } else {
            amountIn = uint256(-amount1Delta);
            uint256 actualAmountOut = uint256(amount0Delta);
            require(actualAmountOut == amountOut, InvalidOutputAmount());
        }

        require(amountIn <= maxAmountIn, SlippageExceeded());

        uint256 remaining = maxAmountIn - amountIn;
        if (remaining > 0) {
            IERC20(assetIn).safeTransfer(msg.sender, remaining);
        }
    }

    function exchangeIn(address assetIn, address assetOut, uint256 amountIn, uint256 minAmountOut)
        external
        payable
        override
        returns (uint256 amountOut)
    {
        address token0 = pool.token0();
        address token1 = pool.token1();

        require(
            (assetIn == token0 && assetOut == token1) || (assetIn == token1 && assetOut == token0), InvalidTokenPair()
        );

        bool zeroForOne = assetIn == token0;

        IERC20(assetIn).safeTransferFrom(msg.sender, address(this), amountIn);

        bytes memory data = abi.encode(assetIn);

        (int256 amount0Delta, int256 amount1Delta) = pool.swap(msg.sender, zeroForOne, int256(amountIn), 0, data);

        if (zeroForOne) {
            uint256 actualAmountIn = uint256(-amount0Delta);
            require(actualAmountIn <= amountIn, InsufficientInputAmount());
            amountOut = uint256(amount1Delta);
        } else {
            uint256 actualAmountIn = uint256(-amount1Delta);
            require(actualAmountIn <= amountIn, InsufficientInputAmount());
            amountOut = uint256(amount0Delta);
        }

        require(amountOut >= minAmountOut, SlippageExceeded());
    }

    function uniswapV3SwapCallback(int256 amount0Delta, int256 amount1Delta, bytes calldata data) external override {
        require(msg.sender == address(pool), InvalidCaller());

        address tokenIn = abi.decode(data, (address));

        address token0 = pool.token0();
        address tokenToPay;
        uint256 amountToPay;

        if (amount0Delta < 0) {
            tokenToPay = token0;
            amountToPay = uint256(-amount0Delta);
        } else if (amount1Delta < 0) {
            tokenToPay = pool.token1();
            amountToPay = uint256(-amount1Delta);
        } else {
            revert InvalidSwapCallback();
        }

        require(tokenToPay == tokenIn, InvalidToken());

        IERC20(tokenToPay).safeTransfer(msg.sender, amountToPay);
    }
}
