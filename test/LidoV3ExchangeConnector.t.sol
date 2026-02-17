// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.28;

import {Test} from "forge-std/Test.sol";
import {LidoV3ExchangeConnector} from "../src/exchange_connectors/LidoV3ExchangeConnector.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";

contract LidoV3ExchangeConnectorTest is Test {
    LidoV3ExchangeConnector public connector;
    
    // Mainnet addresses
    address public constant WETH = 0xC02aaA39b223FE8D0A0e5C4F27eAD9083C756Cc2;
    address public constant STETH = 0xae7ab96520DE3A18E5e111B5EaAb095312D7fE84;
    
    uint256 public constant FORK_BLOCK = 24448072; // Recent block to ensure Lido v3 is operational
    
    address public user = address(0x1337);
    uint256 public constant WETH_AMOUNT = 1 ether;

    function setUp() public {
        string memory rpcUrl = vm.envString("RPC_MAINNET");
        vm.createSelectFork(rpcUrl, FORK_BLOCK);

        connector = new LidoV3ExchangeConnector(WETH);
        
        // Give user some WETH tokens
        deal(WETH, user, WETH_AMOUNT * 10);
        
        // Note: stETH -> WETH is not supported (requires async withdrawal queue)
    }

    function test_exchangeIn_WETH_to_stETH_happyCase() public {
        uint256 amountIn = WETH_AMOUNT;
        uint256 minAmountOut = 0; // Accept any amount
        
        uint256 userWethBalanceBefore = IERC20(WETH).balanceOf(user);
        uint256 userStEthBalanceBefore = IERC20(STETH).balanceOf(user);
        
        vm.startPrank(user);
        IERC20(WETH).approve(address(connector), amountIn);
        
        uint256 stEthOut = connector.exchangeIn(WETH, STETH, amountIn, minAmountOut);
        vm.stopPrank();
        
        uint256 userWethBalanceAfter = IERC20(WETH).balanceOf(user);
        uint256 userStEthBalanceAfter = IERC20(STETH).balanceOf(user);
        uint256 connectorWethBalanceAfter = IERC20(WETH).balanceOf(address(connector));
        uint256 connectorStEthBalanceAfter = IERC20(STETH).balanceOf(address(connector));
        
        // Verify WETH was spent
        assertEq(userWethBalanceBefore - userWethBalanceAfter, amountIn, "WETH should be spent");
        
        // Verify stETH was received
        assertEq(userStEthBalanceAfter - userStEthBalanceBefore, stEthOut, "stETH balance should increase");
        assertGt(stEthOut, 0, "Should receive stETH");
        
        // Verify exchange rate is approximately 1:1 (stETH may be slightly less due to rebasing, but very close)
        // stETH from submit() should be very close to 1:1 with ETH
        assertGe(stEthOut, amountIn * 99 / 100, "stETH amount should be close to WETH amount");
        
        // Post-checks: ensure no tokens left in connector
        assertEq(connectorWethBalanceAfter, 0, "No WETH should remain in connector");
        assertEq(connectorStEthBalanceAfter, 0, "No stETH should remain in connector");
    }

    function test_exchangeOut_WETH_to_stETH_happyCase() public {
        // Test exchangeOut: WETH -> stETH (exact output)
        uint256 amountOut = WETH_AMOUNT / 2; // Want 0.5 ETH worth of stETH
        uint256 maxAmountIn = WETH_AMOUNT; // Willing to spend up to 1 WETH
        
        uint256 userWethBalanceBefore = IERC20(WETH).balanceOf(user);
        uint256 userStEthBalanceBefore = IERC20(STETH).balanceOf(user);
        
        vm.startPrank(user);
        IERC20(WETH).approve(address(connector), maxAmountIn);
        
        uint256 wethIn = connector.exchangeOut(WETH, STETH, amountOut, maxAmountIn);
        vm.stopPrank();
        
        uint256 userWethBalanceAfter = IERC20(WETH).balanceOf(user);
        uint256 userStEthBalanceAfter = IERC20(STETH).balanceOf(user);
        uint256 connectorWethBalanceAfter = IERC20(WETH).balanceOf(address(connector));
        uint256 connectorStEthBalanceAfter = IERC20(STETH).balanceOf(address(connector));
        
        // Verify at least the exact amount of stETH was received (may be slightly more due to rounding buffer)
        assertGe(userStEthBalanceAfter - userStEthBalanceBefore, amountOut, "Should receive at least amountOut stETH");
        
        // Verify WETH was spent (should be close to amountOut due to ~1:1 exchange rate)
        assertGt(userWethBalanceBefore - userWethBalanceAfter, 0, "WETH should be spent");
        assertLe(userWethBalanceBefore - userWethBalanceAfter, maxAmountIn, "Should not spend more than maxAmountIn");
        assertEq(userWethBalanceBefore - userWethBalanceAfter, wethIn, "WETH spent should match returned amountIn");
        
        // Verify exchange rate is approximately 1:1
        assertGe(wethIn, amountOut * 99 / 100, "WETH amount spent should be close to stETH received");
        assertLe(wethIn, amountOut * 101 / 100, "WETH amount spent should be close to stETH received");
        
        // Post-checks: ensure no tokens left in connector
        assertEq(connectorWethBalanceAfter, 0, "No WETH should remain in connector");
        assertEq(connectorStEthBalanceAfter, 0, "No stETH should remain in connector");
    }

    function test_exchangeIn_stETH_to_WETH_notSupported() public {
        uint256 amountIn = WETH_AMOUNT;
        uint256 minAmountOut = 0;
        
        vm.startPrank(user);
        IERC20(STETH).approve(address(connector), amountIn);
        
        // Should revert because stETH -> WETH is not supported via native Lido flow
        vm.expectRevert();
        connector.exchangeIn(STETH, WETH, amountIn, minAmountOut);
        vm.stopPrank();
    }

    function test_exchangeOut_stETH_to_WETH_notSupported() public {
        uint256 amountOut = WETH_AMOUNT / 2;
        uint256 maxAmountIn = WETH_AMOUNT;
        
        vm.startPrank(user);
        IERC20(STETH).approve(address(connector), maxAmountIn);
        
        // Should revert because stETH -> WETH is not supported via native Lido flow
        vm.expectRevert();
        connector.exchangeOut(STETH, WETH, amountOut, maxAmountIn);
        vm.stopPrank();
    }

    function test_exchangeIn_slippageProtection() public {
        uint256 amountIn = WETH_AMOUNT;
        uint256 minAmountOut = amountIn; // Set minimum to full amount (will fail due to rebasing)
        
        vm.startPrank(user);
        IERC20(WETH).approve(address(connector), amountIn);
        
        // This should revert due to slippage protection
        vm.expectRevert();
        connector.exchangeIn(WETH, STETH, amountIn, minAmountOut);
        vm.stopPrank();
    }

    function test_exchangeOut_slippageProtection() public {
        uint256 amountOut = WETH_AMOUNT;
        uint256 maxAmountIn = WETH_AMOUNT / 2; // Set max to half (will fail)
        
        vm.startPrank(user);
        IERC20(WETH).approve(address(connector), maxAmountIn);
        
        // This should revert due to slippage protection
        vm.expectRevert();
        connector.exchangeOut(WETH, STETH, amountOut, maxAmountIn);
        vm.stopPrank();
    }

    function test_invalidTokenPair() public {
        vm.startPrank(user);
        IERC20(WETH).approve(address(connector), WETH_AMOUNT);
        
        // Try to exchange WETH -> WETH (invalid pair)
        vm.expectRevert();
        connector.exchangeIn(WETH, WETH, WETH_AMOUNT, 0);
        vm.stopPrank();
    }
}
