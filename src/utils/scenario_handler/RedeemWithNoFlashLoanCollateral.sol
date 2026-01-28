// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.28;

import {ILowLevelVault} from "../../interface/ILowLevelVault.sol";
import {IExchangeConnector} from "../../interface/IExchangeConnector.sol";
import {SafeERC20, IERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";

contract RedeemWithNoFlashLoanCollateral {
    using SafeERC20 for IERC20;
    using SafeERC20 for ILowLevelVault;

    error RedeemWithNoFlashLoanCollateralSlippageExceeded(uint256 userAssetsOut, uint256 minAssetsCollateral);

    function redeemWithNoFlashLoanCollateral(
        int256 deltaShares,
        int256 deltaCollateral,
        int256 deltaBorrow,
        address borrowToCollateralExchange,
        address vault,
        address user,
        address collateralAsset,
        address borrowAsset,
        uint256 minAssetsCollateral
    ) internal returns (uint256) {
        IERC20(vault).safeTransferFrom(user, address(this), uint256(-deltaShares));
        ILowLevelVault(vault).executeLowLevelRebalanceShares(deltaShares);

        IERC20(borrowAsset).forceApprove(borrowToCollateralExchange, uint256(-deltaBorrow));
        uint256 collateralAssetsOut = IExchangeConnector(borrowToCollateralExchange).exchangeIn(
            borrowAsset, collateralAsset, uint256(-deltaBorrow), 0
        );

        uint256 userAssetsOut = collateralAssetsOut + uint256(deltaCollateral);
        require(
            userAssetsOut >= minAssetsCollateral,
            RedeemWithNoFlashLoanCollateralSlippageExceeded(userAssetsOut, minAssetsCollateral)
        );

        IERC20(collateralAsset).forceApprove(vault, uint256(-deltaCollateral));
        IERC20(collateralAsset).safeTransfer(user, userAssetsOut);
        return userAssetsOut;
    }
}
