// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.28;

import {IExchangeWrapper} from "../interface/IExchangeWrapper.sol";
import {SafeERC20, IERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import {IStEth} from "../interface/IStEth.sol";
import {IwstETH} from "../interface/IwstETH.sol";

contract StEthWstEthWrapper is IExchangeWrapper {
    using SafeERC20 for IERC20;

    error InvalidTokenPair();

    IStEth public constant stEth = IStEth(0xae7ab96520DE3A18E5e111B5EaAb095312D7fE84);
    IwstETH public constant wstEth = IwstETH(0x7f39C581F595B53c5cb19bD0b3f8dA6c935E2Ca0);

    modifier onlyStEthWstEth(address assetIn, address assetOut) {
        require(
            (assetIn == address(stEth) && assetOut == address(wstEth))
                || (assetIn == address(wstEth) && assetOut == address(stEth)),
            InvalidTokenPair()
        );
        _;
    }

    function previewWrappingOperation(address assetIn, address assetOut, uint256 amountOut)
        external
        view
        onlyStEthWstEth(assetIn, assetOut)
        returns (uint256 amountIn)
    {
        if (assetIn == address(stEth)) {
            uint256 totalShares = IStEth(stEth).getTotalShares();
            uint256 totalSupply = IStEth(stEth).totalSupply();
            return (amountOut * totalSupply + totalShares - 1) / totalShares;
        } else {
            uint256 totalShares = IStEth(stEth).getTotalShares();
            uint256 totalSupply = IStEth(stEth).totalSupply();
            return amountOut * totalShares / totalSupply;
        }
    }

    function executeWrappingOperation(address assetIn, address assetOut, uint256 amountIn)
        external
        override
        onlyStEthWstEth(assetIn, assetOut)
        returns (uint256 amountOut)
    {
        if (assetIn == address(stEth)) {
            IERC20(address(stEth)).forceApprove(address(wstEth), amountIn);
            amountOut = IwstETH(wstEth).wrap(amountIn);
        } else {
            amountOut = IwstETH(wstEth).unwrap(amountIn);
        }
        return amountOut;
    }
}