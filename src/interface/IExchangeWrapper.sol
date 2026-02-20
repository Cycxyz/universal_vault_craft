// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.28;

interface IExchangeWrapper {
    function executeWrappingOperationIn(address assetIn, address assetOut, uint256 amountIn)
        external
        returns (uint256 amountOut);
    
    function executeWrappingOperationOut(address assetIn, address assetOut, uint256 amountOut)
        external
        returns (uint256 amountIn);
    
    function previewWrappingOperation(address assetIn, address assetOut, uint256 amountOut)
        external
        view
        returns (uint256 amountIn);
}