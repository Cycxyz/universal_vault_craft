// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.28;

interface ILowLevelRebalanceHelper {
    function mintWithFlashLoanIn(
        address vault,
        address borrowToCollateralExchange,
        address collateralToBorrowExchange,
        address borrowFlashLoanConnector,
        address collateralFlashLoanConnector,
        address asset,
        uint256 assetsIn,
        uint256 minSharesOut
    ) external returns (uint256);

    function redeemWithFlashLoanIn(
        address vault,
        address borrowToCollateralExchange,
        address collateralToBorrowExchange,
        address borrowFlashLoanConnector,
        address collateralFlashLoanConnector,
        address asset,
        uint256 sharesIn,
        uint256 minAssetsOut
    ) external returns (uint256);

    function mintWithFlashLoanOut(
        address vault,
        address borrowToCollateralExchange,
        address collateralToBorrowExchange,
        address borrowFlashLoanConnector,
        address collateralFlashLoanConnector,
        address asset,
        uint256 sharesOut,
        uint256 maxAssetsIn
    ) external returns (uint256);

    function redeemWithFlashLoanOut(    
        address vault,
        address borrowToCollateralExchange,
        address collateralToBorrowExchange,
        address borrowFlashLoanConnector,
        address collateralFlashLoanConnector,
        address asset,
        uint256 sharesOut,
        uint256 maxAssetsIn
    ) external returns (uint256);
}