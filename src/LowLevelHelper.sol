// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.28;

import {ILowLevelVault} from "./interface/ILowLevelVault.sol";
import {SafeERC20, IERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import {MintWithNegativeFlashLoanCollateral} from "./utils/scenario_handler/MintWithNegativeFlashLoanCollateral.sol";
import {MintWithPositiveFlashLoanBorrow} from "./utils/scenario_handler/MintWithPositiveFlashLoanBorrow.sol";
import {RedeemWithPositiveFlashLoanBorrow} from "./utils/scenario_handler/RedeemWithPositiveFlashLoanBorrow.sol";
import {MintWithNoFlashLoanBorrow} from "./utils/scenario_handler/MintWithNoFlashLoanBorrow.sol";
import {RedeemWithNoFlashLoanBorrow} from "./utils/scenario_handler/RedeemWithNoFlashLoanBorrow.sol";
import {MintWithNegativeFlashLoanBorrow} from "./utils/scenario_handler/MintWithNegativeFlashLoanBorrow.sol";
import {MintWithPositiveFlashLoanCollateral} from "./utils/scenario_handler/MintWithPositiveFlashLoanCollateral.sol";
import {RedeemWithNegativeFlashLoanBorrow} from "./utils/scenario_handler/RedeemWithNegativeFlashLoanBorrow.sol";
import {RedeemWithNegativeFlashLoanCollateral} from "./utils/scenario_handler/RedeemWithNegativeFlashLoanCollateral.sol";

contract LowLevelHelper is
    MintWithNegativeFlashLoanCollateral,
    MintWithNegativeFlashLoanBorrow,
    MintWithPositiveFlashLoanBorrow,
    MintWithPositiveFlashLoanCollateral,
    RedeemWithPositiveFlashLoanBorrow,
    MintWithNoFlashLoanBorrow,
    RedeemWithNoFlashLoanBorrow,
    RedeemWithNegativeFlashLoanBorrow
{
    using SafeERC20 for IERC20;
    using SafeERC20 for ILowLevelVault;

    struct RebalanceParams {
        int256 deltaShares;
        address borrowFlashLoan;
        address collateralFlashLoan;
        address borrowToCollateralExchange;
        address collateralToBorrowExchange;
        address vault;
        address receiver;
        bool isBorrowAsset;
        uint256 assetsLimit;
    }

    struct VaultRebalanceState {
        address borrowAsset;
        address collateralAsset;
        int256 deltaCollateral;
        int256 deltaBorrow;
    }

    function executeLowLevelRebalanceWithOneAsset(
        int256 deltaShares,
        address borrowFlashLoan,
        address collateralFlashLoan,
        address borrowToCollateralExchange,
        address collateralToBorrowExchange,
        address vault,
        address receiver,
        bool isBorrowAsset,
        uint256 assetsLimit
    ) external returns (uint256 assetAmount) {
        RebalanceParams memory params = RebalanceParams({
            deltaShares: deltaShares,
            borrowFlashLoan: borrowFlashLoan,
            collateralFlashLoan: collateralFlashLoan,
            borrowToCollateralExchange: borrowToCollateralExchange,
            collateralToBorrowExchange: collateralToBorrowExchange,
            vault: vault,
            receiver: receiver,
            isBorrowAsset: isBorrowAsset,
            assetsLimit: assetsLimit
        });

        address borrowAsset = ILowLevelVault(vault).borrowAsset();
        address collateralAsset = ILowLevelVault(vault).collateralAsset();

        (int256 deltaCollateral, int256 deltaBorrow) =
            ILowLevelVault(params.vault).previewLowLevelRebalanceShares(params.deltaShares);

        if (deltaCollateral > 0 && deltaBorrow > 0 && params.deltaShares > 0 && params.isBorrowAsset) {
            return mintWithPositiveFlashLoanBorrow(
                MintWithPositiveFlashLoanBorrow.MintWithPositiveFlashLoanBorrowInput({
                    deltaShares: params.deltaShares,
                    deltaCollateral: deltaCollateral,
                    deltaBorrow: deltaBorrow,
                    collateralFlashLoan: params.collateralFlashLoan,
                    borrowToCollateralExchange: params.borrowToCollateralExchange,
                    vault: params.vault,
                    user: params.receiver,
                    collateralAsset: collateralAsset,
                    borrowAsset: borrowAsset,
                    maxAssetsBorrow: params.assetsLimit
                })
            );
        } else if (deltaCollateral > 0 && deltaBorrow > 0 && params.deltaShares < 0 && params.isBorrowAsset) {
            return redeemWithPositiveFlashLoanBorrow(
                RedeemWithPositiveFlashLoanBorrow.RedeemWithPositiveFlashLoanBorrowInput({
                    deltaShares: params.deltaShares,
                    deltaCollateral: deltaCollateral,
                    deltaBorrow: deltaBorrow,
                    collateralFlashLoan: params.collateralFlashLoan,
                    borrowToCollateralExchange: params.borrowToCollateralExchange,
                    vault: params.vault,
                    user: params.receiver,
                    collateralAsset: collateralAsset,
                    borrowAsset: borrowAsset,
                    minAssetsBorrow: params.assetsLimit
                })
            );
        } else if (deltaCollateral > 0 && deltaBorrow < 0 && params.deltaShares > 0 && params.isBorrowAsset) {
            return mintWithNoFlashLoanBorrow(
                MintWithNoFlashLoanBorrow.MintWithNoFlashLoanBorrowInput({
                    deltaShares: params.deltaShares,
                    deltaCollateral: deltaCollateral,
                    deltaBorrow: deltaBorrow,
                    borrowToCollateralExchange: params.borrowToCollateralExchange,
                    vault: params.vault,
                    user: params.receiver,
                    collateralAsset: collateralAsset,
                    borrowAsset: borrowAsset,
                    maxAssetsBorrow: params.assetsLimit
                })
            );
        }
        // case when deltaCollateral > 0 && deltaBorrow < 0 && params.deltaShares < 0 is not possible
        // case when deltaCollateral < 0 && deltaBorrow > 0 && params.deltaShares > 0 is not possible
        else if (deltaCollateral < 0 && deltaBorrow > 0 && params.deltaShares < 0 && params.isBorrowAsset) {
            return redeemWithNoFlashLoanBorrow(
                RedeemWithNoFlashLoanBorrow.RedeemWithNoFlashLoanBorrowInput({
                    deltaShares: params.deltaShares,
                    deltaCollateral: deltaCollateral,
                    deltaBorrow: deltaBorrow,
                    collateralToBorrowExchange: params.collateralToBorrowExchange,
                    vault: params.vault,
                    user: params.receiver,
                    collateralAsset: collateralAsset,
                    borrowAsset: borrowAsset,
                    minAssetsBorrow: params.assetsLimit
                })
            );
        } else if (deltaCollateral < 0 && deltaBorrow < 0 && params.deltaShares > 0 && params.isBorrowAsset) {
            return mintWithNegativeFlashLoanBorrow(
                MintWithNegativeFlashLoanBorrow.MintWithNegativeFlashLoanBorrowInput({
                    deltaShares: params.deltaShares,
                    deltaCollateral: deltaCollateral,
                    deltaBorrow: deltaBorrow,
                    borrowFlashLoan: params.borrowFlashLoan,
                    borrowToCollateralExchange: params.borrowToCollateralExchange,
                    vault: params.vault,
                    user: params.receiver,
                    collateralAsset: collateralAsset,
                    borrowAsset: borrowAsset,
                    maxAssetsBorrow: params.assetsLimit
                })
            );
        } else if (deltaCollateral < 0 && deltaBorrow < 0 && params.deltaShares < 0 && params.isBorrowAsset) {
            return redeemWithNegativeFlashLoanBorrow(
                RedeemWithNegativeFlashLoanBorrow.RedeemWithNegativeFlashLoanBorrowInput({
                    deltaShares: params.deltaShares,
                    deltaCollateral: deltaCollateral,
                    deltaBorrow: deltaBorrow,
                    borrowFlashLoan: params.borrowFlashLoan,
                    borrowToCollateralExchange: params.borrowToCollateralExchange,
                    vault: params.vault,
                    user: params.receiver,
                    collateralAsset: collateralAsset,
                    borrowAsset: borrowAsset,
                    minAssetsBorrow: params.assetsLimit
                })
            );
        }
        return 0;
    }
}
