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

    struct RedeemWithNegativeFlashLoanBorrowInput {
        int256 deltaShares;
        int256 deltaCollateral;
        int256 deltaBorrow;
        address borrowFlashLoan;
        address borrowToCollateralExchange;
        address vault;
        address user;
        address collateralAsset;
        address borrowAsset;
        uint256 minAssetsBorrow;
    }

    struct RedeemWithNegativeFlashLoanBorrowCallbackPayload {
        int256 deltaShares;
        address borrowFlashLoan;
        address borrowToCollateralExchange;
        address vault;
        address user;
        address collateralAsset;
        address borrowAsset;
        uint256 minAssetsBorrow;
        int256 deltaCollateral;
        int256 deltaBorrow;
    }

    function redeemWithNegativeFlashLoanBorrow(
        RedeemWithNegativeFlashLoanBorrowInput memory input
    ) internal returns (uint256) {
        uint256 userBorrowBalance = IERC20(input.borrowAsset).balanceOf(input.user);
        RedeemWithNegativeFlashLoanBorrowCallbackPayload memory payload =
            RedeemWithNegativeFlashLoanBorrowCallbackPayload({
                deltaShares: input.deltaShares,
                borrowFlashLoan: input.borrowFlashLoan,
                borrowToCollateralExchange: input.borrowToCollateralExchange,
                vault: input.vault,
                user: input.user,
                collateralAsset: input.collateralAsset,
                borrowAsset: input.borrowAsset,
                minAssetsBorrow: input.minAssetsBorrow,
                deltaCollateral: input.deltaCollateral,
                deltaBorrow: input.deltaBorrow
            });
        IFlashLoanConnector(input.borrowFlashLoan).flashLoan(
            input.borrowAsset,
            uint256(-input.deltaBorrow),
            abi.encodeCall(RedeemWithNegativeFlashLoanBorrow.redeemWithNegativeFlashLoanBorrowFallback, (payload))
        );

        return IERC20(input.borrowAsset).balanceOf(input.user) - userBorrowBalance;
    }

    function redeemWithNegativeFlashLoanBorrowFallback(
        RedeemWithNegativeFlashLoanBorrowCallbackPayload calldata payload
    ) external {
        IERC20(payload.vault).safeTransferFrom(payload.user, address(this), uint256(-payload.deltaShares));

        IERC20(payload.borrowAsset).forceApprove(payload.vault, uint256(-payload.deltaBorrow));
        ILowLevelVault(payload.vault).executeLowLevelRebalanceShares(payload.deltaShares);

        IERC20(payload.collateralAsset).forceApprove(
            payload.borrowToCollateralExchange, uint256(-payload.deltaCollateral)
        );
        uint256 borrowAssetsOut = IExchangeConnector(payload.borrowToCollateralExchange).exchangeIn(
            payload.collateralAsset, payload.borrowAsset, uint256(-payload.deltaCollateral), 0
        );

        uint256 userAssetsIn = borrowAssetsOut - uint256(-payload.deltaBorrow);
        require(
            userAssetsIn >= payload.minAssetsBorrow,
            RedeemWithNegativeFlashLoanBorrowSlippageExceeded(userAssetsIn, payload.minAssetsBorrow)
        );
        IERC20(payload.borrowAsset).safeTransfer(payload.user, userAssetsIn);

        IERC20(payload.borrowAsset).forceApprove(payload.borrowAsset, uint256(-payload.deltaBorrow));
        IFlashLoanConnector(payload.borrowFlashLoan).returnFlashLoan(
            payload.borrowAsset, uint256(-payload.deltaBorrow)
        );
    }
}
