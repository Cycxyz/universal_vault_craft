// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.28;

import {IExchangeConnector} from "../interface/IExchangeConnector.sol";
import {IExchangeWrapper} from "../interface/IExchangeWrapper.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";

abstract contract CommonExchangeConnector is IExchangeConnector {
    using SafeERC20 for IERC20;

    function exchangeIn(ExchangeInParams memory params) external payable override returns (uint256 amountOut) {
        IERC20(params.assetIn).safeTransferFrom(msg.sender, address(this), params.amountIn);
        uint256 swapAmountIn =
            _makePreSwapIfNeeded(params.preExchangeWrapper, params.assetIn, params.swapAssetIn, params.amountIn);
        uint256 swapAmountOut = _swapIn(params.swapAssetIn, params.swapAssetOut, swapAmountIn);
        require(swapAmountOut >= params.minAmountOut, SlippageExceeded());
        amountOut = _makePostSwapIfNeeded(params.postExchangeWrapper, params.swapAssetOut, params.assetOut, swapAmountOut);
        IERC20(params.assetOut).safeTransfer(msg.sender, amountOut);
        return amountOut;
    }

    function exchangeOut(ExchangeOutParams memory params) external payable override returns (uint256 amountIn) {
        IERC20(params.assetIn).safeTransferFrom(msg.sender, address(this), params.maxAmountIn);
        uint256 maxAmountInSwapAssetIn =
            _makePreSwapIfNeeded(params.preExchangeWrapper, params.assetIn, params.swapAssetIn, params.maxAmountIn);

        uint256 swapAmountOut =
            _calculateSwapOutAmount(params.postExchangeWrapper, params.swapAssetOut, params.assetOut, params.amountOut);
        uint256 swapAmountIn = _swapOut(params.swapAssetIn, params.swapAssetOut, maxAmountInSwapAssetIn, swapAmountOut);

        uint256 refundAmountInSwapAssetIn = maxAmountInSwapAssetIn - swapAmountIn;
        uint256 refundedAmountInAssetIn = _makeRefundIfNeeded(
            params.preExchangeWrapper, params.swapAssetIn, params.assetIn, refundAmountInSwapAssetIn
        );
        amountIn = params.maxAmountIn - refundedAmountInAssetIn;

        _makePostSwapIfNeeded(params.postExchangeWrapper, params.swapAssetOut, params.assetOut, swapAmountOut);
        IERC20(params.assetOut).safeTransfer(msg.sender, params.amountOut);
        return amountIn;
    }

    receive() external payable {}

    function _calculateSwapOutAmount(address postWrapper, address swapAssetOut, address assetOut, uint256 amountOut)
        internal
        view
        returns (uint256 swapAmountOut)
    {
        if (postWrapper != address(0)) {
            return IExchangeWrapper(postWrapper).previewWrappingOperation(swapAssetOut, assetOut, amountOut);
        }
        return amountOut;
    }

    function _executeWrappingOperation(address wrapper, address assetIn, address assetOut, uint256 amountIn)
        internal
        returns (uint256 amountOut)
    {
        (bool success, bytes memory data) = wrapper.delegatecall(
            abi.encodeCall(IExchangeWrapper.executeWrappingOperation, (assetIn, assetOut, amountIn))
        );
        require(success, WrappingOperationFailed(wrapper, assetIn, assetOut, amountIn));
        return abi.decode(data, (uint256));
    }

    function _makePreSwapIfNeeded(address wrapper, address assetIn, address assetOut, uint256 amountIn)
        internal
        returns (uint256 swapAmountIn)
    {
        if (wrapper != address(0)) {
            return _executeWrappingOperation(wrapper, assetIn, assetOut, amountIn);
        }
        return amountIn;
    }

    function _makeRefundIfNeeded(
        address preWrapper,
        address swapAssetIn,
        address assetIn,
        uint256 refundAmountInswapAssetIn
    ) internal returns (uint256 refundedInAssetsIn) {
        if (refundAmountInswapAssetIn == 0) {
            return 0;
        }

        if (preWrapper != address(0)) {
            refundedInAssetsIn = _executeWrappingOperation(preWrapper, swapAssetIn, assetIn, refundAmountInswapAssetIn);
        } else {
            refundedInAssetsIn = refundAmountInswapAssetIn;
        }

        IERC20(assetIn).safeTransfer(msg.sender, refundedInAssetsIn);
        return refundedInAssetsIn;
    }

    function _makePostSwapIfNeeded(address postWrapper, address assetIn, address assetOut, uint256 amountIn)
        internal
        returns (uint256 amountOut)
    {
        if (postWrapper != address(0)) {
            return _executeWrappingOperation(postWrapper, assetIn, assetOut, amountIn);
        }
        return amountIn;
    }

    function _swapIn(address swapAssetIn, address swapAssetOut, uint256 amountIn)
        internal
        virtual
        returns (uint256 amountOut);

    function _swapOut(address swapAssetIn, address swapAssetOut, uint256 maxAmountIn, uint256 amountOut)
        internal
        virtual
        returns (uint256 amountIn);
}
