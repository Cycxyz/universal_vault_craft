// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.28;

import {ILowLevelVault} from "../../interface/ILowLevelVault.sol";
import {IExchangeConnector_v0} from "../../interface/IExchangeConnector_v0.sol";
import {SafeERC20, IERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";

contract MintWithNoFlashLoanBorrow {
    using SafeERC20 for IERC20;

    error MintWithNoFlashLoanBorrowSlippageExceeded(uint256 userAssetsIn, uint256 maxBorrowAssets);

    struct MintWithNoFlashLoanBorrowInput {
        int256 deltaShares;
        int256 deltaCollateral;
        int256 deltaBorrow;
        address borrowToCollateralExchange;
        address vault;
        address user;
        address collateralAsset;
        address borrowAsset;
        uint256 maxAssetsBorrow;
    }

    function mintWithNoFlashLoanBorrow(
        MintWithNoFlashLoanBorrowInput memory input
    ) internal returns (uint256) {
        IERC20(input.borrowAsset).safeTransferFrom(input.user, address(this), input.maxAssetsBorrow);

        IERC20(input.borrowAsset).forceApprove(input.borrowToCollateralExchange, input.maxAssetsBorrow);
        uint256 borrowAssetsIn = IExchangeConnector_v0(input.borrowToCollateralExchange).exchangeOut(
            input.borrowAsset, input.collateralAsset, uint256(input.deltaCollateral), input.maxAssetsBorrow
        );

        uint256 borrowAssetsNeeded = borrowAssetsIn + uint256(-input.deltaBorrow);
        require(
            borrowAssetsNeeded <= input.maxAssetsBorrow,
            MintWithNoFlashLoanBorrowSlippageExceeded(borrowAssetsNeeded, input.maxAssetsBorrow)
        );
        IERC20(input.borrowAsset).forceApprove(input.vault, uint256(-input.deltaBorrow));
        IERC20(input.collateralAsset).forceApprove(input.vault, uint256(input.deltaCollateral));
        ILowLevelVault(input.vault).executeLowLevelRebalanceShares(input.deltaShares);

        IERC20(input.vault).safeTransfer(input.user, uint256(input.deltaShares));
        return borrowAssetsNeeded;
    }
}
