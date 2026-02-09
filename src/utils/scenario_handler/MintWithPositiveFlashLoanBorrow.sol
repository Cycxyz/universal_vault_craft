// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.28;

import {ILowLevelVault} from "../../interface/ILowLevelVault.sol";
import {IFlashLoanConnector} from "../../interface/IFlashLoanConnector.sol";
import {IExchangeConnector} from "../../interface/IExchangeConnector.sol";
import {SafeERC20, IERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";

contract MintWithPositiveFlashLoanBorrow {
    using SafeERC20 for IERC20;
    using SafeERC20 for ILowLevelVault;

    struct MintWithPositiveFlashLoanBorrowInput {
        int256 deltaShares;
        int256 deltaCollateral;
        int256 deltaBorrow;
        address collateralFlashLoan;
        address borrowToCollateralExchange;
        address vault;
        address user;
        address collateralAsset;
        address borrowAsset;
        uint256 maxAssetsBorrow;
    }

    struct MintWithPositiveFlashLoanBorrowCallbackPayload {
        int256 deltaShares;
        address collateralFlashLoan;
        address borrowToCollateralExchange;
        address vault;
        address user;
        address collateralAsset;
        address borrowAsset;
        uint256 maxAssetsBorrow;
        int256 deltaCollateral;
        int256 deltaBorrow;
    }

    function mintWithPositiveFlashLoanBorrow(
        MintWithPositiveFlashLoanBorrowInput memory input
    ) internal returns (uint256) {
        uint256 userBorrowBalance = IERC20(input.borrowAsset).balanceOf(input.user);
        MintWithPositiveFlashLoanBorrowCallbackPayload memory payload =
            MintWithPositiveFlashLoanBorrowCallbackPayload({
                deltaShares: input.deltaShares,
                collateralFlashLoan: input.collateralFlashLoan,
                borrowToCollateralExchange: input.borrowToCollateralExchange,
                vault: input.vault,
                user: input.user,
                collateralAsset: input.collateralAsset,
                borrowAsset: input.borrowAsset,
                maxAssetsBorrow: input.maxAssetsBorrow,
                deltaCollateral: input.deltaCollateral,
                deltaBorrow: input.deltaBorrow
            });
        IFlashLoanConnector(input.collateralFlashLoan).flashLoan(
            input.collateralAsset,
            uint256(input.deltaCollateral),
            abi.encodeCall(MintWithPositiveFlashLoanBorrow.mintWithPositiveFlashLoanBorrowFallback, (payload))
        );

        return userBorrowBalance - IERC20(input.borrowAsset).balanceOf(input.user);
    }

    function mintWithPositiveFlashLoanBorrowFallback(
        MintWithPositiveFlashLoanBorrowCallbackPayload calldata payload
    ) external {
        IERC20(payload.collateralAsset).forceApprove(payload.vault, uint256(payload.deltaCollateral));
        ILowLevelVault(payload.vault).executeLowLevelRebalanceShares(payload.deltaShares);

        IERC20(payload.borrowAsset).safeTransferFrom(payload.user, address(this), payload.maxAssetsBorrow);
        uint256 maxAmountIn = uint256(payload.deltaBorrow) + payload.maxAssetsBorrow;
        IERC20(payload.borrowAsset).forceApprove(payload.borrowToCollateralExchange, maxAmountIn);
        uint256 borrowAssetsIn = IExchangeConnector(payload.borrowToCollateralExchange).exchangeOut(
            payload.borrowAsset, payload.collateralAsset, uint256(payload.deltaCollateral), maxAmountIn
        );

        uint256 userAssetsIn = borrowAssetsIn - uint256(payload.deltaBorrow);
        uint256 refundAmount = payload.maxAssetsBorrow - userAssetsIn;

        IERC20(payload.borrowAsset).safeTransfer(payload.user, refundAmount);
        IERC20(payload.vault).safeTransfer(payload.user, uint256(payload.deltaShares));

        IERC20(payload.collateralAsset).forceApprove(
            payload.collateralFlashLoan, uint256(payload.deltaCollateral)
        );
        IFlashLoanConnector(payload.collateralFlashLoan).returnFlashLoan(
            payload.collateralAsset, uint256(payload.deltaCollateral)
        );
    }
}
