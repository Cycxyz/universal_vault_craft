// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.28;

import {ILowLevelVault} from "../../interface/ILowLevelVault.sol";
import {IFlashLoanConnector} from "../../interface/IFlashLoanConnector.sol";
import {IExchangeConnector} from "../../interface/IExchangeConnector.sol";
import {SafeERC20, IERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";

contract MintWithNegativeFlashLoanBorrow {
    using SafeERC20 for IERC20;
    using SafeERC20 for ILowLevelVault;

    error MintWithNegativeFlashLoanBorrowSlippageExceeded(uint256 userAssetsIn, uint256 maxBorrowAssets);

    function mintWithNegativeFlashLoanBorrow(
        int256 deltaShares,
        int256 deltaCollateral,
        int256 deltaBorrow,
        address borrowFlashLoan,
        address borrowToCollateralExchange,
        address vault,
        address user,
        address collateralAsset,
        address borrowAsset,
        uint256 maxAssetsBorrow
    ) internal returns (uint256) {
        uint256 userBorrowBalance = IERC20(borrowAsset).balanceOf(user);
        IFlashLoanConnector(borrowFlashLoan).flashLoan(
            borrowAsset,
            uint256(-deltaBorrow),
            abi.encodeCall(
                MintWithNegativeFlashLoanBorrow.mintWithNegativeFlashLoanBorrowFallback,
                (
                    deltaShares,
                    borrowFlashLoan,
                    borrowToCollateralExchange,
                    vault,
                    user,
                    collateralAsset,
                    borrowAsset,
                    maxAssetsBorrow,
                    deltaCollateral,
                    deltaBorrow
                )
            )
        );

        return userBorrowBalance - IERC20(borrowAsset).balanceOf(user);
    }

    function mintWithNegativeFlashLoanBorrowFallback(
        int256 deltaShares,
        address borrowFlashLoan,
        address borrowToCollateralExchange,
        address vault,
        address user,
        address collateralAsset,
        address borrowAsset,
        uint256 maxAssetsBorrow,
        int256 deltaCollateral,
        int256 deltaBorrow
    ) external {
        IERC20(borrowAsset).forceApprove(borrowToCollateralExchange, uint256(-deltaBorrow));
        ILowLevelVault(vault).executeLowLevelRebalanceShares(deltaShares);

        IERC20(collateralAsset).forceApprove(borrowToCollateralExchange, uint256(-deltaCollateral));
        uint256 borrowAssetsOut = IExchangeConnector(borrowToCollateralExchange).exchangeIn(
            borrowAsset, collateralAsset, uint256(-deltaCollateral), 0
        );

        uint256 userAssetsIn = borrowAssetsOut - uint256(-deltaBorrow);
        require(
            userAssetsIn <= maxAssetsBorrow,
            MintWithNegativeFlashLoanBorrowSlippageExceeded(userAssetsIn, maxAssetsBorrow)
        );
        IERC20(borrowAsset).safeTransferFrom(user, address(this), userAssetsIn);

        IERC20(vault).safeTransfer(user, uint256(deltaShares));

        IERC20(borrowAsset).forceApprove(borrowAsset, uint256(-deltaBorrow));
        IFlashLoanConnector(borrowFlashLoan).returnFlashLoan(borrowAsset, uint256(-deltaBorrow));
    }
}
