// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.28;

import {ILowLevelVault} from "../../interface/ILowLevelVault.sol";
import {IFlashLoanConnector} from "../../interface/IFlashLoanConnector.sol";
import {IExchangeConnector} from "../../interface/IExchangeConnector.sol";
import {SafeERC20, IERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";

contract MintWithNegativeFlashLoanCollateral {
    using SafeERC20 for IERC20;
    using SafeERC20 for ILowLevelVault;

    struct MintWithNegativeFlashLoanCollateralInput {
        int256 deltaShares;
        int256 deltaCollateral;
        int256 deltaBorrow;
        address borrowFlashLoan;
        address collateralToBorrowExchange;
        address vault;
        address user;
        address collateralAsset;
        address borrowAsset;
        uint256 maxAssetsCollateral;
    }

    struct MintWithNegativeFlashLoanCallbackPayload {
        int256 deltaShares;
        address borrowFlashLoan;
        address collateralToBorrowExchange;
        address vault;
        address user;
        address collateralAsset;
        address borrowAsset;
        uint256 maxAssetsCollateral;
        int256 deltaCollateral;
        int256 deltaBorrow;
    }

    function mintWithNegativeFlashLoanCollateral(
        MintWithNegativeFlashLoanCollateralInput memory input
    ) internal returns (uint256) {
        uint256 userCollateralBalance = IERC20(input.collateralAsset).balanceOf(input.user);
        MintWithNegativeFlashLoanCallbackPayload memory payload = MintWithNegativeFlashLoanCallbackPayload({
            deltaShares: input.deltaShares,
            borrowFlashLoan: input.borrowFlashLoan,
            collateralToBorrowExchange: input.collateralToBorrowExchange,
            vault: input.vault,
            user: input.user,
            collateralAsset: input.collateralAsset,
            borrowAsset: input.borrowAsset,
            maxAssetsCollateral: input.maxAssetsCollateral,
            deltaCollateral: input.deltaCollateral,
            deltaBorrow: input.deltaBorrow
        });
        IFlashLoanConnector(input.borrowFlashLoan).flashLoan(
            input.borrowAsset,
            uint256(-input.deltaBorrow),
            abi.encodeCall(MintWithNegativeFlashLoanCollateral.mintWithNegativeFlashLoanCollateralFallback, (payload))
        );

        return userCollateralBalance - IERC20(input.collateralAsset).balanceOf(input.user);
    }

    function mintWithNegativeFlashLoanCollateralFallback(
        MintWithNegativeFlashLoanCallbackPayload calldata payload
    ) external {
        IERC20(payload.borrowAsset).forceApprove(
            payload.collateralToBorrowExchange, uint256(-payload.deltaBorrow)
        );
        ILowLevelVault(payload.vault).executeLowLevelRebalanceShares(payload.deltaShares);

        IERC20(payload.borrowAsset).safeTransferFrom(
            payload.user, address(this), payload.maxAssetsCollateral
        );

        uint256 maxAmountIn = uint256(-payload.deltaCollateral) + payload.maxAssetsCollateral;
        IERC20(payload.collateralAsset).forceApprove(
            payload.collateralToBorrowExchange, maxAmountIn
        );
        uint256 collateralAssetsIn = IExchangeConnector(payload.collateralToBorrowExchange).exchangeOut(
            payload.collateralAsset,
            payload.borrowAsset,
            uint256(-payload.deltaBorrow),
            maxAmountIn
        );

        uint256 userAssetsIn = collateralAssetsIn - uint256(-payload.deltaCollateral);
        uint256 refundAmount = payload.maxAssetsCollateral - userAssetsIn;
        IERC20(payload.collateralAsset).safeTransfer(payload.user, refundAmount);

        IERC20(payload.vault).safeTransfer(payload.user, uint256(payload.deltaShares));

        IERC20(payload.borrowAsset).forceApprove(
            payload.borrowFlashLoan, uint256(-payload.deltaBorrow)
        );
        IFlashLoanConnector(payload.borrowFlashLoan).returnFlashLoan(
            payload.borrowAsset, uint256(-payload.deltaBorrow)
        );
    }
}
