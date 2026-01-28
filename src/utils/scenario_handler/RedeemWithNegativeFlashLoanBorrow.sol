// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.28;

import {ILowLevelVault} from "../../interface/ILowLevelVault.sol";
import {IFlashLoanConnector} from "../../interface/IFlashLoanConnector.sol";
import {IExchangeConnector} from "../../interface/IExchangeConnector.sol";
import {SafeERC20, IERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";

contract RedeemWithNegativeFlashLoanBorrow {
    using SafeERC20 for IERC20;
    using SafeERC20 for ILowLevelVault;

    error RedeemWithNegativeFlashLoanBorrowSlippageExceeded(uint256 userAssetsIn, uint256 maxBorrowAssets);

    function redeemWithNegativeFlashLoanBorrow(
        int256 deltaShares,
        int256 deltaCollateral,
        int256 deltaBorrow,
        address borrowFlashLoan,
        address borrowToCollateralExchange,
        address vault,
        address user,
        address collateralAsset,
        address borrowAsset,
        uint256 minAssetsBorrow
    ) internal returns (uint256) {
        uint256 userBorrowBalance = IERC20(borrowAsset).balanceOf(user);
        IFlashLoanConnector(borrowFlashLoan).flashLoan(
            borrowAsset,
            uint256(-deltaBorrow),
            abi.encodeCall(
                RedeemWithNegativeFlashLoanBorrow.redeemWithNegativeFlashLoanBorrowFallback,
                (
                    deltaShares,
                    borrowFlashLoan,
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

    function redeemWithNegativeFlashLoanBorrowFallback(
        int256 deltaShares,
        address borrowFlashLoan,
        address collateralToBorrowExchange,
        address vault,
        address user,
        address collateralAsset,
        address borrowAsset,
        uint256 minAssetsBorrow,
        int256 deltaCollateral,
        int256 deltaBorrow
    ) external {
        IERC20(vault).safeTransferFrom(user, address(this), uint256(-deltaShares));

        IERC20(borrowAsset).forceApprove(vault, uint256(-deltaBorrow));
        ILowLevelVault(vault).executeLowLevelRebalanceShares(deltaShares);

        IERC20(collateralAsset).forceApprove(collateralToBorrowExchange, uint256(-deltaCollateral));
        uint256 borrowAssetsOut = IExchangeConnector(collateralToBorrowExchange).exchangeIn(
            collateralAsset, borrowAsset, uint256(-deltaCollateral), 0
        );

        uint256 userAssetsIn = borrowAssetsOut - uint256(-deltaBorrow);
        require(
            userAssetsIn >= minAssetsBorrow,
            RedeemWithNegativeFlashLoanBorrowSlippageExceeded(userAssetsIn, minAssetsBorrow)
        );
        IERC20(borrowAsset).safeTransfer(user, userAssetsIn);

        IERC20(borrowAsset).forceApprove(borrowAsset, uint256(-deltaBorrow));
        IFlashLoanConnector(borrowFlashLoan).returnFlashLoan(borrowAsset, uint256(-deltaBorrow));
    }
}
