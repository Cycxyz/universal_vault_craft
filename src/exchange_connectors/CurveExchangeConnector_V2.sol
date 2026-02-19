// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.28;

import {IExchangeConnector} from "../interface/IExchangeConnector.sol";
import {ICurvePool} from "../interface/ICurvePool.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import {IExchangeWrapper} from "../interface/IExchangeWrapper.sol";
import {console} from "forge-std/console.sol";

struct ExchangeInParams {
    address assetIn;
    address poolAssetIn;
    address assetOut;
    address poolAssetOut;
    uint256 amountIn;
    uint256 minAmountOut;
    address preExchangeWrapper;
    address postExchangeWrapper;
}

struct ExchangeOutParams {
    address assetIn;
    address poolAssetIn;
    address assetOut;
    address poolAssetOut;
    uint256 amountOut;
    uint256 maxAmountIn;
    address preExchangeWrapper;
    address postExchangeWrapper;
}

contract CurveExchangeConnector {
    using SafeERC20 for IERC20;

    ICurvePool public immutable pool;
    uint256 public immutable numCoins;
    address constant ETH = 0xEeeeeEeeeEeEeeEeEeEeeEEEeeeeEeeeeeeeEEeE;

    error InvalidTokenPair();
    error TokenNotFound();
    error SlippageExceeded();
    error InvalidPool();

    error ZeroPool();
    error WrappingOperationFailed(address wrapper, address assetIn, address assetOut, uint256 amountIn);
    error WrappingOperationMismatch(
        address wrapper,
        address assetIn,
        address assetOut,
        uint256 amountIn,
        uint256 amountOut,
        uint256 expectedAmountOut
    );

    constructor(address _pool, uint256 _numCoins) {
        require(_pool != address(0), ZeroPool());
        require(_numCoins > 0, InvalidPool());
        pool = ICurvePool(_pool);
        numCoins = _numCoins;
    }

    function exchangeIn(ExchangeInParams memory params) external payable returns (uint256 amountOut) {
        (int128 i, int128 j) = _requireValidPair(params.poolAssetIn, params.poolAssetOut);

        IERC20(params.assetIn).safeTransferFrom(msg.sender, address(this), params.amountIn);
        if (params.preExchangeWrapper != address(0)) {
            params.amountIn = _executeWrappingOperation(
                params.preExchangeWrapper, params.assetIn, params.poolAssetIn, params.amountIn
            );
        }

        amountOut = _swapOnCurve(i, j, params.amountIn, params.minAmountOut, params.poolAssetIn);

        if (params.postExchangeWrapper != address(0)) {
            amountOut =
                _executeWrappingOperation(params.postExchangeWrapper, params.poolAssetOut, params.assetOut, amountOut);
        }

        require(amountOut >= params.minAmountOut, SlippageExceeded());
        IERC20(params.assetOut).safeTransfer(msg.sender, amountOut);
    }

    function exchangeOut(ExchangeOutParams memory params) external payable returns (uint256 amountIn) {
        (int128 i, int128 j) = _requireValidPair(params.poolAssetIn, params.poolAssetOut);

        IERC20(params.assetIn).safeTransferFrom(msg.sender, address(this), params.maxAmountIn);
        uint256 maxAmountInPool = params.maxAmountIn;
        if (params.preExchangeWrapper != address(0)) {
            maxAmountInPool = _executeWrappingOperation(
                params.preExchangeWrapper, params.assetIn, params.poolAssetIn, params.maxAmountIn
            );
        }

        uint256 received = _swapOnCurve(i, j, maxAmountInPool, 0, params.poolAssetIn);

        uint256 refundToExchange;
        if (params.postExchangeWrapper != address(0)) {
            uint256 neededAssets = IExchangeWrapper(params.postExchangeWrapper).previewWrappingOperation(
                params.poolAssetOut, params.assetOut, params.amountOut
            );
            require(received >= neededAssets, SlippageExceeded());
            uint256 realAmountOut = _executeWrappingOperation(
                params.postExchangeWrapper, params.poolAssetOut, params.assetOut, neededAssets
            );

            require(
                realAmountOut == params.amountOut,
                WrappingOperationMismatch(
                    params.postExchangeWrapper,
                    params.poolAssetOut,
                    params.assetOut,
                    received,
                    realAmountOut,
                    params.amountOut
                )
            );
            refundToExchange = received - neededAssets;
        } else {
            refundToExchange = received - params.amountOut;
        }

        uint256 refundAmount;
        if (refundToExchange > 0) {
            refundAmount = _swapOnCurve(j, i, refundToExchange, 0, params.poolAssetOut);
            if (params.preExchangeWrapper != address(0)) {
                refundAmount = _executeWrappingOperation(
                    params.preExchangeWrapper, params.poolAssetIn, params.assetIn, refundAmount
                );
            }
            IERC20(params.assetIn).safeTransfer(msg.sender, refundAmount);
        }

        IERC20(params.assetOut).safeTransfer(msg.sender, params.amountOut);
        amountIn = params.maxAmountIn - refundAmount;
    }

    receive() external payable {}

    function _findTokenIndex(address token) internal view returns (int128 index) {
        for (uint256 i = 0; i < numCoins; i++) {
            if (pool.coins(i) == token) {
                return int128(int256(i));
            }
        }
        revert TokenNotFound();
    }

    function _swapOnCurve(int128 i, int128 j, uint256 amountIn, uint256 minAmountOut, address assetIn)
        internal
        returns (uint256 amountOut)
    {
        if (assetIn == ETH) {
            amountOut = pool.exchange{value: amountIn}(i, j, amountIn, minAmountOut);
        } else {
            IERC20(assetIn).forceApprove(address(pool), amountIn);
            amountOut = pool.exchange(i, j, amountIn, minAmountOut);
        }
        return amountOut;
    }

    function _requireValidPair(address assetIn, address assetOut) internal view returns (int128 i, int128 j) {
        i = _findTokenIndex(assetIn);
        j = _findTokenIndex(assetOut);
        require(i != j, InvalidTokenPair());
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
}
