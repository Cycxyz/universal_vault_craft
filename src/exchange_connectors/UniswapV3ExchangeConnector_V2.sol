// // SPDX-License-Identifier: BUSL-1.1
// pragma solidity ^0.8.28;

// import {IExchangeConnector} from "../interface/IExchangeConnector.sol";
// import {IUSDSMigration} from "../interface/IUSDS.sol";
// import {IsUSDS} from "../interface/IsUSDS.sol";
// import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
// import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
// import {IExchangeWrapper} from "../interface/IExchangeWrapper.sol";

// interface IUniswapV3Pool {
//     function token0() external view returns (address);
//     function token1() external view returns (address);
//     function swap(
//         address recipient,
//         bool zeroForOne,
//         int256 amountSpecified,
//         uint160 sqrtPriceLimitX96,
//         bytes calldata data
//     ) external returns (int256 amount0, int256 amount1);
// }

// interface IUniswapV3SwapCallback {
//     function uniswapV3SwapCallback(int256 amount0Delta, int256 amount1Delta, bytes calldata data) external;
// }

// contract UniswapV3UsdtDaiSusdsExchangeConnector is IUniswapV3SwapCallback {
//     using SafeERC20 for IERC20;

//     // Hardcoded addresses on Ethereum mainnet
//     IUniswapV3Pool public immutable pool;
//     uint160 internal constant MIN_SQRT_RATIO = 4295128739;
//     uint160 internal constant MAX_SQRT_RATIO = 1461446703485210103287273052203988822378723970342;

//     IsUSDS public immutable susds;

//     error ZeroPool();
//     error InvalidTokenPair();
//     error InsufficientInputAmount();
//     error InvalidOutputAmount();
//     error SlippageExceeded();
//     error InvalidCaller();
//     error InvalidSwapCallback();
//     error InvalidToken();
//     error WrappingOperationFailed(address wrapper, address assetIn, address assetOut, uint256 amountIn);
//     error InvalidPool(address pool, int256 amount0Delta, int256 amount1Delta);
//     error WrappingOperationMismatch(
//         address wrapper,
//         address assetIn,
//         address assetOut,
//         uint256 amountIn,
//         uint256 amountOut,
//         uint256 expectedAmountOut
//     );

//     constructor(address _pool) {
//         require(_pool != address(0), ZeroPool());
//         pool = IUniswapV3Pool(_pool);
//     }

//     receive() external payable {}

//     modifier onlyValidPair(address assetIn, address assetOut) {
//         require(
//             assetIn == pool.token0() && assetOut == pool.token1()
//                 || assetIn == pool.token1() && assetOut == pool.token0(),
//             InvalidTokenPair()
//         );
//         _;
//     }

//     function exchangeIn(
//         address assetIn,
//         address poolAssetIn,
//         address assetOut,
//         address poolAssetOut,
//         uint256 amountIn,
//         uint256 minAmountOut,
//         address preExchangeWrapper,
//         address postExchangeWrapper
//     ) external payable onlyValidPair(poolAssetIn, poolAssetOut) returns (uint256 amountOut) {
//         IERC20(assetIn).safeTransferFrom(msg.sender, address(this), amountIn);
//         if (preExchangeWrapper != address(0)) {
//             amountIn = _executeWrappingOperation(preExchangeWrapper, assetIn, poolAssetIn, amountIn);
//         }

//         bool zeroForOne = poolAssetIn == pool.token0();
//         IERC20(poolAssetIn).forceApprove(address(pool), amountIn);
//         (int256 amount0Delta, int256 amount1Delta) = pool.swap(
//             msg.sender, zeroForOne, int256(amountIn), zeroForOne ? MIN_SQRT_RATIO + 1 : MAX_SQRT_RATIO - 1, ""
//         );

//         if (zeroForOne && amount1Delta < 0) {
//             amountOut = uint256(-amount1Delta);
//         } else if (!zeroForOne && amount0Delta < 0) {
//             amountOut = uint256(-amount0Delta);
//         } else {
//             revert InvalidSwapCallback();
//         }
//         if (postExchangeWrapper != address(0)) {
//             amountOut = _executeWrappingOperation(postExchangeWrapper, poolAssetOut, assetOut, uint256(-amount0Delta));
//         }

//         require(amountOut >= minAmountOut, SlippageExceeded());
//         IERC20(assetOut).safeTransfer(msg.sender, amountOut);
//     }

//     function exchangeOut(
//         address assetIn,
//         address poolAssetIn,
//         address assetOut,
//         address poolAssetOut,
//         uint256 amountOut,
//         uint256 maxAmountIn,
//         address preExchangeWrapper,
//         address postExchangeWrapper
//     ) external payable onlyValidPair(poolAssetIn, poolAssetOut) returns (uint256 amountIn) {
//         IERC20(assetIn).safeTransferFrom(msg.sender, address(this), maxAmountIn);
//         uint256 maxAmountInPool = maxAmountIn;
//         if (preExchangeWrapper != address(0)) {
//             maxAmountInPool = _executeWrappingOperation(preExchangeWrapper, assetIn, poolAssetIn, maxAmountIn);
//         }

//         uint256 poolAmountOut = amountOut;
//         if (postExchangeWrapper != address(0)) {
//             poolAmountOut =
//                 IExchangeWrapper(postExchangeWrapper).previewWrappingOperation(poolAssetOut, assetOut, amountOut);
//         }

//         bool zeroForOne = poolAssetIn == pool.token0();
//         IERC20(poolAssetIn).forceApprove(address(pool), maxAmountInPool);
//         (int256 amount0Delta, int256 amount1Delta) = pool.swap(
//             msg.sender, zeroForOne, -int256(poolAmountOut), zeroForOne ? MIN_SQRT_RATIO + 1 : MAX_SQRT_RATIO - 1, ""
//         );
//         IERC20(poolAssetIn).forceApprove(address(pool), 0);

//         uint256 poolAmountIn;
//         if (zeroForOne && amount1Delta > 0) {
//             poolAmountIn = uint256(amount1Delta);
//         } else if (!zeroForOne && amount0Delta > 0) {
//             poolAmountIn = uint256(amount0Delta);
//         } else {
//             revert InvalidSwapCallback();
//         }
        
//         // assume maxAmountInPool >= poolAmountIn since it wouldn't swap otherwise
//         uint256 refundAmount = maxAmountInPool - poolAmountIn;
//         if (refundAmount > 0) {
//             if (preExchangeWrapper != address(0)) {
//                 refundAmount = _executeWrappingOperation(preExchangeWrapper, poolAssetIn, assetIn, refundAmount);
//             }
//             IERC20(assetIn).safeTransfer(msg.sender, refundAmount);
//         }

//         if (postExchangeWrapper != address(0)) {
//             uint256 realAmountOut =
//                 _executeWrappingOperation(postExchangeWrapper, poolAssetOut, assetOut, poolAmountOut);
//             require(
//                 realAmountOut == amountOut,
//                 WrappingOperationMismatch(
//                     postExchangeWrapper, poolAssetOut, assetOut, poolAmountOut, realAmountOut, amountOut
//                 )
//             );
//         }

//         IERC20(assetOut).safeTransfer(msg.sender, amountOut);
//         amountIn = maxAmountIn - refundAmount;
//     }


//     function uniswapV3SwapCallback(int256 amount0Delta, int256 amount1Delta, bytes calldata) external override {
//         require(msg.sender == address(pool), InvalidCaller());

//         if (amount0Delta > 0) {
//             IERC20(pool.token0()).safeTransfer(address(pool), uint256(-amount0Delta));
//         } else if (amount1Delta > 0) {
//             IERC20(pool.token1()).safeTransfer(address(pool), uint256(-amount1Delta));
//         } else {
//             revert InvalidSwapCallback();
//         }
//     }

//     function _executeWrappingOperation(address wrapper, address assetIn, address assetOut, uint256 amountIn)
//         internal
//         returns (uint256 amountOut)
//     {
//         (bool success, bytes memory data) = wrapper.delegatecall(
//             abi.encodeCall(IExchangeWrapper.executeWrappingOperation, (assetIn, assetOut, amountIn))
//         );
//         require(success, WrappingOperationFailed(wrapper, assetIn, assetOut, amountIn));
//         return abi.decode(data, (uint256));
//     }
// }
