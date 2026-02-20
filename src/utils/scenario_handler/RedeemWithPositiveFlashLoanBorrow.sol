// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.28;

import {ILowLevelVault} from "../../interface/ILowLevelVault.sol";
import {IFlashLoanConnector} from "../../interface/IFlashLoanConnector.sol";
import {IExchangeConnector_v0} from "../../interface/IExchangeConnector_v0.sol";
import {SafeERC20, IERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";

contract RedeemWithPositiveFlashLoanBorrow {
    using SafeERC20 for IERC20;
    using SafeERC20 for ILowLevelVault;

    error RedeemWithPositiveFlashLoanBorrowSlippageExceeded(uint256 userAssetsOut, uint256 minAssetsBorrow);

    struct RedeemWithPositiveFlashLoanBorrowInput {
        int256 deltaShares;
        int256 deltaCollateral;
        int256 deltaBorrow;
        address collateralFlashLoan;
        address borrowToCollateralExchange;
        address vault;
        address user;
        address collateralAsset;
        address borrowAsset;
        uint256 minAssetsBorrow;
    }

    struct RedeemWithPositiveFlashLoanBorrowCallbackPayload {
        int256 deltaShares;
        address collateralFlashLoan;
        address borrowToCollateralExchange;
        address vault;
        address user;
        address collateralAsset;
        address borrowAsset;
        uint256 minAssetsBorrow;
        int256 deltaCollateral;
        int256 deltaBorrow;
    }

    function redeemWithPositiveFlashLoanBorrow(
        RedeemWithPositiveFlashLoanBorrowInput memory input
    ) internal returns (uint256) {
        uint256 userBorrowBalance = IERC20(input.borrowAsset).balanceOf(input.user);
        RedeemWithPositiveFlashLoanBorrowCallbackPayload memory payload =
            RedeemWithPositiveFlashLoanBorrowCallbackPayload({
                deltaShares: input.deltaShares,
                collateralFlashLoan: input.collateralFlashLoan,
                borrowToCollateralExchange: input.borrowToCollateralExchange,
                vault: input.vault,
                user: input.user,
                collateralAsset: input.collateralAsset,
                borrowAsset: input.borrowAsset,
                minAssetsBorrow: input.minAssetsBorrow,
                deltaCollateral: input.deltaCollateral,
                deltaBorrow: input.deltaBorrow
            });
        IFlashLoanConnector(input.collateralFlashLoan).flashLoan(
            input.collateralAsset,
            uint256(input.deltaCollateral),
            abi.encodeCall(RedeemWithPositiveFlashLoanBorrow.redeemWithPositiveFlashLoanBorrowFallback, (payload))
        );

        return IERC20(input.borrowAsset).balanceOf(input.user) - userBorrowBalance;
    }

    function redeemWithPositiveFlashLoanBorrowFallback(
        RedeemWithPositiveFlashLoanBorrowCallbackPayload calldata payload
    ) external {
        IERC20(payload.vault).safeTransferFrom(payload.user, address(this), uint256(-payload.deltaShares));

        IERC20(payload.collateralAsset).forceApprove(payload.vault, uint256(payload.deltaCollateral));
        ILowLevelVault(payload.vault).executeLowLevelRebalanceShares(payload.deltaShares);

        IERC20(payload.borrowAsset).forceApprove(
            payload.borrowToCollateralExchange, uint256(payload.deltaBorrow)
        );
        uint256 borrowAssetsIn = IExchangeConnector_v0(payload.borrowToCollateralExchange).exchangeOut(
            payload.borrowAsset, payload.collateralAsset, uint256(payload.deltaCollateral), uint256(payload.deltaBorrow)
        );

        uint256 userAssetsOut = uint256(payload.deltaBorrow) - borrowAssetsIn;
        require(
            userAssetsOut >= payload.minAssetsBorrow,
            RedeemWithPositiveFlashLoanBorrowSlippageExceeded(userAssetsOut, payload.minAssetsBorrow)
        );

        IERC20(payload.borrowAsset).safeTransfer(payload.user, userAssetsOut);

        IERC20(payload.collateralAsset).forceApprove(
            payload.collateralFlashLoan, uint256(payload.deltaCollateral)
        );
        IFlashLoanConnector(payload.collateralFlashLoan).returnFlashLoan(
            payload.collateralAsset, uint256(payload.deltaCollateral)
        );
    }
}
