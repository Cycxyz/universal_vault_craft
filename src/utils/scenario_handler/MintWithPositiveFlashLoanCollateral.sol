// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.28;

import {ILowLevelVault} from "../../interface/ILowLevelVault.sol";
import {IFlashLoanConnector} from "../../interface/IFlashLoanConnector.sol";
import {IExchangeConnector} from "../../interface/IExchangeConnector.sol";
import {SafeERC20, IERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";

contract MintWithPositiveFlashLoanCollateral {
    using SafeERC20 for IERC20;
    using SafeERC20 for ILowLevelVault;

    error MintWithPositiveFlashLoanCollateralSlippageExceeded(uint256 userAssetsIn, uint256 maxCollateralAssets);

    function mintWithPositiveFlashLoanCollateral(
        int256 deltaShares,
        int256 deltaCollateral,
        int256 deltaBorrow,
        address collateralFlashLoan,
        address borrowToCollateralExchange,
        address vault,
        address user,
        address collateralAsset,
        address borrowAsset,
        uint256 maxAssets
    ) internal returns (uint256) {
        uint256 userCollateralBalance = IERC20(collateralAsset).balanceOf(user);
        IFlashLoanConnector(collateralFlashLoan).flashLoan(
            collateralAsset,
            uint256(deltaCollateral),
            abi.encodeCall(
                MintWithPositiveFlashLoanCollateral.mintWithPositiveFlashLoanCollateralFallback,
                (
                    deltaShares,
                    collateralFlashLoan,
                    borrowToCollateralExchange,
                    vault,
                    user,
                    collateralAsset,
                    borrowAsset,
                    maxAssets,
                    deltaCollateral,
                    deltaBorrow
                )
            )
        );

        return userCollateralBalance - IERC20(collateralAsset).balanceOf(user);
    }

    function mintWithPositiveFlashLoanCollateralFallback(
        int256 deltaShares,
        address collateralFlashLoan,
        address borrowToCollateralExchange,
        address vault,
        address user,
        address collateralAsset,
        address borrowAsset,
        uint256 maxAssets,
        int256 deltaCollateral,
        int256 deltaBorrow
    ) external {
        IERC20(collateralAsset).forceApprove(vault, uint256(deltaCollateral));
        ILowLevelVault(vault).executeLowLevelRebalanceShares(deltaShares);

        IERC20(borrowAsset).forceApprove(borrowToCollateralExchange, uint256(deltaBorrow));
        uint256 collateralAssetsOut = IExchangeConnector(borrowToCollateralExchange).exchangeIn(
            borrowAsset, collateralAsset, uint256(deltaBorrow), 0
        );
        uint256 userAssetsIn = uint256(deltaCollateral) - collateralAssetsOut;
        require(userAssetsIn <= maxAssets, MintWithPositiveFlashLoanCollateralSlippageExceeded(userAssetsIn, maxAssets));
        IERC20(collateralAsset).safeTransferFrom(user, address(this), userAssetsIn);

        IERC20(vault).safeTransfer(user, uint256(deltaShares));
        IERC20(borrowAsset).forceApprove(collateralFlashLoan, uint256(deltaCollateral));
        IFlashLoanConnector(collateralFlashLoan).returnFlashLoan(collateralAsset, uint256(deltaCollateral));
    }
}
