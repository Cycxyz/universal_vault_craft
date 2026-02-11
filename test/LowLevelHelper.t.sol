// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.28;

import {Test} from "forge-std/Test.sol";
import {LowLevelHelper} from "../src/LowLevelHelper.sol";
import {MockLowLevelVault} from "./utils/MockLowLevelVault.sol";
import {MockExchangeConnector} from "./utils/MockExchangeConnector.sol";
import {MockFlashLoanConnector} from "./utils/MockFlashLoanConnector.sol";
import {MockERC20} from "./utils/MockERC20.sol";

contract LowLevelHelperTest is Test {
    LowLevelHelper public helper;
    MockLowLevelVault public vault;
    MockExchangeConnector public exchangeConnector;
    MockFlashLoanConnector public flashLoanConnector;
    MockERC20 public collateralToken;
    MockERC20 public borrowToken;

    address public receiver = address(0x2);

    uint256 public constant PRICE_PRECISION = 1e18;
    uint256 public constant BORROW_PRICE = 1e18;
    uint256 public constant COLLATERAL_PRICE = 2e18;
    uint256 public constant SHARE_PRICE = 1e18;
    uint256 public constant FEE_PRECISION = 1e18;
    uint256 public constant FEE_PERCENTAGE = 0;

    function setUp() public {
        collateralToken = new MockERC20("Collateral Token", "COL");
        borrowToken = new MockERC20("Borrow Token", "BOR");

        exchangeConnector = new MockExchangeConnector(
            address(collateralToken),
            address(borrowToken),
            COLLATERAL_PRICE,
            BORROW_PRICE,
            PRICE_PRECISION,
            FEE_PERCENTAGE,
            FEE_PRECISION
        );

        flashLoanConnector = new MockFlashLoanConnector();

        vault = new MockLowLevelVault(
            BORROW_PRICE, COLLATERAL_PRICE, SHARE_PRICE, address(borrowToken), address(collateralToken)
        );

        helper = new LowLevelHelper();

        collateralToken.mint(receiver, 1000e18);
        borrowToken.mint(receiver, 1000e18);

        collateralToken.mint(address(exchangeConnector), 10000e18);
        borrowToken.mint(address(exchangeConnector), 10000e18);
        collateralToken.mint(address(flashLoanConnector), 10000e18);
    }

    // --- Helper: vault constraint 2*deltaCollateral = deltaBorrow + deltaShares (with 1e18 prices) ---
    function _executeRebalance(
        int256 deltaShares,
        int256 deltaCollateral,
        int256 deltaBorrow,
        bool isBorrowAsset,
        uint256 assetsLimit
    ) internal returns (uint256 assetAmount) {
        vault.setResult(deltaCollateral, deltaBorrow, deltaShares);
        if (deltaShares > 0) {
            vm.startPrank(receiver);
            borrowToken.approve(address(helper), assetsLimit);
            collateralToken.approve(address(helper), assetsLimit);
            vm.stopPrank();
        } else {
            uint256 sharesNeeded = uint256(-deltaShares);
            deal(address(vault), receiver, sharesNeeded);
            vm.prank(receiver);
            vault.approve(address(helper), sharesNeeded);
        }
        return helper.executeLowLevelRebalanceWithOneAsset(
            deltaShares,
            address(flashLoanConnector),
            address(flashLoanConnector),
            address(exchangeConnector),
            address(exchangeConnector),
            address(vault),
            receiver,
            isBorrowAsset,
            assetsLimit
        );
    }

    // 1. isBorrowAsset: deltaC>0, deltaB>0, deltaS>0 → mintWithPositiveFlashLoanBorrow
    function test_1_MintWithPositiveFlashLoanBorrow() public {
        int256 deltaShares = 100e18;
        int256 deltaBorrow = 50e18;
        int256 deltaCollateral = 75e18; // 2*75 = 50+100
        uint256 maxAssetsBorrow = 200e18;
        uint256 assetAmount = _executeRebalance(deltaShares, deltaCollateral, deltaBorrow, true, maxAssetsBorrow);
        assertTrue(assetAmount > 0 && assetAmount <= maxAssetsBorrow);
        assertEq(vault.balanceOf(receiver), uint256(deltaShares));
    }

    // 2. isBorrowAsset: deltaC>0, deltaB>0, deltaS<0 → redeemWithPositiveFlashLoanBorrow
    function test_2_RedeemWithPositiveFlashLoanBorrow() public {
        int256 deltaShares = -80e18;
        int256 deltaBorrow = 100e18;
        int256 deltaCollateral = 10e18; // 2*10 = 100-80
        uint256 minAssetsBorrow = 80e18;
        uint256 assetAmount = _executeRebalance(deltaShares, deltaCollateral, deltaBorrow, true, minAssetsBorrow);
        assertTrue(assetAmount >= minAssetsBorrow);
        assertEq(vault.balanceOf(receiver), 0);
    }

    // 3. isBorrowAsset: deltaC>0, deltaB<0, deltaS>0 → mintWithNoFlashLoanBorrow
    function test_3_MintWithNoFlashLoanBorrow() public {
        int256 deltaShares = 100e18;
        int256 deltaBorrow = -50e18;
        int256 deltaCollateral = 25e18; // 2*25 = -50+100
        uint256 maxAssetsBorrow = 100e18;
        uint256 assetAmount = _executeRebalance(deltaShares, deltaCollateral, deltaBorrow, true, maxAssetsBorrow);
        assertTrue(assetAmount > 0 && assetAmount <= maxAssetsBorrow);
        assertEq(vault.balanceOf(receiver), uint256(deltaShares));
    }

    // 4. isBorrowAsset: deltaC<0, deltaB>0, deltaS<0 → redeemWithNoFlashLoanBorrow
    function test_4_RedeemWithNoFlashLoanBorrow() public {
        int256 deltaShares = -100e18;
        int256 deltaBorrow = 50e18;
        int256 deltaCollateral = -25e18; // 2*(-25) = 50-100
        uint256 minAssetsBorrow = 100e18;
        uint256 assetAmount = _executeRebalance(deltaShares, deltaCollateral, deltaBorrow, true, minAssetsBorrow);
        assertTrue(assetAmount >= minAssetsBorrow);
    }

    // 5. isBorrowAsset: deltaC<0, deltaB<0, deltaS>0 → mintWithNegativeFlashLoanBorrow
    function test_5_MintWithNegativeFlashLoanBorrow() public {
        int256 deltaShares = 100e18;
        int256 deltaBorrow = -200e18;
        int256 deltaCollateral = -50e18; // 2*(-50) = -200+100; user provides shortfall
        uint256 maxAssetsBorrow = 100e18;
        uint256 assetAmount = _executeRebalance(deltaShares, deltaCollateral, deltaBorrow, true, maxAssetsBorrow);
        assertTrue(assetAmount <= maxAssetsBorrow);
        assertEq(vault.balanceOf(receiver), uint256(deltaShares));
    }

    // 6. isBorrowAsset: deltaC<0, deltaB<0, deltaS<0 → redeemWithNegativeFlashLoanBorrow
    function test_6_RedeemWithNegativeFlashLoanBorrow() public {
        int256 deltaShares = -100e18;
        int256 deltaBorrow = -50e18;
        int256 deltaCollateral = -75e18; // 2*(-75) = -50-100
        uint256 minAssetsBorrow = 100e18;
        uint256 assetAmount = _executeRebalance(deltaShares, deltaCollateral, deltaBorrow, true, minAssetsBorrow);
        assertTrue(assetAmount >= minAssetsBorrow);
    }

    // 7. !isBorrowAsset: deltaC>0, deltaB>0, deltaS>0 → mintWithPositiveFlashLoanCollateral
    function test_7_MintWithPositiveFlashLoanCollateral() public {
        int256 deltaShares = 100e18;
        int256 deltaBorrow = 50e18;
        int256 deltaCollateral = 75e18;
        uint256 maxAssetsCollateral = 50e18;
        uint256 assetAmount = _executeRebalance(deltaShares, deltaCollateral, deltaBorrow, false, maxAssetsCollateral);
        assertTrue(assetAmount > 0 && assetAmount <= maxAssetsCollateral);
        assertEq(vault.balanceOf(receiver), uint256(deltaShares));
    }

    // 8. !isBorrowAsset: deltaC>0, deltaB>0, deltaS<0 → redeemWithPositiveFlashLoanCollateral
    function test_8_RedeemWithPositiveFlashLoanCollateral() public {
        int256 deltaShares = -80e18;
        int256 deltaBorrow = 100e18;
        int256 deltaCollateral = 10e18;
        uint256 minAssetsCollateral = 40e18;
        uint256 assetAmount = _executeRebalance(deltaShares, deltaCollateral, deltaBorrow, false, minAssetsCollateral);
        assertTrue(assetAmount >= minAssetsCollateral);
    }

    // 9. !isBorrowAsset: deltaC>0, deltaB<0, deltaS>0 → mintWithNoFlashLoanCollateral
    function test_9_MintWithNoFlashLoanCollateral() public {
        int256 deltaShares = 100e18;
        int256 deltaBorrow = -50e18;
        int256 deltaCollateral = 25e18;
        uint256 maxAssetsCollateral = 50e18;
        uint256 assetAmount = _executeRebalance(deltaShares, deltaCollateral, deltaBorrow, false, maxAssetsCollateral);
        assertTrue(assetAmount > 0 && assetAmount <= maxAssetsCollateral);
        assertEq(vault.balanceOf(receiver), uint256(deltaShares));
    }

    // 10. !isBorrowAsset: deltaC<0, deltaB>0, deltaS<0 → redeemWithNoFlashLoanCollateral
    function test_10_RedeemWithNoFlashLoanCollateral() public {
        int256 deltaShares = -100e18;
        int256 deltaBorrow = 50e18;
        int256 deltaCollateral = -25e18;
        uint256 minAssetsCollateral = 50e18;
        uint256 assetAmount = _executeRebalance(deltaShares, deltaCollateral, deltaBorrow, false, minAssetsCollateral);
        assertTrue(assetAmount >= minAssetsCollateral);
    }

    // 11. !isBorrowAsset: deltaC<0, deltaB<0, deltaS>0 → mintWithNegativeFlashLoanCollateral
    function test_11_MintWithNegativeFlashLoanCollateral() public {
        int256 deltaShares = 100e18;
        int256 deltaBorrow = -200e18;
        int256 deltaCollateral = -50e18;
        uint256 maxAssetsCollateral = 50e18;
        uint256 assetAmount = _executeRebalance(deltaShares, deltaCollateral, deltaBorrow, false, maxAssetsCollateral);
        assertTrue(assetAmount > 0 && assetAmount <= maxAssetsCollateral);
        assertEq(vault.balanceOf(receiver), uint256(deltaShares));
    }

    // 12. !isBorrowAsset: deltaC<0, deltaB<0, deltaS<0 → redeemWithNegativeFlashLoanCollateral
    function test_12_RedeemWithNegativeFlashLoanCollateral() public {
        int256 deltaShares = -100e18;
        int256 deltaBorrow = -50e18;
        int256 deltaCollateral = -75e18;
        uint256 minAssetsCollateral = 50e18;
        uint256 assetAmount = _executeRebalance(deltaShares, deltaCollateral, deltaBorrow, false, minAssetsCollateral);
        assertTrue(assetAmount >= minAssetsCollateral);
    }
}
