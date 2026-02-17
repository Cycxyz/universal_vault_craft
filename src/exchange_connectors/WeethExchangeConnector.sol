// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.28;

import {IExchangeConnector} from "../interface/IExchangeConnector.sol";
import {IWETH} from "../interface/IWETH.sol";
import {IWeETH} from "../interface/IWeETH.sol";
import {IEETH} from "../interface/IEETH.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";

contract WeethExchangeConnector is IExchangeConnector {
    using SafeERC20 for IERC20;

    // ether.fi WEETH (Wrapped eETH) contract address on Ethereum mainnet
    address public constant WEETH = 0xCd5fE23C85820F7B72D0926FC9b05b43E359b7ee;
    // ether.fi eETH contract address on Ethereum mainnet
    address public constant EETH = 0x35fA164735182de50811E8e2E824cFb9B6118ac2;
    // ether.fi LiquidityPool contract address on Ethereum mainnet (used for deposits)
    address public constant LIQUIDITY_POOL = 0x308861A430be4cce5502d0A12724771Fc6DaF216;

    IWETH public immutable weth;
    IWeETH public constant weeth = IWeETH(WEETH);
    IEETH public constant eeth = IEETH(EETH);
    IEETH public constant liquidityPool = IEETH(LIQUIDITY_POOL);

    error InvalidTokenPair();
    error InvalidWethAddress();
    error SlippageExceeded();
    error EthTransferFailed();

    constructor(address _weth) {
        require(_weth != address(0), InvalidWethAddress());
        weth = IWETH(_weth);
    }

    receive() external payable {}

    function _requireValidPair(address assetIn, address assetOut) internal view {
        bool isValidPair = (assetIn == address(weth) && assetOut == WEETH)
            || (assetIn == WEETH && assetOut == address(weth));
        require(isValidPair, InvalidTokenPair());
    }

    function exchangeIn(address assetIn, address assetOut, uint256 amountIn, uint256 minAmountOut)
        external
        payable
        override
        returns (uint256 amountOut)
    {
        _requireValidPair(assetIn, assetOut);

        if (assetIn == address(weth)) {
            // WETH -> WEETH: WETH -> ETH -> eETH -> WEETH
            IERC20(address(weth)).safeTransferFrom(msg.sender, address(this), amountIn);
            
            // Step 1: Withdraw WETH to native ETH
            weth.withdraw(amountIn);
            
            // Step 2: Deposit native ETH to eETH via LiquidityPool
            uint256 eethBalanceBefore = IERC20(EETH).balanceOf(address(this));
            liquidityPool.deposit{value: amountIn}();
            uint256 eethBalanceAfter = IERC20(EETH).balanceOf(address(this));
            uint256 eethReceived = eethBalanceAfter - eethBalanceBefore;
            
            // Step 3: Wrap eETH to WEETH (exchange rate is NOT 1:1)
            SafeERC20.forceApprove(IERC20(EETH), WEETH, eethReceived);
            amountOut = weeth.wrap(eethReceived);
            
            require(amountOut >= minAmountOut, SlippageExceeded());
            IERC20(WEETH).safeTransfer(msg.sender, amountOut);
        } else {
            // WEETH -> WETH: WEETH -> eETH -> ETH -> WETH
            IERC20(WEETH).safeTransferFrom(msg.sender, address(this), amountIn);
            
            // Step 1: Unwrap WEETH to eETH (exchange rate is NOT 1:1)
            uint256 eethReceived = weeth.unwrap(amountIn);
            
            // Step 2: Withdraw eETH to native ETH
            eeth.withdraw(eethReceived);
            
            // Step 3: Deposit native ETH to WETH
            weth.deposit{value: eethReceived}();
            amountOut = eethReceived; // eETH withdrawal returns ETH 1:1
            
            require(amountOut >= minAmountOut, SlippageExceeded());
            IERC20(address(weth)).safeTransfer(msg.sender, amountOut);
        }
    }

    function exchangeOut(address assetIn, address assetOut, uint256 amountOut, uint256 maxAmountIn)
        external
        payable
        override
        returns (uint256 amountIn)
    {
        _requireValidPair(assetIn, assetOut);

        if (assetIn == address(weth)) {
            // WETH -> WEETH: Calculate required eETH, then WETH -> ETH -> eETH -> WEETH
            // First, calculate how much eETH is needed to get amountOut WEETH
            uint256 requiredEeth = weeth.getEETHByWeETH(amountOut);
            // Add buffer to account for rounding in deposit and wrap operations
            // We need slightly more eETH to ensure we get enough WEETH after rounding
            uint256 ethToDeposit = requiredEeth + (requiredEeth / 10000) + 1; // Add 0.01% buffer + 1 wei
            require(ethToDeposit <= maxAmountIn, SlippageExceeded());
            
            IERC20(address(weth)).safeTransferFrom(msg.sender, address(this), maxAmountIn);
            
            // Withdraw required WETH to native ETH
            weth.withdraw(ethToDeposit);
            
            // Deposit native ETH to eETH via LiquidityPool
            uint256 eethBalanceBefore = IERC20(EETH).balanceOf(address(this));
            liquidityPool.deposit{value: ethToDeposit}();
            uint256 eethBalanceAfter = IERC20(EETH).balanceOf(address(this));
            uint256 eethReceived = eethBalanceAfter - eethBalanceBefore;
            require(eethReceived >= requiredEeth, SlippageExceeded());
            
            // Wrap eETH to WEETH
            SafeERC20.forceApprove(IERC20(EETH), WEETH, eethReceived);
            uint256 weethReceived = weeth.wrap(eethReceived);
            require(weethReceived >= amountOut, SlippageExceeded());
            
            IERC20(WEETH).safeTransfer(msg.sender, amountOut);
            amountIn = ethToDeposit;
            
            // Handle excess WEETH if we got more than needed
            uint256 excessWeethFromWrap = weethReceived - amountOut;
            if (excessWeethFromWrap > 0) {
                IERC20(WEETH).safeTransfer(msg.sender, excessWeethFromWrap);
            }
            
            // Refund excess WETH
            uint256 excess = maxAmountIn - ethToDeposit;
            if (excess > 0) {
                IERC20(address(weth)).safeTransfer(msg.sender, excess);
            }
        } else {
            // WEETH -> WETH: Calculate required WEETH, then WEETH -> eETH -> ETH -> WETH
            // Since eETH -> ETH is 1:1, we need amountOut eETH
            // Calculate required WEETH with a small buffer to account for rounding
            uint256 requiredEeth = amountOut;
            uint256 requiredWeeth = weeth.getWeETHByeETH(requiredEeth);
            // Add 1 wei buffer to account for rounding errors
            requiredWeeth = requiredWeeth + 1;
            require(requiredWeeth <= maxAmountIn, SlippageExceeded());
            
            IERC20(WEETH).safeTransferFrom(msg.sender, address(this), maxAmountIn);
            
            // Unwrap required WEETH to eETH
            uint256 eethReceived = weeth.unwrap(requiredWeeth);
            require(eethReceived >= requiredEeth, SlippageExceeded());
            
            // Withdraw exact amountOut eETH to native ETH
            eeth.withdraw(amountOut);
            
            // Deposit native ETH to WETH
            weth.deposit{value: amountOut}();
            amountIn = requiredWeeth;
            
            IERC20(address(weth)).safeTransfer(msg.sender, amountOut);
            
            // Handle excess eETH if unwrap gave more than needed
            uint256 excessEeth = eethReceived - amountOut;
            if (excessEeth > 0) {
                // Wrap excess eETH back to WEETH and refund
                SafeERC20.forceApprove(IERC20(EETH), WEETH, excessEeth);
                uint256 excessWeethFromEeth = weeth.wrap(excessEeth);
                IERC20(WEETH).safeTransfer(msg.sender, excessWeethFromEeth);
                // Adjust amountIn to account for refunded excess
                amountIn = amountIn - excessWeethFromEeth;
            }
            
            // Refund excess WEETH that wasn't used
            uint256 excessWeeth = maxAmountIn - requiredWeeth;
            if (excessWeeth > 0) {
                IERC20(WEETH).safeTransfer(msg.sender, excessWeeth);
            }
        }
    }
}
