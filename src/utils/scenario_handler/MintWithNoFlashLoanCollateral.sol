// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.28;

import {ILowLevelVault} from "../../interface/ILowLevelVault.sol";
import {IExchangeConnector} from "../../interface/IExchangeConnector.sol";
import {SafeERC20, IERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";

contract MintWithNoFlashLoanCollateral {
    using SafeERC20 for IERC20;

    error MintWithNoFlashLoanCollateralSlippageExceeded(uint256 userAssetsIn, uint256 maxCollateralAssets);

    struct MintWithNoFlashLoanCollateralInput {
        int256 deltaShares;
        int256 deltaCollateral;
        int256 deltaBorrow;
        address collateralToBorrowExchange;
        address vault;
        address user;
        address collateralAsset;
        address borrowAsset;
        uint256 maxAssetsCollateral;
    }

    function mintWithNoFlashLoanCollateral(
        MintWithNoFlashLoanCollateralInput memory input
    ) internal returns (uint256) {
        IERC20(input.collateralAsset).safeTransferFrom(input.user, address(this), input.maxAssetsCollateral);

        IERC20(input.collateralAsset).forceApprove(input.collateralToBorrowExchange, input.maxAssetsCollateral);
        uint256 collateralAssetsIn = IExchangeConnector(input.collateralToBorrowExchange).exchangeOut(
            input.collateralAsset, input.borrowAsset, uint256(-input.deltaBorrow), input.maxAssetsCollateral
        );

        uint256 collateralAssetsNeeded = collateralAssetsIn + uint256(input.deltaCollateral);
        require(
            collateralAssetsNeeded <= input.maxAssetsCollateral,
            MintWithNoFlashLoanCollateralSlippageExceeded(collateralAssetsNeeded, input.maxAssetsCollateral)
        );
        IERC20(input.borrowAsset).forceApprove(input.vault, uint256(-input.deltaBorrow));
        IERC20(input.collateralAsset).forceApprove(input.vault, uint256(input.deltaCollateral));
        ILowLevelVault(input.vault).executeLowLevelRebalanceShares(input.deltaShares);

        IERC20(input.vault).safeTransfer(input.user, uint256(input.deltaShares));
        return collateralAssetsNeeded;
    }
}
