// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.28;

import {IExchangeConnector} from "../../src/interface/IExchangeConnector.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import {StdCheats} from "forge-std/StdCheats.sol";

contract MockExchangeConnector is IExchangeConnector, StdCheats {
    using SafeERC20 for IERC20;

    address public immutable collateralToken;
    address public immutable borrowToken;
    uint256 public immutable collateralPrice;
    uint256 public immutable borrowPrice;
    uint256 public immutable pricePrecision;
    uint256 public immutable feePercentage;
    uint256 public immutable feePrecision;

    error InvalidTokenPair();
    error SlippageExceeded();
    error InvalidFee();

    constructor(
        address _collateralToken,
        address _borrowToken,
        uint256 _collateralPrice,
        uint256 _borrowPrice,
        uint256 _pricePrecision,
        uint256 _feePercentage,
        uint256 _feePrecision
    ) {
        require(_collateralToken != address(0) && _borrowToken != address(0), "Zero address");
        require(_collateralPrice > 0 && _borrowPrice > 0 && _pricePrecision > 0, "Invalid prices");
        require(_feePrecision > 0, "Invalid fee precision");
        require(_feePercentage <= _feePrecision, InvalidFee());
        collateralToken = _collateralToken;
        borrowToken = _borrowToken;
        collateralPrice = _collateralPrice;
        borrowPrice = _borrowPrice;
        pricePrecision = _pricePrecision;
        feePercentage = _feePercentage;
        feePrecision = _feePrecision;
    }

    function exchangeOut(address assetIn, address assetOut, uint256 amountOut, uint256 maxAmountIn)
        external
        payable
        override
        returns (uint256 amountIn)
    {
        _requireValidPair(assetIn, assetOut);
        bool isCollateralToBorrow = (assetIn == collateralToken && assetOut == borrowToken);
        uint256 amountInNeeded = isCollateralToBorrow
            ? (amountOut * borrowPrice + collateralPrice - 1) / collateralPrice
            : (amountOut * collateralPrice + borrowPrice - 1) / borrowPrice;
        amountInNeeded = (amountInNeeded * (feePrecision + feePercentage) + feePrecision - 1) / feePrecision;
        require(amountInNeeded <= maxAmountIn, SlippageExceeded());
        IERC20(assetIn).safeTransferFrom(msg.sender, address(this), amountInNeeded);
        uint256 balance = IERC20(assetOut).balanceOf(address(this));
        if (balance < amountOut) deal(assetOut, address(this), amountOut);
        IERC20(assetOut).safeTransfer(msg.sender, amountOut);
        return amountInNeeded;
    }

    function exchangeIn(address assetIn, address assetOut, uint256 amountIn, uint256 minAmountOut)
        external
        payable
        override
        returns (uint256 amountOut)
    {
        _requireValidPair(assetIn, assetOut);
        bool isCollateralToBorrow = (assetIn == collateralToken && assetOut == borrowToken);
        amountOut = isCollateralToBorrow
            ? (amountIn * collateralPrice) / borrowPrice
            : (amountIn * borrowPrice) / collateralPrice;
        amountOut = (amountOut * (feePrecision - feePercentage)) / feePrecision;
        require(amountOut >= minAmountOut, SlippageExceeded());
        IERC20(assetIn).safeTransferFrom(msg.sender, address(this), amountIn);
        uint256 balance = IERC20(assetOut).balanceOf(address(this));
        if (balance < amountOut) deal(assetOut, address(this), amountOut);
        IERC20(assetOut).safeTransfer(msg.sender, amountOut);
    }

    function _requireValidPair(address assetIn, address assetOut) internal view {
        bool isValidPair = (assetIn == collateralToken && assetOut == borrowToken) ||
            (assetIn == borrowToken && assetOut == collateralToken);
        require(isValidPair, InvalidTokenPair());
    }
}
