// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.28;

import {CommonExchangeConnector} from "./CommonExchangeConnector.sol";
import {IStEth} from "../interface/IStEth.sol";

contract LidoNativeExchangeConnector is CommonExchangeConnector {
    error InvalidTokenPair();
    error ZeroAddress();

    address public immutable STETH;

    constructor(address _stEth) {
        require(_stEth != address(0), ZeroAddress());
        STETH = _stEth;
    }

    modifier onlyEthToStEth(address assetIn, address assetOut) {
        require((assetIn == 0xEeeeeEeeeEeEeeEeEeEeeEEEeeeeEeeeeeeeEEeE) && (assetOut == STETH), InvalidTokenPair());
        _;
    }

    function _swapIn(address swapAssetIn, address swapAssetOut, uint256 amountIn)
        internal
        override
        onlyEthToStEth(swapAssetIn, swapAssetOut)
        returns (uint256 amountOut)
    {
        IStEth(STETH).submit{value: amountIn}(address(0));
        return amountIn;
    }

    function _swapOut(address swapAssetIn, address swapAssetOut, uint256, uint256 amountOut)
        internal
        override
        onlyEthToStEth(swapAssetIn, swapAssetOut)
        returns (uint256 amountIn)
    {
        IStEth(STETH).submit{value: amountOut}(address(0));
        return amountOut;
    }
}
