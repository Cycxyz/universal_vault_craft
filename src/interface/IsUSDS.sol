// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.28;

/// @notice Interface for sUSDS (Savings USDS) ERC4626 vault
/// @dev sUSDS is an ERC4626 compliant vault that wraps USDS
interface IsUSDS {
    function deposit(uint256 assets, address receiver) external returns (uint256 shares);
    function redeem(uint256 shares, address receiver, address owner) external returns (uint256 assets);
    
    function totalAssets() external view returns (uint256);
    function totalSupply() external view returns (uint256);

    function previewDeposit(uint256 assets) external view returns (uint256 shares);
    function previewRedeem(uint256 shares) external view returns (uint256 assets);
}
