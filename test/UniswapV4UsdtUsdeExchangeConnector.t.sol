// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.28;

import {Test} from "forge-std/Test.sol";
import {UniswapV4UsdtUsdeExchangeConnector} from "../src/exchange_connectors/UniswapV4UsdtUsdeExchangeConnector.sol";
import {SafeERC20, IERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import {IPositionManager} from "../src/interface/IPositionManager.sol";
import {PoolKey} from "../src/types/UniswapV4Structs.sol";

contract UniswapV4UsdtUsdeExchangeConnectorTest is Test {
    using SafeERC20 for IERC20;
    
    UniswapV4UsdtUsdeExchangeConnector public connector;

    // Mainnet addresses
    address public constant USDT = 0xdAC17F958D2ee523a2206206994597C13D831ec7;
    address public constant USDE = 0x4c9EDD5852cd905f086C759E8383e09bff1E68B3; // Ethena USDE
    address public constant SUSDE = 0x9D39A5DE30e57443BfF2A8307A4256c8797A3497; // Ethena sUSDE
    
    // Uniswap V4 mainnet addresses
    address public constant POOL_MANAGER = 0x000000000004444c5dc75cB358380D2e3dE08A90;
    address public constant POSITION_MANAGER = 0xbD216513d74C8cf14cf4747E6AaA6420FF64ee9e;
    
    // Pool ID for USDT/USDE pool - needs to be created/found in PositionManager
    // This is a placeholder - you need to create the pool first or find existing pool ID
    bytes25 public constant POOL_ID = bytes25(0x63bb22f47c7ede6578a25c873e77eb782ec8e4c19778e36ce6);
    
    uint256 public constant FORK_BLOCK = 24_447_946; // Update with recent block number
    
    address public user;
    
    // Test amounts - using smaller amounts due to limited sUSDE withdrawal pool
    uint256 public constant TEST_USDT_AMOUNT = 1e6; // 1 USDT (6 decimals)
    uint256 public constant TEST_SUSDE_AMOUNT = 1e18; // 1 sUSDE (18 decimals)

    function setUp() public {
        string memory rpcUrl = vm.envString("RPC_MAINNET");
        vm.createSelectFork(rpcUrl, FORK_BLOCK);

        // Verify pool key exists - it should have USDT and USDE (order may vary)
        PoolKey memory poolKey = IPositionManager(POSITION_MANAGER).poolKeys(POOL_ID);
        require(
            (poolKey.currency0 == USDT && poolKey.currency1 == USDE) ||
            (poolKey.currency0 == USDE && poolKey.currency1 == USDT),
            "Pool must contain USDT and USDE"
        );

        // Deploy connector with real Uniswap V4 addresses
        connector = new UniswapV4UsdtUsdeExchangeConnector(
            POOL_MANAGER,
            POSITION_MANAGER,
            POOL_ID,
            SUSDE
        );

        // Create test user
        user = address(0x1111);
        vm.deal(user, 100 ether);
        
        // Debug: Print connector addresses
        // console.log("Connector USDT:", connector.USDT());
        // console.log("Connector USDE:", connector.USDE());
        // console.log("Connector SUSDE:", connector.SUSDE());
    }

    function _dealTokens(address token, address to, uint256 amount) internal {
        // Deal tokens to user for testing
        deal(token, to, amount);
    }

    function test_exchangeIn_UsdtToSusde() public {
        // Test: exchangeIn USDT -> sUSDE (exact input)
        uint256 amountIn = TEST_USDT_AMOUNT;
        uint256 minAmountOut = 0; // No slippage protection for happy path
        
        // Use the actual USDT address from the connector (from pool key)
        address connectorUsdt = connector.USDT();
        address connectorSusde = connector.SUSDE();
        
        // Deal USDT to user
        _dealTokens(connectorUsdt, user, amountIn);
        
        // Get initial balances
        uint256 userUsdtBefore = IERC20(connectorUsdt).balanceOf(user);
        uint256 userSusdeBefore = IERC20(connectorSusde).balanceOf(user);
        
        // Approve connector and execute exchange
        vm.startPrank(user);
        IERC20(connectorUsdt).forceApprove(address(connector), amountIn);
        uint256 amountOut = connector.exchangeIn(connectorUsdt, connectorSusde, amountIn, minAmountOut);
        vm.stopPrank();
        
        // Get final balances
        uint256 userUsdtAfter = IERC20(connectorUsdt).balanceOf(user);
        uint256 userSusdeAfter = IERC20(connectorSusde).balanceOf(user);
        
        // Assertions
        assertGt(amountOut, 0, "Should receive sUSDE");
        assertEq(userUsdtBefore - userUsdtAfter, amountIn, "User should have spent exact USDT amount");
        assertEq(userSusdeAfter - userSusdeBefore, amountOut, "User should have received exact sUSDE amount");
        assertGe(amountOut, minAmountOut, "Should meet minimum output requirement");
    }

    function test_exchangeOut_UsdtToSusde() public {
        // Test: exchangeOut USDT -> sUSDE (exact output)
        uint256 amountOut = TEST_SUSDE_AMOUNT;
        uint256 maxAmountIn = TEST_USDT_AMOUNT * 10; // Allow larger buffer for small amounts
        
        // Use the actual addresses from the connector
        address connectorUsdt = connector.USDT();
        address connectorSusde = connector.SUSDE();
        
        // Deal USDT to user
        _dealTokens(connectorUsdt, user, maxAmountIn);
        
        // Get initial balances
        uint256 userUsdtBefore = IERC20(connectorUsdt).balanceOf(user);
        uint256 userSusdeBefore = IERC20(connectorSusde).balanceOf(user);
        
        // Approve connector and execute exchange
        vm.startPrank(user);
        IERC20(connectorUsdt).forceApprove(address(connector), maxAmountIn);
        uint256 amountIn = connector.exchangeOut(connectorUsdt, connectorSusde, amountOut, maxAmountIn);
        vm.stopPrank();
        
        // Get final balances
        uint256 userUsdtAfter = IERC20(connectorUsdt).balanceOf(user);
        uint256 userSusdeAfter = IERC20(connectorSusde).balanceOf(user);
        
        // Assertions
        assertGt(amountIn, 0, "Should have used some USDT");
        assertLe(amountIn, maxAmountIn, "Should not exceed max input");
        assertEq(userSusdeAfter - userSusdeBefore, amountOut, "User should have received exact sUSDE amount");
        // Note: For exchangeOut, user spends maxAmountIn (all tokens are transferred upfront)
        // amountIn is informational - actual amount needed
        assertEq(userUsdtBefore - userUsdtAfter, maxAmountIn, "User should have spent maxAmountIn");
    }

}
