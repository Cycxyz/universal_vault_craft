// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.28;

import {ILowLevelVault} from "../../interface/ILowLevelVault.sol";
import {IFlashLoanConnector} from "../../interface/IFlashLoanConnector.sol";
import {IExchangeConnector_v0} from "../../interface/IExchangeConnector_v0.sol";
import {SafeERC20, IERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";

contract MintWithPositiveFlashLoanCollateral {
    using SafeERC20 for IERC20;
    using SafeERC20 for ILowLevelVault;

    error MintWithPositiveFlashLoanCollateralSlippageExceeded(uint256 userAssetsIn, uint256 maxCollateralAssets);

    struct MintWithPositiveFlashLoanCollateralInput {
        int256 deltaShares;
        int256 deltaCollateral;
        int256 deltaBorrow;
        address collateralFlashLoan;
        address borrowToCollateralExchange;
        address vault;
        address user;
        address collateralAsset;
        address borrowAsset;
        uint256 maxAssets;
    }

    struct MintWithPositiveFlashLoanCollateralCallbackPayload {
        int256 deltaShares;
        address collateralFlashLoan;
        address borrowToCollateralExchange;
        address vault;
        address user;
        address collateralAsset;
        address borrowAsset;
        uint256 maxAssets;
        int256 deltaCollateral;
        int256 deltaBorrow;
    }

    function mintWithPositiveFlashLoanCollateral(
        MintWithPositiveFlashLoanCollateralInput memory input
    ) internal returns (uint256) {
        uint256 userCollateralBalance = IERC20(input.collateralAsset).balanceOf(input.user);
        MintWithPositiveFlashLoanCollateralCallbackPayload memory payload =
            MintWithPositiveFlashLoanCollateralCallbackPayload({
                deltaShares: input.deltaShares,
                collateralFlashLoan: input.collateralFlashLoan,
                borrowToCollateralExchange: input.borrowToCollateralExchange,
                vault: input.vault,
                user: input.user,
                collateralAsset: input.collateralAsset,
                borrowAsset: input.borrowAsset,
                maxAssets: input.maxAssets,
                deltaCollateral: input.deltaCollateral,
                deltaBorrow: input.deltaBorrow
            });
        IFlashLoanConnector(input.collateralFlashLoan).flashLoan(
            input.collateralAsset,
            uint256(input.deltaCollateral),
            abi.encodeCall(MintWithPositiveFlashLoanCollateral.mintWithPositiveFlashLoanCollateralFallback, (payload))
        );

        return userCollateralBalance - IERC20(input.collateralAsset).balanceOf(input.user);
    }

    function mintWithPositiveFlashLoanCollateralFallback(
        MintWithPositiveFlashLoanCollateralCallbackPayload calldata payload
    ) external {
        IERC20(payload.collateralAsset).forceApprove(payload.vault, uint256(payload.deltaCollateral));
        ILowLevelVault(payload.vault).executeLowLevelRebalanceShares(payload.deltaShares);

        IERC20(payload.borrowAsset).forceApprove(
            payload.borrowToCollateralExchange, uint256(payload.deltaBorrow)
        );
        uint256 collateralAssetsOut = IExchangeConnector_v0(payload.borrowToCollateralExchange).exchangeIn(
            payload.borrowAsset, payload.collateralAsset, uint256(payload.deltaBorrow), 0
        );
        uint256 userAssetsIn = uint256(payload.deltaCollateral) - collateralAssetsOut;
        require(
            userAssetsIn <= payload.maxAssets,
            MintWithPositiveFlashLoanCollateralSlippageExceeded(userAssetsIn, payload.maxAssets)
        );
        IERC20(payload.collateralAsset).safeTransferFrom(payload.user, address(this), userAssetsIn);

        IERC20(payload.vault).safeTransfer(payload.user, uint256(payload.deltaShares));
        IERC20(payload.collateralAsset).forceApprove(
            payload.collateralFlashLoan, uint256(payload.deltaCollateral)
        );
        IFlashLoanConnector(payload.collateralFlashLoan).returnFlashLoan(
            payload.collateralAsset, uint256(payload.deltaCollateral)
        );
    }
}
