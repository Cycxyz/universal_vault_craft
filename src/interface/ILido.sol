// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.28;

/// @notice Interface for Lido stETH contract (v3)
/// @dev Lido contract address: 0xae7ab96520DE3A18E5e111B5EaAb095312D7fE84
/// @dev Lido v3 supports staking on behalf of different stakers via recipient parameter
interface ILido {
    /// @notice Submit ETH to Lido and receive stETH
    /// @dev This function is payable and mints stETH tokens to the recipient address
    /// @param _referral Referral address (can be address(0))
    /// @param _recipient Address to receive the stETH tokens (Lido v3 feature)
    /// @return Amount of stETH tokens minted
    function submit(address _referral, address _recipient) external payable returns (uint256);

    /// @notice Get the total supply of stETH tokens
    /// @return Total supply of stETH
    function totalSupply() external view returns (uint256);

    /// @notice Get the total shares in the Lido protocol
    /// @return Total shares
    function getTotalShares() external view returns (uint256);

    /// @notice Get the amount of stETH tokens for a given amount of shares
    /// @param _sharesAmount Amount of shares
    /// @return Amount of stETH tokens
    function getPooledEthByShares(uint256 _sharesAmount) external view returns (uint256);

    /// @notice Get the amount of shares for a given amount of stETH tokens
    /// @param _stETHAmount Amount of stETH tokens
    /// @return Amount of shares
    function getSharesByPooledEth(uint256 _stETHAmount) external view returns (uint256);
}
