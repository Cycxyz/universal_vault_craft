// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.28;

import {ILowLevelVault} from "../../interface/ILowLevelVault.sol";
import {IFlashLoanConnector} from "../../interface/IFlashLoanConnector.sol";
import {IExchangeConnector_v0} from "../../interface/IExchangeConnector_v0.sol";
import {SafeERC20, IERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";

contract RedeemWithPositiveFlashLoanCollateral {
    using SafeERC20 for IERC20;
    using SafeERC20 for ILowLevelVault;

    error RedeemWithPositiveFlashLoanCollateralSlippageExceeded(uint256 userAssetsOut, uint256 minAssetsCollateral);

    struct RedeemWithPositiveFlashLoanCollateralInput {
        int256 deltaShares;
        int256 deltaCollateral;
        int256 deltaBorrow;
        address collateralFlashLoan;
        address borrowToCollateralExchange;
        address vault;
        address user;
        address collateralAsset;
        address borrowAsset;
        uint256 minAssetsCollateral;
    }

    struct RedeemWithPositiveFlashLoanCollateralCallbackPayload {
        int256 deltaShares;
        address collateralFlashLoan;
        address borrowToCollateralExchange;
        address vault;
        address user;
        address collateralAsset;
        address borrowAsset;
        uint256 minAssetsCollateral;
        int256 deltaCollateral;
        int256 deltaBorrow;
    }

    function redeemWithPositiveFlashLoanCollateral(
        RedeemWithPositiveFlashLoanCollateralInput memory input
    ) internal returns (uint256) {
        uint256 userCollateralBalance = IERC20(input.collateralAsset).balanceOf(input.user);
        RedeemWithPositiveFlashLoanCollateralCallbackPayload memory payload =
            RedeemWithPositiveFlashLoanCollateralCallbackPayload({
                deltaShares: input.deltaShares,
                collateralFlashLoan: input.collateralFlashLoan,
                borrowToCollateralExchange: input.borrowToCollateralExchange,
                vault: input.vault,
                user: input.user,
                collateralAsset: input.collateralAsset,
                borrowAsset: input.borrowAsset,
                minAssetsCollateral: input.minAssetsCollateral,
                deltaCollateral: input.deltaCollateral,
                deltaBorrow: input.deltaBorrow
            });
        IFlashLoanConnector(input.collateralFlashLoan).flashLoan(
            input.collateralAsset,
            uint256(input.deltaCollateral),
            abi.encodeCall(RedeemWithPositiveFlashLoanCollateral.redeemWithPositiveFlashLoanCollateralFallback, (payload))
        );

        return IERC20(input.collateralAsset).balanceOf(input.user) - userCollateralBalance;
    }

    function redeemWithPositiveFlashLoanCollateralFallback(
        RedeemWithPositiveFlashLoanCollateralCallbackPayload calldata payload
    ) external {
        IERC20(payload.vault).safeTransferFrom(payload.user, address(this), uint256(-payload.deltaShares));

        IERC20(payload.collateralAsset).forceApprove(payload.vault, uint256(payload.deltaCollateral));
        ILowLevelVault(payload.vault).executeLowLevelRebalanceShares(payload.deltaShares);

        IERC20(payload.borrowAsset).forceApprove(
            payload.borrowToCollateralExchange, uint256(payload.deltaBorrow)
        );
        uint256 collateralAssetsOut = IExchangeConnector_v0(payload.borrowToCollateralExchange).exchangeIn(
            payload.borrowAsset, payload.collateralAsset, uint256(payload.deltaBorrow), 0
        );

        uint256 userAssetsOut = collateralAssetsOut - uint256(payload.deltaCollateral);
        require(
            userAssetsOut >= payload.minAssetsCollateral,
            RedeemWithPositiveFlashLoanCollateralSlippageExceeded(userAssetsOut, payload.minAssetsCollateral)
        );

        IERC20(payload.collateralAsset).safeTransfer(payload.user, userAssetsOut);

        IERC20(payload.collateralAsset).forceApprove(
            payload.collateralFlashLoan, uint256(payload.deltaCollateral)
        );
        IFlashLoanConnector(payload.collateralFlashLoan).returnFlashLoan(
            payload.collateralAsset, uint256(payload.deltaCollateral)
        );
    }
}
