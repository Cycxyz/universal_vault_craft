// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.28;

/// @notice Interface for Lombard Bitcoin (LBTC) token contract
/// @dev LBTC wraps BTC (via BTC.b or WBTC) and mints LBTC tokens
/// @dev Based on StakedLBTC contract at 0x8236a87084f8B84306f72007F36F2618A5634494
interface ILBTC {
    /// @notice Deposits underlying BTC tokens and mints LBTC to msg.sender
    /// @param amount The amount of underlying tokens to deposit
    /// @dev The LBTC tokens are minted to the caller (msg.sender)
    function deposit(uint256 amount) external;

    /// @notice Gets the exchange rate (ratio) between underlying tokens and LBTC
    /// @return The ratio representing how much LBTC is minted per underlying token
    /// @dev This is used to calculate the exchange rate
    function ratio() external view returns (uint256);

    /// @notice Gets the current rate for converting underlying tokens to LBTC
    /// @return The current rate
    function getRate() external view returns (uint256);
}
