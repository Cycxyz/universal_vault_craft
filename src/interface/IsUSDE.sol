// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.28;

// sUSDE is an ERC4626 vault with cooldown period
// Users must request redemption first, then wait 7 days before redeeming
interface IsUSDE {
    function deposit(uint256 assets, address receiver) external returns (uint256 shares);
    function redeem(uint256 shares, address receiver, address owner) external returns (uint256 assets);
    function convertToAssets(uint256 shares) external view returns (uint256);
    function convertToShares(uint256 assets) external view returns (uint256);
    
    // Cooldown functions for sUSDE
    function requestRedeem(uint256 shares, address owner) external returns (uint256);
    function requestCooldownAssets(address owner) external view returns (uint256);
    function maxRedeem(address owner) external view returns (uint256);
}
