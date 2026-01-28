// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.28;

interface IExchangeConnector {
    function exchangeOut(address assetIn, address assetOut, uint256 amountOut, uint256 maxAmountIn)
        external
        returns (uint256 amountIn);
    function exchangeIn(address assetIn, address assetOut, uint256 amountIn, uint256 minAmountOut)
        external
        returns (uint256 amountOut);
}
