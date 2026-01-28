// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.28;

import {ILowLevelVault} from "../../interface/ILowLevelVault.sol";
import {IExchangeConnector} from "../../interface/IExchangeConnector.sol";
import {SafeERC20, IERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";

contract RedeemWithNoFlashLoanBorrow {
    using SafeERC20 for IERC20;
    using SafeERC20 for ILowLevelVault;

    error RedeemWithNoFlashLoanBorrowSlippageExceeded(uint256 userAssetsOut, uint256 minAssetsBorrow);

    function redeemWithNoFlashLoanBorrow(
        int256 deltaShares,
        int256 deltaCollateral,
        int256 deltaBorrow,
        address collateralToBorrowExchange,
        address vault,
        address user,
        address collateralAsset,
        address borrowAsset,
        uint256 minAssetsBorrow
    ) internal returns (uint256) {
        IERC20(vault).safeTransferFrom(user, address(this), uint256(-deltaShares));
        ILowLevelVault(vault).executeLowLevelRebalanceShares(deltaShares);

        IERC20(collateralAsset).forceApprove(collateralToBorrowExchange, uint256(-deltaCollateral));
        uint256 borrowAssetsOut = IExchangeConnector(collateralToBorrowExchange).exchangeIn(
            collateralAsset, borrowAsset, uint256(-deltaCollateral), 0
        );

        uint256 userAssetsOut = borrowAssetsOut + uint256(deltaBorrow);
        require(
            userAssetsOut >= minAssetsBorrow,
            RedeemWithNoFlashLoanBorrowSlippageExceeded(userAssetsOut, minAssetsBorrow)
        );

        IERC20(borrowAsset).forceApprove(vault, uint256(-deltaBorrow));
        IERC20(borrowAsset).safeTransfer(user, userAssetsOut);
        return userAssetsOut;
    }
}
