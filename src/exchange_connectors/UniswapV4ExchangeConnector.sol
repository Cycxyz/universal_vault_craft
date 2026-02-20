//SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.28;

import {CommonExchangeConnector} from "./CommonExchangeConnector.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import {IPoolManager} from "../interface/IPoolManager.sol";
import {IPositionManager} from "../interface/IPositionManager.sol";
import {BalanceDeltaLibrary} from "../libraries/BalanceDeltaLibrary.sol";

contract UniswapV4ExchangeConnector is CommonExchangeConnector {
    using SafeERC20 for IERC20;

    IPoolManager public immutable POOL_MANAGER;
    address public immutable CURRENCY_0;
    address public immutable CURRENCY_1;
    uint24 public immutable FEE;
    int24 public immutable TICK_SPACING;
    address public immutable HOOKS;

    uint160 internal constant MIN_SQRT_RATIO = 4295128739;
    uint160 internal constant MAX_SQRT_RATIO = 1461446703485210103287273052203988822378723970342;

    error InvalidPool();
    error InvalidPositionManager();
    error InvalidTokenPair();
    error InvalidCaller();
    error InsufficientInputAmount();
    error InvalidOutputAmount();

    constructor(address _poolManager, address _positionManager, bytes25 _poolId) {
        require(_poolManager != address(0), InvalidPool());
        require(_positionManager != address(0), InvalidPositionManager());
        IPoolManager.PoolKey memory poolKey = IPositionManager(_positionManager).poolKeys(_poolId);
        require(poolKey.currency0 < poolKey.currency1, InvalidTokenPair());

        POOL_MANAGER = IPoolManager(_poolManager);
        CURRENCY_0 = poolKey.currency0;
        CURRENCY_1 = poolKey.currency1;
        FEE = poolKey.fee;
        TICK_SPACING = poolKey.tickSpacing;
        HOOKS = poolKey.hooks;
    }

    function unlockCallback(bytes calldata data) external returns (bytes memory) {
        require(msg.sender == address(POOL_MANAGER), InvalidCaller());
        IPoolManager.SwapParams memory params = abi.decode(data, (IPoolManager.SwapParams));

        int256 swapDelta = POOL_MANAGER.swap(_getPoolKey(), params, "");
        (uint256 amountIn, uint256 amountOut) = _extractSwapAmounts(swapDelta, params.zeroForOne);
        address inCurrency = params.zeroForOne ? CURRENCY_0 : CURRENCY_1;
        address outCurrency = params.zeroForOne ? CURRENCY_1 : CURRENCY_0;

        POOL_MANAGER.take(outCurrency, address(this), amountOut);
        if (inCurrency == address(0)) {
            POOL_MANAGER.settle{value: amountIn}();
        } else {
            IERC20(inCurrency).safeTransfer(address(POOL_MANAGER), amountIn);
            POOL_MANAGER.settle();
        }

        if (params.amountSpecified < 0) {
            return abi.encode(amountOut);
        } else {
            return abi.encode(amountIn);
        }
    }

    function _swapIn(address swapAssetIn, address swapAssetOut, uint256 amountIn)
        internal
        override
        returns (uint256 amountOut)
    {
        _requireValidPair(swapAssetIn, swapAssetOut);

        POOL_MANAGER.sync(swapAssetIn);

        bool zeroForOne = swapAssetIn == CURRENCY_0;
        IPoolManager.SwapParams memory params = IPoolManager.SwapParams({
            zeroForOne: zeroForOne,
            amountSpecified: -int256(amountIn),
            sqrtPriceLimitX96: zeroForOne ? MIN_SQRT_RATIO + 1 : MAX_SQRT_RATIO - 1
        });

        bytes memory unlockData = abi.encode(params);
        bytes memory unlockResult = POOL_MANAGER.unlock(unlockData);
        amountOut = abi.decode(unlockResult, (uint256));
    }

    function _swapOut(address swapAssetIn, address swapAssetOut, uint256 maxAmountIn, uint256 amountOut)
        internal
        override
        returns (uint256 amountIn)
    {
        _requireValidPair(swapAssetIn, swapAssetOut);

        POOL_MANAGER.sync(swapAssetIn);

        bool zeroForOne = swapAssetIn == CURRENCY_0;
        IPoolManager.SwapParams memory params = IPoolManager.SwapParams({
            zeroForOne: zeroForOne,
            amountSpecified: int256(amountOut),
            sqrtPriceLimitX96: zeroForOne ? MIN_SQRT_RATIO + 1 : MAX_SQRT_RATIO - 1
        });

        bytes memory unlockData = abi.encode(params);
        bytes memory unlockResult = POOL_MANAGER.unlock(unlockData);

        amountIn = abi.decode(unlockResult, (uint256));
        require(amountIn <= maxAmountIn, SlippageExceeded());
    }

    function _requireValidPair(address assetIn, address assetOut) internal view {
        require(
            assetIn == CURRENCY_0 && assetOut == CURRENCY_1 || assetIn == CURRENCY_1 && assetOut == CURRENCY_0,
            InvalidTokenPair()
        );
    }

    function _getPoolKey() internal view returns (IPoolManager.PoolKey memory) {
        return IPoolManager.PoolKey({
            currency0: CURRENCY_0,
            currency1: CURRENCY_1,
            fee: FEE,
            tickSpacing: TICK_SPACING,
            hooks: HOOKS
        });
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
}
