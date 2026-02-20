// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.28;

import {ILowLevelVault} from "../../interface/ILowLevelVault.sol";
import {IFlashLoanConnector} from "../../interface/IFlashLoanConnector.sol";
import {IExchangeConnector_v0} from "../../interface/IExchangeConnector_v0.sol";
import {SafeERC20, IERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";

contract RedeemWithNegativeFlashLoanCollateral {
    using SafeERC20 for IERC20;
    using SafeERC20 for ILowLevelVault;

    error RedeemWithNegativeFlashLoanCollateralSlippageExceeded(uint256 userAssetsOut, uint256 minAssetsCollateral);

    struct RedeemWithNegativeFlashLoanCollateralInput {
        int256 deltaShares;
        int256 deltaCollateral;
        int256 deltaBorrow;
        address borrowFlashLoan;
        address collateralToBorrowExchange;
        address vault;
        address user;
        address collateralAsset;
        address borrowAsset;
        uint256 minAssetsCollateral;
    }

    struct RedeemWithNegativeFlashLoanCollateralCallbackPayload {
        int256 deltaShares;
        address borrowFlashLoan;
        address collateralToBorrowExchange;
        address vault;
        address user;
        address collateralAsset;
        address borrowAsset;
        uint256 minAssetsCollateral;
        int256 deltaCollateral;
        int256 deltaBorrow;
    }

    function redeemWithNegativeFlashLoanCollateral(
        RedeemWithNegativeFlashLoanCollateralInput memory input
    ) internal returns (uint256) {
        uint256 userCollateralBalance = IERC20(input.collateralAsset).balanceOf(input.user);
        RedeemWithNegativeFlashLoanCollateralCallbackPayload memory payload =
            RedeemWithNegativeFlashLoanCollateralCallbackPayload({
                deltaShares: input.deltaShares,
                borrowFlashLoan: input.borrowFlashLoan,
                collateralToBorrowExchange: input.collateralToBorrowExchange,
                vault: input.vault,
                user: input.user,
                collateralAsset: input.collateralAsset,
                borrowAsset: input.borrowAsset,
                minAssetsCollateral: input.minAssetsCollateral,
                deltaCollateral: input.deltaCollateral,
                deltaBorrow: input.deltaBorrow
            });
        IFlashLoanConnector(input.borrowFlashLoan).flashLoan(
            input.borrowAsset,
            uint256(-input.deltaBorrow),
            abi.encodeCall(RedeemWithNegativeFlashLoanCollateral.redeemWithNegativeFlashLoanCollateralFallback, (payload))
        );

        return IERC20(input.collateralAsset).balanceOf(input.user) - userCollateralBalance;
    }

    function redeemWithNegativeFlashLoanCollateralFallback(
        RedeemWithNegativeFlashLoanCollateralCallbackPayload calldata payload
    ) external {
        IERC20(payload.vault).safeTransferFrom(payload.user, address(this), uint256(-payload.deltaShares));

        IERC20(payload.borrowAsset).forceApprove(payload.vault, uint256(-payload.deltaBorrow));
        ILowLevelVault(payload.vault).executeLowLevelRebalanceShares(payload.deltaShares);

        IERC20(payload.collateralAsset).forceApprove(
            payload.collateralToBorrowExchange, uint256(-payload.deltaCollateral)
        );
        uint256 collateralAssetsIn = IExchangeConnector_v0(payload.collateralToBorrowExchange).exchangeOut(
            payload.collateralAsset, payload.borrowAsset, uint256(-payload.deltaBorrow), uint256(-payload.deltaCollateral)
        );

        uint256 userAssetsOut = uint256(-payload.deltaCollateral) - collateralAssetsIn;
        require(
            userAssetsOut >= payload.minAssetsCollateral,
            RedeemWithNegativeFlashLoanCollateralSlippageExceeded(userAssetsOut, payload.minAssetsCollateral)
        );
        IERC20(payload.collateralAsset).safeTransfer(payload.user, userAssetsOut);

        IERC20(payload.borrowAsset).forceApprove(
            payload.borrowFlashLoan, uint256(-payload.deltaBorrow)
        );
        IFlashLoanConnector(payload.borrowFlashLoan).returnFlashLoan(
            payload.borrowAsset, uint256(-payload.deltaBorrow)
        );
    }
}
