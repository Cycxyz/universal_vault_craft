// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.28;

import {IExchangeConnector} from "../interface/IExchangeConnector.sol";
import {IUSDSMigration} from "../interface/IUSDS.sol";
import {IsUSDS} from "../interface/IsUSDS.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";

interface IUniswapV3Pool {
    function token0() external view returns (address);
    function token1() external view returns (address);
    function swap(
        address recipient,
        bool zeroForOne,
        int256 amountSpecified,
        uint160 sqrtPriceLimitX96,
        bytes calldata data
    ) external returns (int256 amount0, int256 amount1);
}

interface IUniswapV3SwapCallback {
    function uniswapV3SwapCallback(int256 amount0Delta, int256 amount1Delta, bytes calldata data) external;
}

contract UniswapV3UsdtDaiSusdsExchangeConnector is IExchangeConnector, IUniswapV3SwapCallback {
    using SafeERC20 for IERC20;

    // Hardcoded addresses on Ethereum mainnet
    address public constant USDT = 0xdAC17F958D2ee523a2206206994597C13D831ec7;
    address public constant DAI = 0x6B175474E89094C44Da98b954EedeAC495271d0F;
    IUniswapV3Pool public constant pool = IUniswapV3Pool(0x48DA0965ab2d2cbf1C17C09cFB5Cbe67Ad5B1406);
    address public immutable USDS;
    address public immutable SUSDS;
    IUSDSMigration public immutable usdsMigration;
    uint160 internal constant MIN_SQRT_RATIO = 4295128739;
    uint160 internal constant MAX_SQRT_RATIO = 1461446703485210103287273052203988822378723970342;

    IsUSDS public immutable susds;

    error InvalidPool();
    error InvalidTokenPair();
    error InsufficientInputAmount();
    error InvalidOutputAmount();
    error SlippageExceeded();
    error InvalidCaller();
    error InvalidSwapCallback();
    error InvalidToken();

    constructor(address _usds, address _susds, address _usdsMigration) {
        require(_usds != address(0), InvalidPool());
        require(_susds != address(0), InvalidPool());
        require(_usdsMigration != address(0), InvalidPool());

        USDS = _usds;
        SUSDS = _susds;
        usdsMigration = IUSDSMigration(_usdsMigration);
        susds = IsUSDS(_susds);

        // Verify pool token order: DAI is token0, USDT is token1
        require(pool.token0() == DAI && pool.token1() == USDT, InvalidPool());
    }

    receive() external payable {}

    function _requireValidPair(address assetIn, address assetOut) internal view {
        require(assetIn == USDT && assetOut == SUSDS, InvalidTokenPair());
    }

    function _swapUsdtToDaiIn(uint256 amountIn, uint256 minAmountOut) internal returns (uint256 amountOut) {
        IERC20(USDT).safeTransferFrom(msg.sender, address(this), amountIn);

        (int256 amount0Delta, int256 amount1Delta) =
            pool.swap(address(this), false, int256(amountIn), MAX_SQRT_RATIO - 1, "");

        uint256 actualAmountIn = uint256(amount1Delta);
        require(actualAmountIn <= amountIn, InsufficientInputAmount());
        amountOut = uint256(-amount0Delta);
        require(amountOut >= minAmountOut, SlippageExceeded());
    }

    function _swapUsdtToDaiOut(uint256 amountOut, uint256 maxAmountIn) internal returns (uint256 amountIn) {
        IERC20(USDT).safeTransferFrom(msg.sender, address(this), maxAmountIn);

        (int256 amount0Delta, int256 amount1Delta) =
            pool.swap(address(this), false, -int256(amountOut), MAX_SQRT_RATIO - 1, "");

        amountIn = uint256(amount1Delta);
        require(amountIn <= maxAmountIn, InsufficientInputAmount());
        require(uint256(-amount0Delta) == amountOut, InvalidOutputAmount());

        uint256 remaining = maxAmountIn - amountIn;
        if (remaining > 0) {
            IERC20(USDT).safeTransfer(msg.sender, remaining);
        }

        return amountIn;
    }

    function _exchangeUsdtToSusdsIn(uint256 amountIn, uint256 minAmountOut) internal returns (uint256 amountOut) {
        uint256 daiReceived = _swapUsdtToDaiIn(amountIn, 0);

        IERC20(DAI).forceApprove(address(usdsMigration), daiReceived);
        uint256 usdsBalanceBefore = IERC20(USDS).balanceOf(address(this));
        usdsMigration.migrateDAIToUSDS(address(this), daiReceived);
        uint256 usdsReceived = IERC20(USDS).balanceOf(address(this)) - usdsBalanceBefore;
        require(usdsReceived > 0, "Migration failed");

        // Step 3: Deposit USDS to sUSDS vault
        SafeERC20.forceApprove(IERC20(USDS), SUSDS, usdsReceived);
        uint256 susdsReceived = susds.deposit(usdsReceived, address(this));
        require(susdsReceived >= minAmountOut, SlippageExceeded());

        IERC20(SUSDS).safeTransfer(msg.sender, susdsReceived);
        return susdsReceived;
    }

    function _exchangeUsdtToSusdsOut(uint256 amountOut, uint256 maxAmountIn) internal returns (uint256 amountIn) {
        uint256 sUsdsSupply = susds.totalSupply();
        uint256 sUsdsAssets = susds.totalAssets();

        uint256 requiredUsds = (amountOut * sUsdsAssets + sUsdsSupply - 1) / sUsdsSupply;

        uint256 requiredDai = requiredUsds;
        uint256 usdtRequired = _swapUsdtToDaiOut(requiredDai, maxAmountIn);

        IERC20(DAI).forceApprove(address(usdsMigration), requiredDai);
        usdsMigration.migrateDAIToUSDS(address(this), requiredDai);
        IERC20(USDS).forceApprove(address(susds), requiredUsds);
        uint256 susdsReceived = susds.deposit(requiredUsds, address(this));
        require(susdsReceived >= amountOut, SlippageExceeded());
        IERC20(SUSDS).safeTransfer(msg.sender, amountOut);

        return usdtRequired;
    }

    function exchangeIn(address assetIn, address assetOut, uint256 amountIn, uint256 minAmountOut)
        external
        payable
        override
        returns (uint256 amountOut)
    {
        _requireValidPair(assetIn, assetOut);
        return _exchangeUsdtToSusdsIn(amountIn, minAmountOut);
    }

    function exchangeOut(address assetIn, address assetOut, uint256 amountOut, uint256 maxAmountIn)
        external
        payable
        override
        returns (uint256 amountIn)
    {
        _requireValidPair(assetIn, assetOut);
        return _exchangeUsdtToSusdsOut(amountOut, maxAmountIn);
    }

    function uniswapV3SwapCallback(int256, int256 amount1Delta, bytes calldata) external override {
        require(msg.sender == address(pool), InvalidCaller());

        require(amount1Delta > 0, InvalidSwapCallback());

        IERC20(USDT).safeTransfer(msg.sender, uint256(amount1Delta));
    }
}
