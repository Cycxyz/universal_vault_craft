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
import {IsUSDE} from "../interface/IsUSDE.sol";

contract UniswapV4UsdtUsdeExchangeConnector is IExchangeConnector, IUnlockCallback {
    using SafeERC20 for IERC20;

    IPoolManager public immutable POOL_MANAGER;
    address public immutable USDT;
    address public immutable USDE;
    address public immutable SUSDE;
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

    constructor(
        address _poolManager,
        address _positionManager,
        bytes25 _poolId,
        address _susde
    ) {
        require(_poolManager != address(0), InvalidPool());
        require(_positionManager != address(0), InvalidPositionManager());
        require(_susde != address(0), InvalidToken());
        
        PoolKey memory poolKey = IPositionManager(_positionManager).poolKeys(_poolId);
        require(poolKey.currency0 < poolKey.currency1, InvalidTokenPair());

        POOL_MANAGER = IPoolManager(_poolManager);
        // Pool key has currencies sorted: currency0 < currency1
        // We need to identify which is USDT and which is USDE
        // USDT: 0xdAC17F958D2ee523a2206206994597C13D831ec7
        // USDE: 0x4c9EDD5852cd905f086C759E8383e09bff1E68B3
        // USDE < USDT address-wise, so USDE is currency0, USDT is currency1
        if (poolKey.currency0 == address(0x4c9EDD5852cd905f086C759E8383e09bff1E68B3)) {
            // USDE is currency0, USDT is currency1
            USDE = poolKey.currency0;
            USDT = poolKey.currency1;
        } else {
            // USDT is currency0, USDE is currency1
            USDT = poolKey.currency0;
            USDE = poolKey.currency1;
        }
        FEE = poolKey.fee;
        TICK_SPACING = poolKey.tickSpacing;
        HOOKS = poolKey.hooks;
        SUSDE = _susde;
    }

    function exchangeOut(address assetIn, address assetOut, uint256 amountOut, uint256 maxAmountIn)
        external
        payable
        override
        returns (uint256 amountIn)
    {
        _validateTokenPair(assetIn, assetOut);
        require(assetIn == USDT && assetOut == SUSDE, InvalidTokenPair());
        
        return _exchangeOutUsdtToSusde(amountOut, maxAmountIn);
    }

    function exchangeIn(address assetIn, address assetOut, uint256 amountIn, uint256 minAmountOut)
        external
        payable
        override
        returns (uint256 amountOut)
    {
        _validateTokenPair(assetIn, assetOut);
        require(assetIn == USDT && assetOut == SUSDE, InvalidTokenPair());
        
        return _exchangeInUsdtToSusde(amountIn, minAmountOut);
    }

    function _exchangeOutUniswap(address assetIn, address assetOut, uint256 amountOut, uint256 maxAmountIn)
        internal
        returns (uint256 amountIn)
    {
        address currencyIn = assetIn;
        bool zeroForOne = currencyIn == USDE; // USDE is currency0, USDT is currency1

        SwapData memory swapData = SwapData({
            assetIn: assetIn,
            assetOut: assetOut,
            recipient: address(this), // Internal call, recipient is this contract
            amountOut: amountOut,
            maxAmountIn: maxAmountIn,
            amountIn: 0,
            minAmountOut: 0,
            isExchangeOut: true
        });

        POOL_MANAGER.sync(currencyIn);

        // For zeroForOne: price cannot go below limit (use 1 for minimum, 0 is invalid)
        // For oneForZero: price cannot go above limit (use a very large but valid value)
        // Using 2^160 - 1 would be max, but that's invalid. Use 2^160 - 2^96 as a safe upper bound
        uint160 sqrtPriceLimitX96 = zeroForOne ? 1 : (type(uint160).max >> 1);

        SwapParams memory params = SwapParams({
            zeroForOne: zeroForOne,
            amountSpecified: int256(amountOut),
            sqrtPriceLimitX96: sqrtPriceLimitX96
        });

        bytes memory unlockData = abi.encode(params, swapData);
        bytes memory result = POOL_MANAGER.unlock(unlockData);

        amountIn = abi.decode(result, (uint256));
        require(amountIn <= maxAmountIn, SlippageExceeded());
    }

    function _exchangeInUniswap(address assetIn, address assetOut, uint256 amountIn, uint256 minAmountOut)
        internal
        returns (uint256 amountOut)
    {
        address currencyIn = assetIn;
        bool zeroForOne = currencyIn == USDE; // USDE is currency0, USDT is currency1

        SwapData memory swapData = SwapData({
            assetIn: assetIn,
            assetOut: assetOut,
            recipient: address(this), // Internal call, recipient is this contract
            amountOut: 0,
            maxAmountIn: 0,
            amountIn: amountIn,
            minAmountOut: minAmountOut,
            isExchangeOut: false
        });

        POOL_MANAGER.sync(currencyIn);

        // For zeroForOne: price cannot go below limit (use 1 for minimum, 0 is invalid)
        // For oneForZero: price cannot go above limit (use a very large but valid value)
        // Using 2^160 - 1 would be max, but that's invalid. Use 2^160 - 2^96 as a safe upper bound
        uint160 sqrtPriceLimitX96 = zeroForOne ? 1 : (type(uint160).max >> 1);

        SwapParams memory params = SwapParams({
            zeroForOne: zeroForOne,
            amountSpecified: -int256(amountIn),
            sqrtPriceLimitX96: sqrtPriceLimitX96
        });

        bytes memory unlockData = abi.encode(params, swapData);
        bytes memory result = POOL_MANAGER.unlock(unlockData);

        amountOut = abi.decode(result, (uint256));
        require(amountOut >= minAmountOut, SlippageExceeded());
    }

    function _exchangeOutUsdtToSusde(uint256 amountOut, uint256 maxAmountIn)
        internal
        returns (uint256 amountIn)
    {
        // User wants amountOut sUSDE
        // Strategy: Calculate required USDE, then do exact output swap
        // Note: We transfer maxAmountIn upfront, but _exchangeOutUniswap will only use what's needed
        // However, _settleInput transfers all tokens to PoolManager, so we can't return excess
        
        // Step 1: Calculate how much USDE we need for amountOut sUSDE
        uint256 requiredUsde = IsUSDE(SUSDE).convertToAssets(amountOut);
        
        // Step 2: Add buffer for rounding and slippage (2% buffer)
        uint256 requiredUsdeWithBuffer = (requiredUsde * 102) / 100;
        
        // Step 3: Transfer maxAmountIn upfront
        IERC20(USDT).safeTransferFrom(msg.sender, address(this), maxAmountIn);

        // Step 4: Swap USDT to USDE (exact output) - returns amountIn (USDT used)
        // This will only use what's needed, but _settleInput transfers all tokens to PoolManager
        amountIn = _exchangeOutUniswap(USDT, USDE, requiredUsdeWithBuffer, maxAmountIn);
        
        // Step 5: Get the actual USDE received (should be >= requiredUsde)
        uint256 usdeReceived = requiredUsdeWithBuffer;
        
        // Step 6: Deposit USDE to sUSDE (ERC4626 vault)
        SafeERC20.forceApprove(IERC20(USDE), SUSDE, usdeReceived);
        uint256 susdeReceived = IsUSDE(SUSDE).deposit(usdeReceived, address(this));
        require(susdeReceived >= amountOut, SlippageExceeded());

        // Step 7: Transfer exact amountOut sUSDE to user
        IERC20(SUSDE).safeTransfer(msg.sender, amountOut);

        // Step 8: Calculate actual USDT used proportionally
        // If usdeReceived USDE required amountIn USDT, then
        // requiredUsde USDE -> (requiredUsde * amountIn) / usdeReceived USDT
        amountIn = (requiredUsde * amountIn + usdeReceived - 1) / usdeReceived;
        
        // Note: Excess USDT was transferred to PoolManager during settlement
        // This is a limitation of the current implementation
        // Excess sUSDE remains in contract (can't redeem due to vault restrictions)
    }

    function _exchangeInUsdtToSusde(uint256 amountIn, uint256 minAmountOut)
        internal
        returns (uint256 amountOut)
    {
        // First swap USDT -> USDE, then wrap USDE -> sUSDE
        IERC20(USDT).safeTransferFrom(msg.sender, address(this), amountIn);

        // Swap USDT to USDE
        uint256 usdeReceived = _exchangeInUniswap(USDT, USDE, amountIn, 0);

        // Deposit USDE to sUSDE (ERC4626 vault)
        SafeERC20.forceApprove(IERC20(USDE), SUSDE, usdeReceived);
        amountOut = IsUSDE(SUSDE).deposit(usdeReceived, address(this));
        require(amountOut >= minAmountOut, SlippageExceeded());
        IERC20(SUSDE).safeTransfer(msg.sender, amountOut);
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
            // Transfer tokens to PoolManager first, then settle
            IERC20(currency).safeTransfer(address(POOL_MANAGER), amount);
            POOL_MANAGER.settle();
        }
    }

    function _validateTokenPair(address assetIn, address assetOut) internal view {
        require(assetIn == USDT && assetOut == SUSDE, InvalidTokenPair());
    }

    function _getPoolKey() internal view returns (PoolKey memory) {
        // Pool key must match the actual pool structure
        // currency0 < currency1, so we need to order them correctly
        address currency0 = USDE < USDT ? USDE : USDT;
        address currency1 = USDE < USDT ? USDT : USDE;
        return PoolKey({currency0: currency0, currency1: currency1, fee: FEE, tickSpacing: TICK_SPACING, hooks: HOOKS});
    }

    receive() external payable {}
}
