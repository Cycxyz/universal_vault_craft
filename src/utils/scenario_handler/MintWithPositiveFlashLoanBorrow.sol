// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.28;

import {ILowLevelVault} from "../../interface/ILowLevelVault.sol";
import {IFlashLoanConnector} from "../../interface/IFlashLoanConnector.sol";
import {IExchangeConnector} from "../../interface/IExchangeConnector.sol";
import {SafeERC20, IERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";

contract MintWithPositiveFlashLoanBorrow {
    using SafeERC20 for IERC20;
    using SafeERC20 for ILowLevelVault;

    function mintWithPositiveFlashLoanBorrow(
        int256 deltaShares,
        int256 deltaCollateral,
        int256 deltaBorrow,
        address collateralFlashLoan,
        address borrowToCollateralExchange,
        address vault,
        address user,
        address collateralAsset,
        address borrowAsset,
        uint256 maxAssetsBorrow
    ) internal returns (uint256) {
        uint256 userBorrowBalance = IERC20(borrowAsset).balanceOf(user);
        IFlashLoanConnector(collateralFlashLoan).flashLoan(
            collateralAsset,
            uint256(deltaCollateral),
            abi.encodeCall(
                MintWithPositiveFlashLoanBorrow.mintWithPositiveFlashLoanBorrowFallback,
                (
                    deltaShares,
                    collateralFlashLoan,
                    borrowToCollateralExchange,
                    vault,
                    user,
                    collateralAsset,
                    borrowAsset,
                    maxAssetsBorrow,
                    deltaCollateral,
                    deltaBorrow
                )
            )
        );

        return userBorrowBalance - IERC20(borrowAsset).balanceOf(user);
    }

    function mintWithPositiveFlashLoanBorrowFallback(
        int256 deltaShares,
        address collateralFlashLoan,
        address borrowToCollateralExchange,
        address vault,
        address user,
        address collateralAsset,
        address borrowAsset,
        uint256 maxAssetsBorrow,
        int256 deltaCollateral,
        int256 deltaBorrow
    ) external {
        IERC20(collateralAsset).forceApprove(vault, uint256(deltaCollateral));
        ILowLevelVault(vault).executeLowLevelRebalanceShares(deltaShares);

        IERC20(borrowAsset).safeTransferFrom(user, address(this), maxAssetsBorrow);
        uint256 maxAmountIn = uint256(deltaBorrow) + maxAssetsBorrow;
        IERC20(borrowAsset).forceApprove(borrowToCollateralExchange, maxAmountIn);
        uint256 borrowAssetsIn = IExchangeConnector(borrowToCollateralExchange).exchangeOut(
            borrowAsset, collateralAsset, uint256(deltaCollateral), maxAmountIn
        );

        uint256 userAssetsIn = borrowAssetsIn - uint256(-deltaBorrow);
        uint256 refundAmount = maxAssetsBorrow - userAssetsIn;

        IERC20(collateralAsset).safeTransfer(user, refundAmount);
        IERC20(vault).safeTransfer(user, uint256(deltaShares));

        IERC20(collateralAsset).forceApprove(collateralFlashLoan, uint256(deltaCollateral));
        IFlashLoanConnector(collateralFlashLoan).returnFlashLoan(collateralAsset, uint256(deltaCollateral));
    }
}
