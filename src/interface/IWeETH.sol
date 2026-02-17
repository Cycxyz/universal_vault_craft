// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.28;

interface IWeETH {
    /// @notice Wrap eETH to WEETH
    /// @param amount Amount of eETH to wrap
    /// @return Amount of WEETH received
    function wrap(uint256 amount) external returns (uint256);
    
    /// @notice Unwrap WEETH to eETH
    /// @param amount Amount of WEETH to unwrap
    /// @return Amount of eETH received
    function unwrap(uint256 amount) external returns (uint256);
    
    /// @notice Get the amount of WEETH for a given amount of eETH
    /// @param amount Amount of eETH
    /// @return Amount of WEETH
    function getWeETHByeETH(uint256 amount) external view returns (uint256);
    
    /// @notice Get the amount of eETH for a given amount of WEETH
    /// @param amount Amount of WEETH
    /// @return Amount of eETH
    function getEETHByWeETH(uint256 amount) external view returns (uint256);
}
