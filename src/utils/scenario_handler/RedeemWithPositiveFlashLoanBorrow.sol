// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.28;

import {ILowLevelVault} from "../../interface/ILowLevelVault.sol";
import {IFlashLoanConnector} from "../../interface/IFlashLoanConnector.sol";
import {IExchangeConnector} from "../../interface/IExchangeConnector.sol";
import {SafeERC20, IERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";

contract RedeemWithPositiveFlashLoanBorrow {
    using SafeERC20 for IERC20;
    using SafeERC20 for ILowLevelVault;

    error RedeemWithPositiveFlashLoanBorrowSlippageExceeded(uint256 userAssetsOut, uint256 minAssetsBorrow);

    function redeemWithPositiveFlashLoanBorrow(
        int256 deltaShares,
        int256 deltaCollateral,
        int256 deltaBorrow,
        address collateralFlashLoan,
        address borrowToCollateralExchange,
        address vault,
        address user,
        address collateralAsset,
        address borrowAsset,
        uint256 minAssetsBorrow
    ) internal returns (uint256) {
        uint256 userBorrowBalance = IERC20(borrowAsset).balanceOf(user);
        IFlashLoanConnector(collateralFlashLoan).flashLoan(
            collateralAsset,
            uint256(deltaCollateral),
            abi.encodeCall(
                RedeemWithPositiveFlashLoanBorrow.redeemWithPositiveFlashLoanBorrowFallback,
                (
                    deltaShares,
                    collateralFlashLoan,
                    borrowToCollateralExchange,
                    vault,
                    user,
                    collateralAsset,
                    borrowAsset,
                    minAssetsBorrow,
                    deltaCollateral,
                    deltaBorrow
                )
            )
        );

        return IERC20(borrowAsset).balanceOf(user) - userBorrowBalance;
    }

    function redeemWithPositiveFlashLoanBorrowFallback(
        int256 deltaShares,
        address collateralFlashLoan,
        address borrowToCollateralExchange,
        address vault,
        address user,
        address collateralAsset,
        address borrowAsset,
        uint256 minAssetsBorrow,
        int256 deltaCollateral,
        int256 deltaBorrow
    ) external {
        IERC20(vault).safeTransferFrom(user, address(this), uint256(-deltaShares));

        IERC20(collateralAsset).forceApprove(vault, uint256(deltaCollateral));
        ILowLevelVault(vault).executeLowLevelRebalanceShares(deltaShares);

        IERC20(borrowAsset).forceApprove(borrowToCollateralExchange, uint256(deltaBorrow));
        uint256 borrowAssetsIn = IExchangeConnector(borrowToCollateralExchange).exchangeOut(
            borrowAsset, collateralAsset, uint256(deltaCollateral), uint256(deltaBorrow)
        );

        uint256 userAssetsOut = uint256(deltaBorrow) - borrowAssetsIn;
        require(
            userAssetsOut >= minAssetsBorrow,
            RedeemWithPositiveFlashLoanBorrowSlippageExceeded(userAssetsOut, minAssetsBorrow)
        );

        IERC20(borrowAsset).safeTransfer(user, userAssetsOut);

        IERC20(collateralAsset).forceApprove(collateralFlashLoan, uint256(deltaCollateral));
        IFlashLoanConnector(collateralFlashLoan).returnFlashLoan(collateralAsset, uint256(deltaCollateral));
    }
}
