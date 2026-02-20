// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.28;

import {Test} from "forge-std/Test.sol";
import {CommonExchangeConnector} from "../../src/exchange_connectors/CommonExchangeConnector.sol";
import {IExchangeConnector} from "../../src/interface/IExchangeConnector.sol";
import {SafeERC20, IERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import {IERC20Metadata} from "@openzeppelin/contracts/interfaces/IERC20Metadata.sol";

abstract contract CommonExchangeConnectorTest is Test {
    using SafeERC20 for IERC20;

    function _test_exchangeConnectorOut(
        address assetIn,
        address swapAssetIn,
        address assetOut,
        address swapAssetOut,
        uint256 amountOut,
        address preExchangeWrapper,
        address postExchangeWrapper
    ) public {
        address user = address(234327319);
        IExchangeConnector exchangeConnector = deployExchangeConnector();

        uint256 maxAmountIn =
            2 * amountOut * 10 ** IERC20Metadata(assetIn).decimals() / 10 ** IERC20Metadata(assetOut).decimals();
        deal(assetIn, user, maxAmountIn);
        vm.startPrank(user);
        IERC20(assetIn).forceApprove(address(exchangeConnector), maxAmountIn);
        uint256 amountIn = exchangeConnector.exchangeOut(
            IExchangeConnector.ExchangeOutParams({
                assetIn: assetIn,
                swapAssetIn: swapAssetIn,
                assetOut: assetOut,
                swapAssetOut: swapAssetOut,
                amountOut: amountOut,
                maxAmountIn: maxAmountIn,
                preExchangeWrapper: preExchangeWrapper,
                postExchangeWrapper: postExchangeWrapper
            })
        );

        _makePostChecks(
            user,
            address(exchangeConnector),
            assetIn,
            assetOut,
            swapAssetIn,
            swapAssetOut,
            maxAmountIn,
            amountIn,
            amountOut
        );
    }

    function _test_exchangeConnectorIn(
        address assetIn,
        address swapAssetIn,
        address assetOut,
        address swapAssetOut,
        uint256 amountIn,
        address preExchangeWrapper,
        address postExchangeWrapper
    ) public {
        address user = address(234327319);
        IExchangeConnector exchangeConnector = deployExchangeConnector();

        uint256 minAmountOut =
            (amountIn / 2) * 10 ** IERC20Metadata(assetOut).decimals() / 10 ** IERC20Metadata(assetIn).decimals();
        deal(assetIn, user, amountIn);
        vm.startPrank(user);
        IERC20(assetIn).forceApprove(address(exchangeConnector), amountIn);
        uint256 amountOut = exchangeConnector.exchangeIn(
            IExchangeConnector.ExchangeInParams({
                assetIn: assetIn,
                swapAssetIn: swapAssetIn,
                assetOut: assetOut,
                swapAssetOut: swapAssetOut,
                amountIn: amountIn,
                minAmountOut: minAmountOut,
                preExchangeWrapper: preExchangeWrapper,
                postExchangeWrapper: postExchangeWrapper
            })
        );

        _makePostChecks(
            user,
            address(exchangeConnector),
            assetIn,
            assetOut,
            swapAssetIn,
            swapAssetOut,
            amountIn,
            amountIn,
            amountOut
        );
    }

    function _makePostChecks(
        address user,
        address exchangeConnector,
        address assetIn,
        address assetOut,
        address swapAssetIn,
        address swapAssetOut,
        uint256 initialAmountIn,
        uint256 amountIn,
        uint256 amountOut
    ) internal view {
        assertEq(IERC20(assetIn).balanceOf(address(exchangeConnector)), 0);
        assertEq(IERC20(assetOut).balanceOf(address(exchangeConnector)), 0);

        if (isEthAddress(swapAssetIn)) {
            assertEq(address(exchangeConnector).balance, 0);
        } else {
            assertEq(IERC20(swapAssetIn).balanceOf(address(exchangeConnector)), 0);
        }

        if (isEthAddress(swapAssetOut)) {
            assertEq(address(exchangeConnector).balance, 0);
        } else {
            assertEq(IERC20(swapAssetOut).balanceOf(address(exchangeConnector)), 0);
        }

        assertEq(IERC20(assetIn).balanceOf(user), initialAmountIn - amountIn);
        assertEq(IERC20(assetOut).balanceOf(user), amountOut);

        if (isEthAddress(swapAssetIn)) {
            assertEq(address(user).balance, 0);
        } else if (swapAssetIn != assetIn) {
            assertEq(IERC20(swapAssetIn).balanceOf(user), 0);
        }

        if (isEthAddress(swapAssetOut)) {
            assertEq(address(user).balance, 0);
        } else if (swapAssetOut != assetOut) {
            assertEq(IERC20(swapAssetOut).balanceOf(user), 0);
        }
    }

    function isEthAddress(address addr) internal pure returns (bool) {
        return addr == 0xEeeeeEeeeEeEeeEeEeEeeEEEeeeeEeeeeeeeEEeE || addr == address(0);
    }

    function deployExchangeConnector() internal virtual returns (IExchangeConnector);
}
