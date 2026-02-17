// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.28;

import {IExchangeConnector} from "../interface/IExchangeConnector.sol";
import {ICurvePool} from "../interface/ICurvePool.sol";
import {IWETH} from "../interface/IWETH.sol";
import {IStEth} from "../interface/IStEth.sol";
import {IwstETH} from "../interface/IwstETH.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";

contract CurveStEthEthExchangeConnector is IExchangeConnector {
    using SafeERC20 for IERC20;

    ICurvePool public immutable pool;
    address public immutable stEth;
    address public immutable wstETH;
    IWETH public immutable weth;

    error InvalidTokenPair();
    error SlippageExceeded();
    error EthTransferFailed();

    constructor(address _pool, address _weth, address _wstETH) {
        require(_pool != address(0) && _weth != address(0) && _wstETH != address(0), "Zero address");
        pool = ICurvePool(_pool);
        stEth = ICurvePool(_pool).coins(1);
        weth = IWETH(_weth);
        wstETH = _wstETH;
        require(stEth != address(0), "Invalid pool coins");
    }

    receive() external payable {}

    function _assetToIndex(address asset) internal view returns (int128 index, bool isWeth) {
        if (asset == address(weth)) return (0, true);
        if (asset == wstETH) return (1, false);
        revert InvalidTokenPair();
    }

    function _requireValidPair(address assetIn, address assetOut) internal view {
        (int128 i,) = _assetToIndex(assetIn);
        (int128 j,) = _assetToIndex(assetOut);
        require(i != j, InvalidTokenPair());
    }

    function _exchangeWethToWstEthIn(uint256 amountIn, uint256 minAmountOut) internal returns (uint256 amountOut) {
        weth.withdraw(amountIn);
        uint256 receivedStEth = pool.exchange(0, 1, amountIn, 0);
        IERC20(stEth).forceApprove(wstETH, receivedStEth);
        amountOut = IwstETH(wstETH).wrap(receivedStEth);
        require(amountOut >= minAmountOut, SlippageExceeded());
        IERC20(wstETH).safeTransfer(msg.sender, amountOut);
    }

    function _exchangeWethToWstEthOut(uint256 amountOut, uint256 maxAmountIn) internal returns (uint256 amountIn) {
        uint256 minStEth = (amountOut * IStEth(stEth).totalSupply() + IStEth(stEth).getTotalShares() - 1)
            / IStEth(stEth).getTotalShares();
        weth.withdraw(maxAmountIn);
        uint256 receivedStEth = pool.exchange(0, 1, maxAmountIn, minStEth);
        require(receivedStEth >= minStEth, SlippageExceeded());
        IERC20(stEth).forceApprove(wstETH, receivedStEth);
        uint256 wstEthReceived = IwstETH(wstETH).wrap(receivedStEth);
        require(wstEthReceived >= amountOut, SlippageExceeded());
        IERC20(wstETH).safeTransfer(msg.sender, amountOut);

        uint256 excessWstEth = wstEthReceived - amountOut;
        uint256 amountBack = 0;
        if (excessWstEth > 0) {
            uint256 stEthExcess = IwstETH(wstETH).unwrap(excessWstEth);
            amountBack = pool.exchange(1, 0, stEthExcess, 0);
        }
        amountIn = maxAmountIn - amountBack;
        if (amountBack > 0) {
            weth.deposit{value: amountBack}();
            IERC20(address(weth)).safeTransfer(msg.sender, amountBack);
        }
    }

    function _exchangeWstEthToWethIn(uint256 amountIn, uint256 minAmountOut) internal returns (uint256 amountOut) {
        uint256 stEthAmount = IwstETH(wstETH).unwrap(amountIn);
        IERC20(stEth).forceApprove(address(pool), stEthAmount);
        amountOut = pool.exchange(1, 0, stEthAmount, minAmountOut);
        require(amountOut >= minAmountOut, SlippageExceeded());
        weth.deposit{value: amountOut}();
        IERC20(address(weth)).safeTransfer(msg.sender, amountOut);
    }

    function _exchangeWstEthToWethOut(uint256 amountOut, uint256 maxAmountIn) internal returns (uint256 amountIn) {
        uint256 stEthAmount = IwstETH(wstETH).unwrap(maxAmountIn);
        IERC20(stEth).forceApprove(address(pool), stEthAmount);
        uint256 receivedEth = pool.exchange(1, 0, stEthAmount, amountOut);
        require(receivedEth >= amountOut, SlippageExceeded());
        weth.deposit{value: amountOut}();
        IERC20(address(weth)).safeTransfer(msg.sender, amountOut);

        uint256 excessEth = receivedEth - amountOut;
        uint256 amountBackWstEth = 0;
        if (excessEth > 0) {
            uint256 amountBackStEth = pool.exchange{value: excessEth}(0, 1, excessEth, 0);
            IERC20(stEth).forceApprove(wstETH, amountBackStEth);
            amountBackWstEth = IwstETH(wstETH).wrap(amountBackStEth);
        }
        amountIn = maxAmountIn - amountBackWstEth;
        if (amountBackWstEth > 0) {
            IERC20(wstETH).safeTransfer(msg.sender, amountBackWstEth);
        }
    }

    function exchangeOut(address assetIn, address assetOut, uint256 amountOut, uint256 maxAmountIn)
        external
        payable
        override
        returns (uint256 amountIn)
    {
        _requireValidPair(assetIn, assetOut);
        IERC20(assetIn).safeTransferFrom(msg.sender, address(this), maxAmountIn);

        (, bool inIsWeth) = _assetToIndex(assetIn);
        if (inIsWeth) {
            return _exchangeWethToWstEthOut(amountOut, maxAmountIn);
        } else {
            return _exchangeWstEthToWethOut(amountOut, maxAmountIn);
        }
    }

    function exchangeIn(address assetIn, address assetOut, uint256 amountIn, uint256 minAmountOut)
        external
        payable
        override
        returns (uint256 amountOut)
    {
        _requireValidPair(assetIn, assetOut);
        IERC20(assetIn).safeTransferFrom(msg.sender, address(this), amountIn);

        (, bool inIsWeth) = _assetToIndex(assetIn);
        if (inIsWeth) {
            return _exchangeWethToWstEthIn(amountIn, minAmountOut);
        } else {
            return _exchangeWstEthToWethIn(amountIn, minAmountOut);
        }
    }
}