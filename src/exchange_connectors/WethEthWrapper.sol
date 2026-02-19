// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.28;

import {IExchangeWrapper} from "../interface/IExchangeWrapper.sol";
import {SafeERC20, IERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import {IWETH} from "../interface/IWETH.sol";

contract WethEthWrapper is IExchangeWrapper {
    using SafeERC20 for IERC20;

    error InvalidTokenPair();

    IWETH public immutable weth;

    constructor(address _weth) {
        require(_weth != address(0), "Invalid WETH address");
        weth = IWETH(_weth);
    }

    modifier onlyWethEth(address assetIn, address assetOut) {
        require(
            (assetIn == address(weth) && assetOut == address(0xEeeeeEeeeEeEeeEeEeEeeEEEeeeeEeeeeeeeEEeE))
                || (assetIn == address(0xEeeeeEeeeEeEeeEeEeEeeEEEeeeeEeeeeeeeEEeE) && assetOut == address(weth)),
            InvalidTokenPair()
        );
        _;
    }

    function previewWrappingOperation(address assetIn, address assetOut, uint256 amountOut)
        external
        view
        onlyWethEth(assetIn, assetOut)
        returns (uint256 amountIn)
    {
        return amountOut;
    }

    function executeWrappingOperation(address assetIn, address assetOut, uint256 amountIn)
        external
        override
        onlyWethEth(assetIn, assetOut)
        returns (uint256 amountOut)
    {
        if (assetIn == address(weth)) {
            weth.withdraw(amountIn);
        } else {
            weth.deposit{value: amountIn}();
        }
        return amountIn;
    }
}
