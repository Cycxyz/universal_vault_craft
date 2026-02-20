// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.28;

import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import {IsUSDS} from "../interface/IsUSDS.sol";
import {IUSDSMigration} from "../interface/IUSDS.sol";
import {IERC4626} from "forge-std/interfaces/IERC4626.sol";
import {IExchangeWrapper} from "../interface/IExchangeWrapper.sol";

contract DaiToSusdsWrapper is IExchangeWrapper {
    using SafeERC20 for IERC20;

    address public immutable DAI;
    IUSDSMigration public immutable usdsMigration;
    IERC20 public immutable USDS;
    IERC4626 public immutable SUSDS;

    error InvalidTokenPair();

    constructor(address _dai, address _usdsMigration, address usds, address susds) {
        DAI = _dai;
        usdsMigration = IUSDSMigration(_usdsMigration);
        USDS = IERC20(usds);
        SUSDS = IERC4626(susds);
    }

    modifier onlyDaiToSusds(address assetIn, address assetOut) {
        require(assetIn == DAI && assetOut == address(SUSDS), InvalidTokenPair());
        _;
    }

    function previewWrappingOperation(address assetIn, address assetOut, uint256 amountOut)
        public
        view
        override
        onlyDaiToSusds(assetIn, assetOut)
        returns (uint256 amountIn)
    {
        // DAI to USDS is 1:1 so just preview mint
        return SUSDS.previewMint(amountOut);
    }

    function executeWrappingOperationIn(address assetIn, address assetOut, uint256 amountIn)
        public
        override
        onlyDaiToSusds(assetIn, assetOut)
        returns (uint256 amountOut)
    {
        IERC20(DAI).forceApprove(address(usdsMigration), amountIn);
        usdsMigration.migrateDAIToUSDS(address(this), amountIn);
        IERC20(USDS).forceApprove(address(SUSDS), amountIn);
        return SUSDS.deposit(amountIn, address(this));
    }

    function executeWrappingOperationOut(address assetIn, address assetOut, uint256 amountOut)
        public
        override
        onlyDaiToSusds(assetIn, assetOut)
        returns (uint256)
    {
        uint256 amountIn = SUSDS.previewMint(amountOut);

        IERC20(DAI).forceApprove(address(usdsMigration), amountIn);
        usdsMigration.migrateDAIToUSDS(address(this), amountIn);
        IERC20(USDS).forceApprove(address(SUSDS), amountIn);
        return SUSDS.mint(amountOut, address(this));
    }
}