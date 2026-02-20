// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.28;

import {IExchangeWrapper} from "../interface/IExchangeWrapper.sol";
import {IsUSDE} from "../interface/IsUSDE.sol";
import {SafeERC20, IERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import {IERC4626} from "@openzeppelin/contracts/interfaces/IERC4626.sol";

contract Eip4626Wrapper is IExchangeWrapper {
    using SafeERC20 for IERC20;

    IERC20 public immutable baseToken;
    IERC4626 public immutable wrappedToken;

    error InvalidTokenPair();

    constructor(address _baseToken, address _wrappedToken) {
        baseToken = IERC20(_baseToken);
        wrappedToken = IERC4626(_wrappedToken);
    }

    function previewWrappingOperation(address assetIn, address assetOut, uint256 amountOut)
        external
        view
        override
        returns (uint256 amountIn)
    {
        if (assetIn == address(baseToken) && assetOut == address(wrappedToken)) {
            return wrappedToken.previewMint(amountOut);
        } else if (assetIn == address(wrappedToken) && assetOut == address(baseToken)) {
            return wrappedToken.previewWithdraw(amountOut);
        }
        revert InvalidTokenPair();
    }

    function executeWrappingOperationIn(address assetIn, address assetOut, uint256 amountIn)
        external
        override
        returns (uint256 amountOut)
    {
        if (assetIn == address(baseToken) && assetOut == address(wrappedToken)) {
            IERC20(assetIn).forceApprove(address(wrappedToken), amountIn);
            return wrappedToken.deposit(amountIn, address(this));
        } else if (assetIn == address(wrappedToken) && assetOut == address(baseToken)) {
            return wrappedToken.withdraw(amountIn, address(this), address(this));
        }
        revert InvalidTokenPair();
    }

    function executeWrappingOperationOut(address assetIn, address assetOut, uint256 amountOut)
        external
        override
        returns (uint256 amountIn)
    {
        if (assetIn == address(baseToken) && assetOut == address(wrappedToken)) {
            IERC20(assetIn).forceApprove(address(wrappedToken), wrappedToken.previewMint(amountOut));
            return wrappedToken.mint(amountOut, address(this));
        } else if (assetIn == address(wrappedToken) && assetOut == address(baseToken)) {
            return wrappedToken.withdraw(amountOut, address(this), address(this));
        }
        revert InvalidTokenPair();
    }
}
