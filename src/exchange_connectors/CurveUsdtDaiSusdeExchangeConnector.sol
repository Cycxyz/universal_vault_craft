// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.28;

import {IExchangeConnector} from "../interface/IExchangeConnector.sol";
import {ICurvePoolDeprecated} from "../interface/ICurvePoolDeprecated.sol";
import {IUSDSMigration} from "../interface/IUSDS.sol";
import {IsUSDS} from "../interface/IsUSDS.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";

contract CurveUsdtDaiSusdeExchangeConnector is IExchangeConnector {
    using SafeERC20 for IERC20;

    // Hardcoded addresses on Ethereum mainnet
    address public constant USDT = 0xdAC17F958D2ee523a2206206994597C13D831ec7;
    address public constant DAI = 0x6B175474E89094C44Da98b954EedeAC495271d0F;
    address public immutable USDS;
    address public immutable SUSDS;

    // Hardcoded Curve 3pool address (DAI/USDC/USDT)
    // Pool: 0xbEbc44782C7dB0a1A60Cb6fe97d0b483032FF1C7
    // Indices: DAI=0, USDC=1, USDT=2
    ICurvePoolDeprecated public constant USDT_DAI_POOL =
        ICurvePoolDeprecated(0xbEbc44782C7dB0a1A60Cb6fe97d0b483032FF1C7);
    int128 public constant DAI_INDEX = 0;
    int128 public constant USDT_INDEX = 2;

    // Migration contract for upgrading DAI to USDS
    IUSDSMigration public immutable usdsMigration;
    // sUSDS contract for wrapping USDS
    IsUSDS public immutable susds;

    error InvalidTokenPair();
    error SlippageExceeded();
    error InvalidPool();

    constructor(address _usds, address _susds, address _usdsMigration) {
        require(_usds != address(0), InvalidPool());
        require(_susds != address(0), InvalidPool());
        require(_usdsMigration != address(0), InvalidPool());
        USDS = _usds;
        SUSDS = _susds;
        usdsMigration = IUSDSMigration(_usdsMigration);
        susds = IsUSDS(_susds);
    }

    receive() external payable {}

    function _requireValidPair(address assetIn, address assetOut) internal view {
        bool validPair = (assetIn == USDT && assetOut == SUSDS) || (assetIn == SUSDS && assetOut == USDT);
        require(validPair, InvalidTokenPair());
    }

    function _exchangeUsdtToSusdsIn(uint256 amountIn, uint256 minAmountOut) internal returns (uint256 amountOut) {
        // Transfer USDT from sender
        IERC20(USDT).safeTransferFrom(msg.sender, address(this), amountIn);

        // Step 1: Swap USDT -> DAI on Curve 3pool
        SafeERC20.forceApprove(IERC20(USDT), address(USDT_DAI_POOL), amountIn);
        uint256 daiBalanceBefore = IERC20(DAI).balanceOf(address(this));

        USDT_DAI_POOL.exchange(USDT_INDEX, DAI_INDEX, amountIn, uint256(0));

        uint256 daiBalanceAfter = IERC20(DAI).balanceOf(address(this));
        require(daiBalanceAfter > daiBalanceBefore, "No DAI received from swap");
        uint256 daiReceived = daiBalanceAfter - daiBalanceBefore;

        // Step 2: Upgrade DAI to USDS via migration contract
        SafeERC20.forceApprove(IERC20(DAI), address(usdsMigration), daiReceived);
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
        // Transfer USDT from sender
        IERC20(USDT).safeTransferFrom(msg.sender, address(this), maxAmountIn);

        // Step 1: Swap USDT -> DAI on Curve 3pool
        SafeERC20.forceApprove(IERC20(USDT), address(USDT_DAI_POOL), maxAmountIn);
        uint256 daiBalanceBefore = IERC20(DAI).balanceOf(address(this));
        USDT_DAI_POOL.exchange(USDT_INDEX, DAI_INDEX, maxAmountIn, uint256(0));
        uint256 daiBalanceAfter = IERC20(DAI).balanceOf(address(this));
        uint256 daiReceived = daiBalanceAfter - daiBalanceBefore;

        // Step 2: Upgrade DAI to USDS via migration contract
        SafeERC20.forceApprove(IERC20(DAI), address(usdsMigration), daiReceived);
        uint256 usdsBalanceBefore = IERC20(USDS).balanceOf(address(this));
        usdsMigration.migrateDAIToUSDS(address(this), daiReceived);
        uint256 usdsReceived = IERC20(USDS).balanceOf(address(this)) - usdsBalanceBefore;

        // Step 3: Deposit USDS to sUSDS vault
        SafeERC20.forceApprove(IERC20(USDS), SUSDS, usdsReceived);
        uint256 susdsReceived = susds.deposit(usdsReceived, address(this));
        require(susdsReceived >= amountOut, SlippageExceeded());

        IERC20(SUSDS).safeTransfer(msg.sender, amountOut);

        // Handle excess sUSDS
        if (susdsReceived > amountOut) {
            uint256 excessSusds = susdsReceived - amountOut;
            // Redeem excess sUSDS back to USDS
            uint256 excessUsds = susds.redeem(excessSusds, address(this), address(this));
            // Downgrade excess USDS back to DAI via migration contract
            SafeERC20.forceApprove(IERC20(USDS), address(usdsMigration), excessUsds);
            uint256 daiBalanceBeforeExcess = IERC20(DAI).balanceOf(address(this));
            usdsMigration.downgradeUSDSToDAI(address(this), excessUsds);
            uint256 excessDai = IERC20(DAI).balanceOf(address(this)) - daiBalanceBeforeExcess;
            // Swap excess DAI back to USDT
            SafeERC20.forceApprove(IERC20(DAI), address(USDT_DAI_POOL), excessDai);
            daiBalanceBefore = IERC20(USDT).balanceOf(address(this));
            USDT_DAI_POOL.exchange(DAI_INDEX, USDT_INDEX, excessDai, uint256(0));
            uint256 excessUsdt = IERC20(USDT).balanceOf(address(this)) - daiBalanceBefore;
            amountIn = maxAmountIn - excessUsdt;
            IERC20(USDT).safeTransfer(msg.sender, excessUsdt);
        } else {
            amountIn = maxAmountIn;
        }
    }

    function _exchangeSusdsToUsdtIn(uint256 amountIn, uint256 minAmountOut) internal returns (uint256 amountOut) {
        // Transfer sUSDS from sender
        IERC20(SUSDS).safeTransferFrom(msg.sender, address(this), amountIn);

        // Step 1: Redeem sUSDS to USDS
        uint256 usdsReceived = susds.redeem(amountIn, address(this), address(this));

        // Step 2: Downgrade USDS to DAI via migration contract
        SafeERC20.forceApprove(IERC20(USDS), address(usdsMigration), usdsReceived);
        uint256 daiBalanceBefore = IERC20(DAI).balanceOf(address(this));
        usdsMigration.downgradeUSDSToDAI(address(this), usdsReceived);
        uint256 daiReceived = IERC20(DAI).balanceOf(address(this)) - daiBalanceBefore;

        // Step 3: Swap DAI -> USDT on Curve 3pool
        SafeERC20.forceApprove(IERC20(DAI), address(USDT_DAI_POOL), daiReceived);
        uint256 usdtBalanceBefore = IERC20(USDT).balanceOf(address(this));
        USDT_DAI_POOL.exchange(DAI_INDEX, USDT_INDEX, daiReceived, minAmountOut);
        uint256 usdtBalanceAfter = IERC20(USDT).balanceOf(address(this));
        uint256 usdtReceived = usdtBalanceAfter - usdtBalanceBefore;
        require(usdtReceived >= minAmountOut, SlippageExceeded());

        IERC20(USDT).safeTransfer(msg.sender, usdtReceived);
        return usdtReceived;
    }

    function _exchangeSusdsToUsdtOut(uint256 amountOut, uint256 maxAmountIn) internal returns (uint256 amountIn) {
        // Transfer sUSDS from sender
        IERC20(SUSDS).safeTransferFrom(msg.sender, address(this), maxAmountIn);

        // Step 1: Redeem sUSDS to USDS
        uint256 usdsReceived = susds.redeem(maxAmountIn, address(this), address(this));

        // Step 2: Downgrade USDS to DAI via migration contract
        SafeERC20.forceApprove(IERC20(USDS), address(usdsMigration), usdsReceived);
        uint256 daiBalanceBefore = IERC20(DAI).balanceOf(address(this));
        usdsMigration.downgradeUSDSToDAI(address(this), usdsReceived);
        uint256 daiReceived = IERC20(DAI).balanceOf(address(this)) - daiBalanceBefore;

        // Step 3: Swap DAI -> USDT on Curve 3pool (exact output)
        SafeERC20.forceApprove(IERC20(DAI), address(USDT_DAI_POOL), daiReceived);
        uint256 usdtBalanceBefore = IERC20(USDT).balanceOf(address(this));
        USDT_DAI_POOL.exchange(DAI_INDEX, USDT_INDEX, daiReceived, amountOut);
        uint256 usdtBalanceAfter = IERC20(USDT).balanceOf(address(this));
        uint256 usdtReceived = usdtBalanceAfter - usdtBalanceBefore;
        require(usdtReceived >= amountOut, SlippageExceeded());

        IERC20(USDT).safeTransfer(msg.sender, amountOut);

        // Handle excess USDT
        uint256 excessUsdt = usdtReceived - amountOut;
        if (excessUsdt > 0) {
            // Swap excess USDT back to DAI
            SafeERC20.forceApprove(IERC20(USDT), address(USDT_DAI_POOL), excessUsdt);
            daiBalanceBefore = IERC20(DAI).balanceOf(address(this));
            USDT_DAI_POOL.exchange(USDT_INDEX, DAI_INDEX, excessUsdt, uint256(0));
            uint256 excessDai = IERC20(DAI).balanceOf(address(this)) - daiBalanceBefore;
            // Upgrade excess DAI back to USDS via migration contract
            SafeERC20.forceApprove(IERC20(DAI), address(usdsMigration), excessDai);
            uint256 usdsBalanceBefore = IERC20(USDS).balanceOf(address(this));
            usdsMigration.migrateDAIToUSDS(address(this), excessDai);
            uint256 excessUsds = IERC20(USDS).balanceOf(address(this)) - usdsBalanceBefore;
            // Deposit excess USDS back to sUSDS vault
            SafeERC20.forceApprove(IERC20(USDS), SUSDS, excessUsds);
            uint256 excessSusds = susds.deposit(excessUsds, address(this));
            amountIn = maxAmountIn - excessSusds;
            IERC20(SUSDS).safeTransfer(msg.sender, excessSusds);
        } else {
            amountIn = maxAmountIn;
        }
    }

    function exchangeIn(address assetIn, address assetOut, uint256 amountIn, uint256 minAmountOut)
        external
        payable
        override
        returns (uint256 amountOut)
    {
        _requireValidPair(assetIn, assetOut);

        if (assetIn == USDT && assetOut == SUSDS) {
            return _exchangeUsdtToSusdsIn(amountIn, minAmountOut);
        } else if (assetIn == SUSDS && assetOut == USDT) {
            return _exchangeSusdsToUsdtIn(amountIn, minAmountOut);
        }

        revert InvalidTokenPair();
    }

    function exchangeOut(address assetIn, address assetOut, uint256 amountOut, uint256 maxAmountIn)
        external
        payable
        override
        returns (uint256 amountIn)
    {
        _requireValidPair(assetIn, assetOut);

        if (assetIn == USDT && assetOut == SUSDS) {
            return _exchangeUsdtToSusdsOut(amountOut, maxAmountIn);
        } else if (assetIn == SUSDS && assetOut == USDT) {
            return _exchangeSusdsToUsdtOut(amountOut, maxAmountIn);
        }

        revert InvalidTokenPair();
    }
}
