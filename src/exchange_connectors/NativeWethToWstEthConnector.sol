// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.28;

import {IExchangeConnector_v0} from "../interface/IExchangeConnector_v0.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";

interface IWETH {
    function withdraw(uint256 wad) external;
}

interface IwstETH {
    function getStETHByWstETH(uint256 _wstETHAmount) external view returns (uint256);
    function getWstETHByStETH(uint256 _stETHAmount) external view returns (uint256);
}

interface IStEth {
    function totalSupply() external view returns (uint256);
    function getTotalShares() external view returns (uint256);
}

contract NativeWethToWstEthConnector is IExchangeConnector_v0 {
    using SafeERC20 for IERC20;

    IWETH public constant weth = IWETH(0xC02aaA39b223FE8D0A0e5C4F27eAD9083C756Cc2);
    address public constant wstETH = 0x7f39C581F595B53c5cb19bD0b3f8dA6c935E2Ca0;
    address public constant stEth = 0xae7ab96520DE3A18E5e111B5EaAb095312D7fE84;

    error InvalidTokenPair();
    error SlippageExceeded();
    error EthTransferFailed();

    receive() external payable {}

    function exchangeOut(address assetIn, address assetOut, uint256 amountOut, uint256 maxAmountIn)
        external
        payable
        override
        returns (uint256 amountIn)
    {
        _requireWethToWstEth(assetIn, assetOut);

        // To get exactly amountOut wstETH we need this much stETH/ETH (1:1 from Lido submit)
        uint256 totalShares = IStEth(stEth).getTotalShares();
        uint256 ethRequired = (amountOut * IStEth(stEth).totalSupply() + totalShares - 1) / totalShares;
        require(ethRequired <= maxAmountIn, SlippageExceeded());

        IERC20(assetIn).safeTransferFrom(msg.sender, address(this), maxAmountIn);

        weth.withdraw(ethRequired);

        uint256 wstEthBalance = IERC20(wstETH).balanceOf(address(this));
        (bool ok,) = wstETH.call{value: ethRequired}("");
        require(ok, EthTransferFailed());

        uint256 received = IERC20(wstETH).balanceOf(address(this)) - wstEthBalance;
        require(received >= amountOut, SlippageExceeded());

        IERC20(wstETH).safeTransfer(msg.sender, amountOut);

        uint256 remainingWeth = maxAmountIn - ethRequired;
        if (remainingWeth > 0) {
            IERC20(assetIn).safeTransfer(msg.sender, remainingWeth);
        }

        return ethRequired;
    }

    /// @inheritdoc IExchangeConnector_v0
    function exchangeIn(address assetIn, address assetOut, uint256 amountIn, uint256 minAmountOut)
        external
        payable
        override
        returns (uint256 amountOut)
    {
        _requireWethToWstEth(assetIn, assetOut);

        IERC20(assetIn).safeTransferFrom(msg.sender, address(this), amountIn);

        weth.withdraw(amountIn);

        uint256 wstEthBalance = IERC20(wstETH).balanceOf(address(this));

        (bool ok,) = wstETH.call{value: amountIn}("");
        require(ok, EthTransferFailed());

        amountOut = IERC20(wstETH).balanceOf(address(this)) - wstEthBalance;
        require(amountOut >= minAmountOut, SlippageExceeded());

        IERC20(wstETH).safeTransfer(msg.sender, amountOut);
    }

    function _requireWethToWstEth(address assetIn, address assetOut) internal pure {
        require(assetIn == address(weth) && assetOut == wstETH, InvalidTokenPair());
    }
}
