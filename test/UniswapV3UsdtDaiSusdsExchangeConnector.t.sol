// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.28;

import {Test} from "forge-std/Test.sol";
import {UniswapV3UsdtDaiSusdsExchangeConnector} from "../src/exchange_connectors/UniswapV3UsdtDaiSusdsExchangeConnector.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";

contract UniswapV3UsdtDaiSusdsExchangeConnectorTest is Test {
    using SafeERC20 for IERC20;
    
    UniswapV3UsdtDaiSusdsExchangeConnector public connector;
    
    // Mainnet addresses
    address public constant USDT = 0xdAC17F958D2ee523a2206206994597C13D831ec7;
    address public constant DAI = 0x6B175474E89094C44Da98b954EedeAC495271d0F;
    address public constant USDS = 0xdC035D45d973E3EC169d2276DDab16f1e407384F;
    address public constant SUSDS = 0xa3931d71877C0E7a3148CB7Eb4463524FEc27fbD;
    
    // Uniswap V3 USDT/DAI pool
    address public constant UNISWAP_V3_POOL = 0x48DA0965ab2d2cbf1C17C09cFB5Cbe67Ad5B1406;
    
    // Use a recent block where all contracts exist
    uint256 public constant FORK_BLOCK = 24_447_978; // Recent block with USDS deployed
    
    address public user = address(0x1337);
    uint256 public constant TEST_AMOUNT = 1000e6; // 1000 USDT (6 decimals)
    
    // Spark Protocol MigrationActions contract
    address public constant MIGRATION_CONTRACT = 0xf86141a5657Cf52AEB3E30eBccA5Ad3a8f714B89;
    
    function setUp() public {
        string memory rpcUrl = vm.envString("RPC_MAINNET");
        vm.createSelectFork(rpcUrl, FORK_BLOCK);
        
        // Verify contracts exist at this block
        require(USDS.code.length > 0, "USDS contract not found");
        require(SUSDS.code.length > 0, "sUSDS contract not found");
        require(MIGRATION_CONTRACT.code.length > 0, "Migration contract not found");
        require(UNISWAP_V3_POOL.code.length > 0, "Uniswap V3 pool not found");
        
        // Give user some USDT
        deal(USDT, user, TEST_AMOUNT * 10);
        
        connector = new UniswapV3UsdtDaiSusdsExchangeConnector(
            USDS,
            SUSDS,
            MIGRATION_CONTRACT
        );
    }
    
    function test_exchangeIn_happyCase() public {
        uint256 amountIn = TEST_AMOUNT;
        uint256 minAmountOut = 0; // Accept any amount
        
        uint256 userUsdtBalanceBefore = IERC20(USDT).balanceOf(user);
        uint256 userSusdsBalanceBefore = IERC20(SUSDS).balanceOf(user);
        
        vm.startPrank(user);
        // USDT doesn't return bool from approve, so we need to handle it differently
        (bool success,) = address(USDT).call(
            abi.encodeWithSignature("approve(address,uint256)", address(connector), amountIn)
        );
        require(success, "USDT approve failed");
        
        uint256 amountOut = connector.exchangeIn(USDT, SUSDS, amountIn, minAmountOut);
        vm.stopPrank();
        
        uint256 userUsdtBalanceAfter = IERC20(USDT).balanceOf(user);
        uint256 userSusdsBalanceAfter = IERC20(SUSDS).balanceOf(user);
        
        // Verify USDT was spent
        assertEq(userUsdtBalanceBefore - userUsdtBalanceAfter, amountIn, "USDT should be spent");
        
        // Verify sUSDS was received
        uint256 actualAmountOut = userSusdsBalanceAfter - userSusdsBalanceBefore;
        assertGt(actualAmountOut, 0, "Should receive sUSDS");
        assertEq(actualAmountOut, amountOut, "sUSDS balance should match returned amount");
        
        // Verify we got a reasonable amount (accounting for Uniswap V3 swap slippage and ERC4626 deposit)
        // Should receive at least 95% of input value after all conversions
        assertGe(actualAmountOut, amountIn * 95 / 100, "Should receive at least 95% of input value");
    }

function test_exchangeOut_happyCase() public {
    uint256 desiredSusdsOut = 10**18;
    uint256 maxUsdtIn = 10**6 * 2;

    // Give user enough USDT to cover maxAmountIn
    deal(USDT, user, maxUsdtIn);

    uint256 userUsdtBalanceBefore = IERC20(USDT).balanceOf(user);
    uint256 userSusdsBalanceBefore = IERC20(SUSDS).balanceOf(user);

    vm.startPrank(user);
    // USDT doesn't return bool from approve, so we need to handle it differently
    (bool success,) = address(USDT).call(
        abi.encodeWithSignature("approve(address,uint256)", address(connector), maxUsdtIn)
    );
    require(success, "USDT approve failed");

    uint256 usdtSpent = connector.exchangeOut(USDT, SUSDS, desiredSusdsOut, maxUsdtIn);
    vm.stopPrank();

    uint256 userUsdtBalanceAfter = IERC20(USDT).balanceOf(user);
    uint256 userSusdsBalanceAfter = IERC20(SUSDS).balanceOf(user);

    // USDT should be spent, but not more than maxUsdtIn
    assertLe(userUsdtBalanceBefore - userUsdtBalanceAfter, maxUsdtIn, "USDT used should not exceed maxAmountIn");
    assertEq(userUsdtBalanceBefore - userUsdtBalanceAfter, usdtSpent, "USDT spent should match returned amount");

    // sUSDS should be received
    uint256 susdsReceived = userSusdsBalanceAfter - userSusdsBalanceBefore;
    assertEq(susdsReceived, desiredSusdsOut, "Should receive exact specified sUSDS amount");

    // Should not use excessive USDT (more than 105% of sUSDS, allowing for some slippage)
    assertLe(usdtSpent, desiredSusdsOut * 105 / 100, "USDT spent should not exceed 105% of sUSDS out");
}
}
