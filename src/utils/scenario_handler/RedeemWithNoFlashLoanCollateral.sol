// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.28;

import {ILowLevelVault} from "../../interface/ILowLevelVault.sol";
import {IExchangeConnector} from "../../interface/IExchangeConnector.sol";
import {SafeERC20, IERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";

contract RedeemWithNoFlashLoanCollateral {
    using SafeERC20 for IERC20;
    using SafeERC20 for ILowLevelVault;

    error RedeemWithNoFlashLoanCollateralSlippageExceeded(uint256 userAssetsOut, uint256 minAssetsCollateral);

    struct RedeemWithNoFlashLoanCollateralInput {
        int256 deltaShares;
        int256 deltaCollateral;
        int256 deltaBorrow;
        address borrowToCollateralExchange;
        address vault;
        address user;
        address collateralAsset;
        address borrowAsset;
        uint256 minAssetsCollateral;
    }

    function redeemWithNoFlashLoanCollateral(
        RedeemWithNoFlashLoanCollateralInput memory input
    ) internal returns (uint256) {
        IERC20(input.vault).safeTransferFrom(input.user, address(this), uint256(-input.deltaShares));
        ILowLevelVault(input.vault).executeLowLevelRebalanceShares(input.deltaShares);

        IERC20(input.borrowAsset).forceApprove(
            input.borrowToCollateralExchange, uint256(-input.deltaBorrow)
        );
        uint256 collateralAssetsOut = IExchangeConnector(input.borrowToCollateralExchange).exchangeIn(
            input.borrowAsset, input.collateralAsset, uint256(-input.deltaBorrow), 0
        );

        uint256 userAssetsOut = collateralAssetsOut + uint256(input.deltaCollateral);
        require(
            userAssetsOut >= input.minAssetsCollateral,
            RedeemWithNoFlashLoanCollateralSlippageExceeded(userAssetsOut, input.minAssetsCollateral)
        );

        IERC20(input.collateralAsset).forceApprove(input.vault, uint256(-input.deltaCollateral));
        IERC20(input.collateralAsset).safeTransfer(input.user, userAssetsOut);
        return userAssetsOut;
    }
}
