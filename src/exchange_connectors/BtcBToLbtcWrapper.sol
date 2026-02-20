// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.28;

import {IExchangeWrapper} from "../interface/IExchangeWrapper.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import {ILBTC} from "../interface/ILBTC.sol";

contract BtcBToLbtcWrapper is IExchangeWrapper {
    using SafeERC20 for IERC20;

    IERC20 public immutable BTC_B;
    ILBTC public immutable LBTC;

    error InvalidTokenPair();
    error InvalidRatio();
    error InvalidToken();

    constructor(address btcB, address lbtc) {
        require(btcB != address(0), InvalidToken());
        require(lbtc != address(0), InvalidToken());
        BTC_B = IERC20(btcB);
        LBTC = ILBTC(lbtc);
    }

    modifier onlyBtcBToLbtc(address assetIn, address assetOut) {
        require(assetIn == address(BTC_B) && assetOut == address(LBTC), InvalidTokenPair());
        _;
    }

    function previewWrappingOperation(address assetIn, address assetOut, uint256 amountOut)
        public
        view
        override
        onlyBtcBToLbtc(assetIn, assetOut)
        returns (uint256 amountIn)
    {
        uint256 rate = LBTC.ratio();
        require(rate != 0, InvalidRatio());
        return (amountOut * 1e18 + rate - 1) / rate;
    }

    function executeWrappingOperationIn(address assetIn, address assetOut, uint256 amountIn)
        external
        override
        onlyBtcBToLbtc(assetIn, assetOut)
        returns (uint256 amountOut)
    {
        uint256 balanceBefore = IERC20(address(LBTC)).balanceOf(address(this));
        BTC_B.forceApprove(address(LBTC), amountIn);
        LBTC.deposit(amountIn);
        uint256 balanceAfter = IERC20(address(LBTC)).balanceOf(address(this));
        amountOut = balanceAfter - balanceBefore;
        return amountOut;
    }

    function executeWrappingOperationOut(address assetIn, address assetOut, uint256 amountOut)
        external
        override
        onlyBtcBToLbtc(assetIn, assetOut)
        returns (uint256)
    {
        uint256 amountIn = previewWrappingOperation(assetIn, assetOut, amountOut);
        BTC_B.forceApprove(address(LBTC), amountIn);
        uint256 balanceBefore = IERC20(address(LBTC)).balanceOf(address(this));
        LBTC.deposit(amountIn);
        uint256 balanceAfter = IERC20(address(LBTC)).balanceOf(address(this));
        amountOut = balanceAfter - balanceBefore;

        require(amountOut >= amountOut, InvalidRatio());
        return amountIn;
    }
}
