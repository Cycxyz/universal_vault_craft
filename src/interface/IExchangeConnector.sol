// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.28;

interface IExchangeConnector {

    struct ExchangeInParams {
        address assetIn;
        address swapAssetIn;
        address assetOut;
        address swapAssetOut;
        uint256 amountIn;
        uint256 minAmountOut;
        address preExchangeWrapper;
        address postExchangeWrapper;
    }

    struct ExchangeOutParams {
        address assetIn;
        address swapAssetIn;
        address assetOut;
        address swapAssetOut;
        uint256 amountOut;
        uint256 maxAmountIn;
        address preExchangeWrapper;
        address postExchangeWrapper;
    }

    error WrappingOperationFailed(address wrapper, address assetIn, address assetOut, uint256 amountIn);
    error SlippageExceeded();

    function exchangeIn(ExchangeInParams memory params) external payable returns (uint256 amountOut);
    function exchangeOut(ExchangeOutParams memory params) external payable returns (uint256 amountIn);
}