// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.28;

import {ILowLevelVault} from "../../interface/ILowLevelVault.sol";
import {IFlashLoanConnector} from "../../interface/IFlashLoanConnector.sol";
import {IExchangeConnector} from "../../interface/IExchangeConnector.sol";
import {SafeERC20, IERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";

contract MintWithNegativeFlashLoanCollateral {
    using SafeERC20 for IERC20;
    using SafeERC20 for ILowLevelVault;

    function mintWithNegativeFlashLoanCollateral(
        int256 deltaShares,
        int256 deltaCollateral,
        int256 deltaBorrow,
        address borrowFlashLoan,
        address collateralToBorrowExchange,
        address vault,
        address user,
        address collateralAsset,
        address borrowAsset,
        uint256 maxAssetsCollateral
    ) internal returns (uint256) {
        uint256 userCollateralBalance = IERC20(collateralAsset).balanceOf(user);
        IFlashLoanConnector(borrowFlashLoan).flashLoan(
            borrowAsset,
            uint256(-deltaBorrow),
            abi.encodeCall(
                MintWithNegativeFlashLoanCollateral.mintWithNegativeFlashLoanCollateralFallback,
                (
                    deltaShares,
                    borrowFlashLoan,
                    collateralToBorrowExchange,
                    vault,
                    user,
                    collateralAsset,
                    borrowAsset,
                    maxAssetsCollateral,
                    deltaCollateral,
                    deltaBorrow
                )
            )
        );

        return userCollateralBalance - IERC20(collateralAsset).balanceOf(user);
    }

    function mintWithNegativeFlashLoanCollateralFallback(
        int256 deltaShares,
        address borrowFlashLoan,
        address collateralToBorrowExchange,
        address vault,
        address user,
        address collateralAsset,
        address borrowAsset,
        uint256 maxAssetsCollateral,
        int256 deltaCollateral,
        int256 deltaBorrow
    ) external {
        IERC20(borrowAsset).forceApprove(collateralToBorrowExchange, uint256(-deltaBorrow));
        ILowLevelVault(vault).executeLowLevelRebalanceShares(deltaShares);

        IERC20(borrowAsset).safeTransferFrom(user, address(this), maxAssetsCollateral);

        uint256 maxAmountIn = uint256(-deltaCollateral) + maxAssetsCollateral;
        IERC20(collateralAsset).forceApprove(collateralToBorrowExchange, maxAmountIn);
        uint256 collateralAssetsIn = IExchangeConnector(collateralToBorrowExchange).exchangeOut(
            collateralAsset, borrowAsset, uint256(-deltaBorrow), maxAmountIn
        );

        uint256 userAssetsIn = collateralAssetsIn - uint256(-deltaCollateral);
        uint256 refundAmount = maxAssetsCollateral - userAssetsIn;
        IERC20(collateralAsset).safeTransfer(user, refundAmount);

        IERC20(vault).safeTransfer(user, uint256(deltaShares));

        IERC20(borrowAsset).forceApprove(borrowFlashLoan, uint256(-deltaBorrow));
        IFlashLoanConnector(borrowFlashLoan).returnFlashLoan(borrowAsset, uint256(-deltaBorrow));
    }
}
