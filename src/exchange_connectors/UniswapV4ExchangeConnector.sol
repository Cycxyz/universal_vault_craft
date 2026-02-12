// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.28;

import {IExchangeConnector} from "../interface/IExchangeConnector.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import {PoolKey, SwapParams} from "../types/UniswapV4Structs.sol";
import {IPoolManager} from "../interface/IPoolManager.sol";
import {IPositionManager} from "../interface/IPositionManager.sol";
import {IUnlockCallback} from "../interface/IUnlockCallback.sol";
import {BalanceDeltaLibrary} from "../libraries/BalanceDeltaLibrary.sol";


contract UniswapV4ExchangeConnector is IExchangeConnector, IUnlockCallback {
    using SafeERC20 for IERC20;

    IPoolManager public immutable POOL_MANAGER;
    address public immutable CURRENCY_0;
    address public immutable CURRENCY_1;
    uint24 public immutable FEE;
    int24 public immutable TICK_SPACING;
    address public immutable HOOKS;

    error InvalidPool();
    error InvalidPositionManager();
    error InvalidTokenPair();
    error InsufficientInputAmount();
    error InvalidOutputAmount();
    error SlippageExceeded();
    error InvalidCaller();
    error InvalidSwapCallback();
    error InvalidToken();
    error ManagerLocked();
    error EthTransferFailed();

    // Swap data passed via bytes to avoid storage costs
    struct SwapData {
        address assetIn;
        address assetOut;
        address recipient; // Original caller
        uint256 amountOut;
        uint256 maxAmountIn;
        uint256 amountIn;
        uint256 minAmountOut;
        bool isExchangeOut;
    }

    constructor(address _poolManager, address _positionManager, bytes25 _poolId) {
        require(_poolManager != address(0), InvalidPool());
        require(_positionManager != address(0), InvalidPositionManager());
        PoolKey memory poolKey = IPositionManager(_positionManager).poolKeys(_poolId);
        require(poolKey.currency0 < poolKey.currency1, InvalidTokenPair());

        POOL_MANAGER = IPoolManager(_poolManager);
        CURRENCY_0 = poolKey.currency0;
        CURRENCY_1 = poolKey.currency1;
        FEE = poolKey.fee;
        TICK_SPACING = poolKey.tickSpacing;
        HOOKS = poolKey.hooks;
    }

    function exchangeOut(address assetIn, address assetOut, uint256 amountOut, uint256 maxAmountIn)
        external
        override
        returns (uint256 amountIn)
    {
        _validateTokenPair(assetIn, assetOut);

        address currencyIn = assetIn;
        bool zeroForOne = currencyIn == CURRENCY_0;

        IERC20(assetIn).safeTransferFrom(msg.sender, address(this), maxAmountIn);

        SwapData memory swapData = SwapData({
            assetIn: assetIn,
            assetOut: assetOut,
            recipient: msg.sender,
            amountOut: amountOut,
            maxAmountIn: maxAmountIn,
            amountIn: 0,
            minAmountOut: 0,
            isExchangeOut: true
        });

        POOL_MANAGER.sync(currencyIn);

        SwapParams memory params = SwapParams({
            zeroForOne: zeroForOne,
            amountSpecified: int256(amountOut),
            sqrtPriceLimitX96: 0
        });

        bytes memory unlockData = abi.encode(params, swapData);
        bytes memory result = POOL_MANAGER.unlock(unlockData);

        amountIn = abi.decode(result, (uint256));
        require(amountIn <= maxAmountIn, SlippageExceeded());

        uint256 remaining = maxAmountIn - amountIn;
        if (remaining > 0) {
            IERC20(assetIn).safeTransfer(msg.sender, remaining);
        }
    }

    function exchangeIn(address assetIn, address assetOut, uint256 amountIn, uint256 minAmountOut)
        external
        override
        returns (uint256 amountOut)
    {
        _validateTokenPair(assetIn, assetOut);

        address currencyIn = assetIn;
        bool zeroForOne = currencyIn == CURRENCY_0;

        IERC20(assetIn).safeTransferFrom(msg.sender, address(this), amountIn);

        // Prepare swap data
        SwapData memory swapData = SwapData({
            assetIn: assetIn,
            assetOut: assetOut,
            recipient: msg.sender,
            amountOut: 0,
            maxAmountIn: 0,
            amountIn: amountIn,
            minAmountOut: minAmountOut,
            isExchangeOut: false
        });

        // Sync currency before swap
        POOL_MANAGER.sync(currencyIn);

        // Execute swap via unlock mechanism
        SwapParams memory params = SwapParams({
            zeroForOne: zeroForOne,
            amountSpecified: -int256(amountIn), // Negative for exact input
            sqrtPriceLimitX96: 0 // No price limit
        });

        // Encode both SwapParams and SwapData to pass via bytes
        bytes memory unlockData = abi.encode(params, swapData);
        bytes memory result = POOL_MANAGER.unlock(unlockData);

        // Decode the returned amountOut
        amountOut = abi.decode(result, (uint256));
        require(amountOut >= minAmountOut, SlippageExceeded());
    }

    function unlockCallback(bytes calldata data) external override returns (bytes memory) {
        require(msg.sender == address(POOL_MANAGER), InvalidCaller());

        (SwapParams memory params, SwapData memory swapData) = abi.decode(data, (SwapParams, SwapData));

        // Execute swap and extract amounts
        int256 swapDelta = POOL_MANAGER.swap(_getPoolKey(), params, "");
        (uint256 amountIn, uint256 amountOut) = _extractSwapAmounts(swapDelta, params.zeroForOne);

        // Validate and process swap
        if (swapData.isExchangeOut) {
            return _handleExchangeOut(swapData, amountIn, amountOut);
        } else {
            return _handleExchangeIn(swapData, amountIn, amountOut);
        }
    }

    function _extractSwapAmounts(int256 swapDelta, bool zeroForOne)
        internal
        pure
        returns (uint256 amountIn, uint256 amountOut)
    {
        int128 amount0Delta = BalanceDeltaLibrary.amount0(swapDelta);
        int128 amount1Delta = BalanceDeltaLibrary.amount1(swapDelta);

        // Negative delta = we pay (input), Positive delta = we receive (output)
        int128 amountInDelta = zeroForOne ? amount0Delta : amount1Delta;
        int128 amountOutDelta = zeroForOne ? amount1Delta : amount0Delta;

        require(amountInDelta < 0, InsufficientInputAmount());
        require(amountOutDelta > 0, InvalidOutputAmount());

        amountIn = uint256(uint128(-amountInDelta));
        amountOut = uint256(uint128(amountOutDelta));
    }

    function _handleExchangeOut(SwapData memory swapData, uint256 amountIn, uint256 amountOut)
        internal
        returns (bytes memory)
    {
        require(amountOut == swapData.amountOut, InvalidOutputAmount());

        _transferOutput(swapData.assetOut, swapData.recipient, swapData.amountOut);
        _settleInput(swapData.assetIn, amountIn);

        return abi.encode(amountIn);
    }

    function _handleExchangeIn(SwapData memory swapData, uint256 amountIn, uint256 amountOut)
        internal
        returns (bytes memory)
    {
        require(amountIn <= swapData.amountIn, InsufficientInputAmount());
        require(amountOut >= swapData.minAmountOut, SlippageExceeded());

        _transferOutput(swapData.assetOut, swapData.recipient, amountOut);
        _settleInput(swapData.assetIn, amountIn);

        return abi.encode(amountOut);
    }

    function _transferOutput(address currency, address recipient, uint256 amount) internal {
        POOL_MANAGER.take(currency, address(this), amount);

        if (currency == address(0)) {
            (bool success,) = recipient.call{value: amount}("");
            require(success, EthTransferFailed());
        } else {
            IERC20(currency).safeTransfer(recipient, amount);
        }
    }

    function _settleInput(address currency, uint256 amount) internal {
        if (currency == address(0)) {
            POOL_MANAGER.settle{value: amount}();
        } else {
            SafeERC20.forceApprove(IERC20(currency), address(POOL_MANAGER), amount);
            POOL_MANAGER.settle();
        }
    }

    function _validateTokenPair(address assetIn, address assetOut) internal view {
        require(
            (assetIn == CURRENCY_0 && assetOut == CURRENCY_1)
                || (assetIn == CURRENCY_1 && assetOut == CURRENCY_0),
            InvalidTokenPair()
        );
    }

    function _getPoolKey() internal view returns (PoolKey memory) {
        return
            PoolKey({currency0: CURRENCY_0, currency1: CURRENCY_1, fee: FEE, tickSpacing: TICK_SPACING, hooks: HOOKS});
    }

    receive() external payable {}
}
