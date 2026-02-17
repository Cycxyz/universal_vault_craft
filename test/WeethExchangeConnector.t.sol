// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.28;

import {Test} from "forge-std/Test.sol";
import {WeethExchangeConnector} from "../src/exchange_connectors/WeethExchangeConnector.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";

contract WeethExchangeConnectorTest is Test {
    WeethExchangeConnector public connector;
    
    // Mainnet addresses
    address public constant WETH = 0xC02aaA39b223FE8D0A0e5C4F27eAD9083C756Cc2;
    address public constant WEETH = 0xCd5fE23C85820F7B72D0926FC9b05b43E359b7ee;
    
    uint256 public constant FORK_BLOCK = 24448072; // Recent block to ensure eETH is operational
    
    address public user = address(0x1337);
    uint256 public constant WETH_AMOUNT = 1 ether;

    function setUp() public {
        string memory rpcUrl = vm.envString("RPC_MAINNET");
        vm.createSelectFork(rpcUrl, FORK_BLOCK);

        connector = new WeethExchangeConnector(WETH);
        
        // Give user some WETH tokens
        deal(WETH, user, WETH_AMOUNT * 10);
    }

    function test_exchangeIn_WETH_to_WEETH_happyCase() public {
        uint256 amountIn = WETH_AMOUNT;
        uint256 minAmountOut = 0; // Accept any amount
        
        uint256 userWethBalanceBefore = IERC20(WETH).balanceOf(user);
        uint256 userWeethBalanceBefore = IERC20(WEETH).balanceOf(user);
        
        vm.startPrank(user);
        IERC20(WETH).approve(address(connector), amountIn);
        
        uint256 weethOut = connector.exchangeIn(WETH, WEETH, amountIn, minAmountOut);
        vm.stopPrank();
        
        uint256 userWethBalanceAfter = IERC20(WETH).balanceOf(user);
        uint256 userWeethBalanceAfter = IERC20(WEETH).balanceOf(user);
        uint256 connectorWethBalanceAfter = IERC20(WETH).balanceOf(address(connector));
        uint256 connectorWeethBalanceAfter = IERC20(WEETH).balanceOf(address(connector));
        
        // Verify WETH was spent
        assertEq(userWethBalanceBefore - userWethBalanceAfter, amountIn, "WETH should be spent");
        
        // Verify WEETH was received
        assertEq(userWeethBalanceAfter - userWeethBalanceBefore, weethOut, "WEETH balance should increase");
        assertGt(weethOut, 0, "Should receive WEETH");
        
        // Verify exchange rate is NOT 1:1 (WEETH amount should be less than WETH due to eETH staking rewards)
        assertLt(weethOut, amountIn, "WEETH amount should be less than WETH due to exchange rate");
        
        // Post-checks: ensure no tokens left in connector
        assertEq(connectorWethBalanceAfter, 0, "No WETH should remain in connector");
        assertEq(connectorWeethBalanceAfter, 0, "No WEETH should remain in connector");
    }

    function test_exchangeOut_WETH_to_WEETH_happyCase() public {
        // Test exchangeOut: WETH -> WEETH (exact output)
        uint256 amountOut = WETH_AMOUNT / 2; // Want 0.5 ETH worth of WEETH
        uint256 maxAmountIn = WETH_AMOUNT; // Willing to spend up to 1 WETH
        
        uint256 userWethBalanceBefore = IERC20(WETH).balanceOf(user);
        uint256 userWeethBalanceBefore = IERC20(WEETH).balanceOf(user);
        
        vm.startPrank(user);
        IERC20(WETH).approve(address(connector), maxAmountIn);
        
        uint256 wethIn = connector.exchangeOut(WETH, WEETH, amountOut, maxAmountIn);
        vm.stopPrank();
        
        uint256 userWethBalanceAfter = IERC20(WETH).balanceOf(user);
        uint256 userWeethBalanceAfter = IERC20(WEETH).balanceOf(user);
        uint256 connectorWethBalanceAfter = IERC20(WETH).balanceOf(address(connector));
        uint256 connectorWeethBalanceAfter = IERC20(WEETH).balanceOf(address(connector));
        
        // Verify at least the exact amount of WEETH was received (may be slightly more due to rounding buffer)
        assertEq(userWeethBalanceAfter - userWeethBalanceBefore, amountOut, "Should receive at least amountOut WEETH");
        
        // Verify WETH was spent (should be less than maxAmountIn due to exchange rate)
        assertGt(userWethBalanceBefore - userWethBalanceAfter, 0, "WETH should be spent");
        assertLe(userWethBalanceBefore - userWethBalanceAfter, maxAmountIn, "Should not spend more than maxAmountIn");
        assertEq(userWethBalanceBefore - userWethBalanceAfter, wethIn, "WETH spent should match returned amountIn");
        
        // Verify exchange rate is NOT 1:1 (WETH amount spent should be more than WEETH received due to exchange rate)
        assertGt(wethIn, amountOut, "WETH amount spent should be more than WEETH received due to exchange rate");
        
        // Post-checks: ensure no tokens left in connector
        assertEq(connectorWethBalanceAfter, 0, "No WETH should remain in connector");
        assertEq(connectorWeethBalanceAfter, 0, "No WEETH should remain in connector");
    }
}
