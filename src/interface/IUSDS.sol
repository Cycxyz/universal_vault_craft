// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.28;

/// @notice Interface for Spark Protocol MigrationActions contract that upgrades DAI to USDS
/// @dev Contract address: 0xf86141a5657Cf52AEB3E30eBccA5Ad3a8f714B89
interface IUSDSMigration {
    /// @notice Migrates DAI to USDS at 1:1 ratio
    /// @param receiver The address to receive USDS
    /// @param assetsIn The amount of DAI to migrate
    function migrateDAIToUSDS(address receiver, uint256 assetsIn) external;
    
    /// @notice Downgrades USDS to DAI at 1:1 ratio
    /// @param receiver The address to receive DAI
    /// @param assetsIn The amount of USDS to downgrade
    function downgradeUSDSToDAI(address receiver, uint256 assetsIn) external;
}
