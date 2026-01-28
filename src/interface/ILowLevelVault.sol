// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.28;

interface ILowLevelVault {
    function borrowAsset() external view returns (address);
    function collateralAsset() external view returns (address);
    function previewLowLevelRebalanceShares(int256 deltaShares) external view returns (int256 deltaCollateral, int256 deltaBorrow);
    function executeLowLevelRebalanceShares(int256 deltaShares) external returns (int256 deltaCollateral, int256 deltaBorrow);
}