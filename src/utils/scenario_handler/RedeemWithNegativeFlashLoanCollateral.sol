// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.28;

import {ILowLevelVault} from "../../interface/ILowLevelVault.sol";
import {IFlashLoanConnector} from "../../interface/IFlashLoanConnector.sol";
import {IExchangeConnector} from "../../interface/IExchangeConnector.sol";
import {SafeERC20, IERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";

contract RedeemWithNegativeFlashLoanCollateral {
    using SafeERC20 for IERC20;
    using SafeERC20 for ILowLevelVault;

    error RedeemWithNegativeFlashLoanCollateralSlippageExceeded(uint256 userAssetsOut, uint256 minAssetsCollateral);

    function redeemWithNegativeFlashLoanCollateral(
        int256 deltaShares,
        int256 deltaCollateral,
        int256 deltaBorrow,
        address borrowFlashLoan,
        address borrowToCollateralExchange,
        address vault,
        address user,
        address collateralAsset,
        address borrowAsset,
        uint256 minAssetsCollateral
    ) internal returns (uint256) {
        uint256 userCollateralBalance = IERC20(collateralAsset).balanceOf(user);
        IFlashLoanConnector(borrowFlashLoan).flashLoan(
            borrowAsset,
            uint256(-deltaBorrow),
            abi.encodeCall(
                RedeemWithNegativeFlashLoanCollateral.redeemWithNegativeFlashLoanCollateralFallback,
                (
                    deltaShares,
                    borrowFlashLoan,
                    borrowToCollateralExchange,
                    vault,
                    user,
                    collateralAsset,
                    borrowAsset,
                    minAssetsCollateral,
                    deltaCollateral,
                    deltaBorrow
                )
            )
        );

        return IERC20(collateralAsset).balanceOf(user) - userCollateralBalance;
    }

    function redeemWithNegativeFlashLoanCollateralFallback(
        int256 deltaShares,
        address borrowFlashLoan,
        address collateralToBorrowExchange,
        address vault,
        address user,
        address collateralAsset,
        address borrowAsset,
        uint256 minAssetsCollateral,
        int256 deltaCollateral,
        int256 deltaBorrow
    ) external {
        IERC20(vault).safeTransferFrom(user, address(this), uint256(-deltaShares));

        IERC20(borrowAsset).forceApprove(vault, uint256(-deltaBorrow));
        ILowLevelVault(vault).executeLowLevelRebalanceShares(deltaShares);

        IERC20(borrowAsset).forceApprove(collateralToBorrowExchange, uint256(-deltaBorrow));
        uint256 collateralAssetsIn = IExchangeConnector(collateralToBorrowExchange).exchangeOut(
            borrowAsset, collateralAsset, uint256(-deltaBorrow), uint256(-deltaCollateral)
        );

        uint256 userAssetsOut = uint256(-deltaCollateral) - collateralAssetsIn;
        require(
            userAssetsOut >= minAssetsCollateral,
            RedeemWithNegativeFlashLoanCollateralSlippageExceeded(userAssetsOut, minAssetsCollateral)
        );
        IERC20(collateralAsset).safeTransfer(user, userAssetsOut);

        IERC20(borrowAsset).forceApprove(borrowFlashLoan, uint256(-deltaBorrow));
        IFlashLoanConnector(borrowFlashLoan).returnFlashLoan(borrowAsset, uint256(-deltaBorrow));
    }
}
