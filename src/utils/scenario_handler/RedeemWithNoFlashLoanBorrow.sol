// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.28;

import {ILowLevelVault} from "../../interface/ILowLevelVault.sol";
import {IExchangeConnector} from "../../interface/IExchangeConnector.sol";
import {SafeERC20, IERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";

contract RedeemWithNoFlashLoanBorrow {
    using SafeERC20 for IERC20;
    using SafeERC20 for ILowLevelVault;

    error RedeemWithNoFlashLoanBorrowSlippageExceeded(uint256 userAssetsOut, uint256 minAssetsBorrow);

    struct RedeemWithNoFlashLoanBorrowInput {
        int256 deltaShares;
        int256 deltaCollateral;
        int256 deltaBorrow;
        address collateralToBorrowExchange;
        address vault;
        address user;
        address collateralAsset;
        address borrowAsset;
        uint256 minAssetsBorrow;
    }

    function redeemWithNoFlashLoanBorrow(
        RedeemWithNoFlashLoanBorrowInput memory input
    ) internal returns (uint256) {
        IERC20(input.vault).safeTransferFrom(input.user, address(this), uint256(-input.deltaShares));
        ILowLevelVault(input.vault).executeLowLevelRebalanceShares(input.deltaShares);

        IERC20(input.collateralAsset).forceApprove(
            input.collateralToBorrowExchange, uint256(-input.deltaCollateral)
        );
        uint256 borrowAssetsOut = IExchangeConnector(input.collateralToBorrowExchange).exchangeIn(
            input.collateralAsset, input.borrowAsset, uint256(-input.deltaCollateral), 0
        );

        uint256 userAssetsOut = borrowAssetsOut + uint256(input.deltaBorrow);
        require(
            userAssetsOut >= input.minAssetsBorrow,
            RedeemWithNoFlashLoanBorrowSlippageExceeded(userAssetsOut, input.minAssetsBorrow)
        );

        IERC20(input.borrowAsset).forceApprove(input.vault, uint256(-input.deltaBorrow));
        IERC20(input.borrowAsset).safeTransfer(input.user, userAssetsOut);
        return userAssetsOut;
    }
}
