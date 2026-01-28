// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.28;

import {ILowLevelVault} from "../../interface/ILowLevelVault.sol";
import {IExchangeConnector} from "../../interface/IExchangeConnector.sol";
import {SafeERC20, IERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";

contract MintWithNoFlashLoanBorrow {
    using SafeERC20 for IERC20;

    error MintWithNoFlashLoanBorrowSlippageExceeded(uint256 userAssetsIn, uint256 maxBorrowAssets);

    function mintWithNoFlashLoanBorrow(
        int256 deltaShares,
        int256 deltaCollateral,
        int256 deltaBorrow,
        address borrowToCollateralExchange,
        address vault,
        address user,
        address collateralAsset,
        address borrowAsset,
        uint256 maxAssetsBorrow
    ) internal returns (uint256) {
        IERC20(borrowAsset).safeTransferFrom(user, address(this), maxAssetsBorrow);

        IERC20(borrowAsset).forceApprove(borrowToCollateralExchange, maxAssetsBorrow);
        uint256 borrowAssetsIn = IExchangeConnector(borrowToCollateralExchange).exchangeOut(
            borrowAsset, collateralAsset, uint256(deltaCollateral), maxAssetsBorrow
        );

        uint256 borrowAssetsNeeded = borrowAssetsIn + uint256(-deltaBorrow);
        require(
            borrowAssetsNeeded <= maxAssetsBorrow,
            MintWithNoFlashLoanBorrowSlippageExceeded(borrowAssetsNeeded, maxAssetsBorrow)
        );
        IERC20(borrowAsset).forceApprove(vault, uint256(-deltaBorrow));
        IERC20(collateralAsset).forceApprove(vault, uint256(deltaCollateral));
        ILowLevelVault(vault).executeLowLevelRebalanceShares(deltaShares);

        IERC20(vault).safeTransfer(user, uint256(deltaShares));
        return borrowAssetsNeeded;
    }
}
