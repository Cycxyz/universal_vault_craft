// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.28;

import {Test} from "forge-std/Test.sol";
import {UniswapV4WbtcToLbtcConnector} from "../src/exchange_connectors/UniswapV4WbtcToLbtcConnector.sol";
import {ILBTC} from "../src/interface/ILBTC.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {IPositionManager} from "../src/interface/IPositionManager.sol";
import {PoolKey} from "../src/types/UniswapV4Structs.sol";

contract UniswapV4WbtcToLbtcConnectorTest is Test {
    UniswapV4WbtcToLbtcConnector public connector;
    
    address public constant LBTC = 0x8236a87084f8B84306f72007F36F2618A5634494;
    address public constant WBTC = 0x2260FAC5E5542a773Aa44fBCfeDf7C193bc2C599;
    address public constant BTC_B = 0xB0F70C0bD6FD87dbEb7C10dC692a2a6106817072;
    
    // Uniswap V4 mainnet addresses
    address public constant POOL_MANAGER = 0x000000000004444c5dc75cB358380D2e3dE08A90;
    address public constant POSITION_MANAGER = 0xbD216513d74C8cf14cf4747E6AaA6420FF64ee9e;
    
    // Pool ID for WBTC/BTC.b pool (first 25 bytes of the pool ID)
    // Pool ID: 0x627bfda0f23d0aad057e59224c9149d6b42848fa7c455f5addffc682b34cc453
    // Taking first 25 bytes (50 hex chars): 627bfda0f23d0aad057e59224c9149d6b42848fa7c455f5add
    bytes25 public constant POOL_ID = bytes25(0x627bfda0f23d0aad057e59224c9149d6b42848fa7c455f5add);
    
    uint256 public constant FORK_BLOCK = 24_447_946; // More recent block with pool liquidity
    
    address public user = address(0x1337);
    uint256 public constant DEPOSIT_AMOUNT = 0.01e8; // 0.01 WBTC (8 decimals)

    function setUp() public {
        string memory rpcUrl = vm.envString("RPC_MAINNET");
        vm.createSelectFork(rpcUrl, FORK_BLOCK);

        // Verify pool key exists
        PoolKey memory poolKey = IPositionManager(POSITION_MANAGER).poolKeys(POOL_ID);
        require(
            (poolKey.currency0 == WBTC && poolKey.currency1 == BTC_B) ||
            (poolKey.currency0 == BTC_B && poolKey.currency1 == WBTC),
            "Pool must contain WBTC and BTC.b"
        );

        connector = new UniswapV4WbtcToLbtcConnector(
            POOL_MANAGER,
            POSITION_MANAGER,
            POOL_ID
        );
        
        // Give user some WBTC tokens
        deal(WBTC, user, DEPOSIT_AMOUNT * 10);
    }

    function test_exchangeIn_happyCase() public {
        uint256 amountIn = DEPOSIT_AMOUNT;
        uint256 minAmountOut = 0; // Accept any amount
        
        uint256 userWbtcBalanceBefore = IERC20(WBTC).balanceOf(user);
        
        vm.startPrank(user);
        IERC20(WBTC).approve(address(connector), amountIn);
        
        uint256 lbtcOut = connector.exchangeIn(WBTC, LBTC, amountIn, minAmountOut);
        vm.stopPrank();
        
        uint256 userWbtcBalanceAfter = IERC20(WBTC).balanceOf(user);
        uint256 connectorWbtcBalanceAfter = IERC20(WBTC).balanceOf(address(connector));
        uint256 connectorBtcBBalanceAfter = IERC20(BTC_B).balanceOf(address(connector));
        uint256 connectorLbtcBalanceAfter = IERC20(LBTC).balanceOf(address(connector));
        
        // Verify WBTC was spent
        assertEq(userWbtcBalanceBefore - userWbtcBalanceAfter, amountIn, "WBTC should be spent");
        
        // Verify LBTC amount returned (should be greater than zero)
        assertGt(lbtcOut, 0, "Should return LBTC amount");
        
        // Note: LBTC deposit is asynchronous - it burns BTC.b and sends a cross-chain message
        // The LBTC will be minted later when the message is processed
        // So we can't verify the LBTC balance increase synchronously
        // The connector returns the expected amount based on the ratio
        
        // Post-checks: ensure no tokens left in connector
        assertEq(connectorWbtcBalanceAfter, 0, "No WBTC should remain in connector");
        assertEq(connectorBtcBBalanceAfter, 0, "No BTC.b should remain in connector");
        assertEq(connectorLbtcBalanceAfter, 0, "No LBTC should remain in connector");
    }
}
