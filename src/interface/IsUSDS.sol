// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.28;

/// @notice Interface for sUSDS (Savings USDS) ERC4626 vault
/// @dev sUSDS is an ERC4626 compliant vault that wraps USDS
interface IsUSDS {
    /// @notice Deposits USDS and receives sUSDS shares
    /// @param assets The amount of USDS to deposit
    /// @param receiver The address to receive sUSDS shares
    /// @return shares The amount of sUSDS shares received
    function deposit(uint256 assets, address receiver) external returns (uint256 shares);
    
    /// @notice Redeems sUSDS shares for USDS assets
    /// @param shares The amount of sUSDS shares to redeem
    /// @param receiver The address to receive USDS
    /// @param owner The address that owns the shares
    /// @return assets The amount of USDS received
    function redeem(uint256 shares, address receiver, address owner) external returns (uint256 assets);
}
