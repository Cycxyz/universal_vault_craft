// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.28;

import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import {IsUSDS} from "../interface/IsUSDS.sol";
import {IUSDSMigration} from "../interface/IUSDS.sol";

contract DaiToSusdsWrapper {
    using SafeERC20 for IERC20;

    address public immutable USDS;
    address public immutable SUSDS;
    address public immutable DAI;
    IUSDSMigration public immutable usdsMigration;

    error InvalidTokenPair();

    modifier onlyDaiToSusds(address assetIn, address assetOut) {
        require(assetIn == DAI && assetOut == SUSDS, InvalidTokenPair());
        _;
    }

    function previewWrappingOperation(address assetIn, address assetOut, uint256 amountOut)
        external
        view
        onlyDaiToSusds(assetIn, assetOut)
        returns (uint256 amountIn)
    {
        uint256 sUsdsSupply = IsUSDS(SUSDS).totalSupply();
        uint256 sUsdsAssets = IsUSDS(SUSDS).totalAssets();

        uint256 requiredUsds = (amountOut * sUsdsAssets + sUsdsSupply - 1) / sUsdsSupply;

        // USDS to DAI 1:1
        return requiredUsds;
    }

    function executeWrappingOperation(address assetIn, address assetOut, uint256 amountIn)
        external
        onlyDaiToSusds(assetIn, assetOut)
        returns (uint256 amountOut)
    {
        IERC20(DAI).forceApprove(address(usdsMigration), amountIn);
        usdsMigration.migrateDAIToUSDS(address(this), amountIn);
        IERC20(USDS).forceApprove(SUSDS, amountIn);
        uint256 susdsReceived = IsUSDS(SUSDS).deposit(amountIn, address(this));
        return susdsReceived;
    }
}
