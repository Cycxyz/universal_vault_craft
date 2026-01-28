// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.28;

import {ILowLevelVault} from "./interface/ILowLevelVault.sol";
import {SafeERC20, IERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import {MintWithNegativeFlashLoanCollateral} from "./utils/scenario_handler/MintWithNegativeFlashLoanCollateral.sol";

contract LowLevelHelper is MintWithNegativeFlashLoanCollateral {
    using SafeERC20 for IERC20;
    using SafeERC20 for ILowLevelVault;

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
        address borrowAsset = ILowLevelVault(vault).borrowAsset();
        address collateralAsset = ILowLevelVault(vault).collateralAsset();

        (int256 deltaCollateral, int256 deltaBorrow) = ILowLevelVault(vault).previewLowLevelRebalanceShares(deltaShares);

        if (deltaCollateral < 0 && deltaBorrow < 0 && deltaShares > 0 && !isBorrowAsset) {
            return mintWithNegativeFlashLoanCollateral(
                deltaShares,
                deltaCollateral,
                deltaBorrow,
                borrowFlashLoan,
                collateralToBorrowExchange,
                vault,
                receiver,
                collateralAsset,
                borrowAsset,
                assetsLimit
            );
        }
        return 0;
    }


}
