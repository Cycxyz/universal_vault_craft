// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.28;

interface IEETH {
    /// @notice Deposit native ETH to receive eETH
    function deposit() external payable;
    
    /// @notice Withdraw eETH to receive native ETH
    /// @param amount Amount of eETH to withdraw
    function withdraw(uint256 amount) external;
}
