// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.28;

import {Test} from "forge-std/Test.sol";
import {CurveExchangeConnector, ExchangeOutParams, ExchangeInParams} from "../src/exchange_connectors/CurveExchangeConnector_V2.sol";
import {WethEthWrapper} from "../src/exchange_connectors/WethEthWrapper.sol";
import {StEthWstEthWrapper} from "../src/exchange_connectors/StEthWstEthWrapper.sol";
import {SafeERC20, IERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";

contract CurveV2ExchangeConnectorTest is Test {
    using SafeERC20 for IERC20;

    function test_exchangeOutEthToWstEth() public {
        address weth = 0xC02aaA39b223FE8D0A0e5C4F27eAD9083C756Cc2;
        address wstEth = 0x7f39C581F595B53c5cb19bD0b3f8dA6c935E2Ca0;
        address stEth = 0xae7ab96520DE3A18E5e111B5EaAb095312D7fE84;
        address eth = 0xEeeeeEeeeEeEeeEeEeEeeEEEeeeeEeeeeeeeEEeE;
        CurveExchangeConnector connector =
            new CurveExchangeConnector{salt: bytes32(0)}(0xDC24316b9AE028F1497c275EB9192a3Ea0f67022, 2);
        WethEthWrapper wethEthWrapper = new WethEthWrapper(weth);
        StEthWstEthWrapper stEthWstEthWrapper = new StEthWstEthWrapper();

        uint256 amountOut = 100e18;
        uint256 maxAmountIn = 200e18;

        address user = address(23946);
        deal(weth, user, maxAmountIn);
        vm.startPrank(user);
        IERC20(weth).approve(address(connector), maxAmountIn);
        uint256 amountIn = connector.exchangeOut(
            ExchangeOutParams({
                assetIn: weth,
                poolAssetIn: eth,
                assetOut: wstEth,
                poolAssetOut: stEth,
                amountOut: amountOut,
                maxAmountIn: maxAmountIn,
                preExchangeWrapper: address(wethEthWrapper),
                postExchangeWrapper: address(stEthWstEthWrapper)
            })
        );
        assertEq(IERC20(wstEth).balanceOf(address(connector)), 0);
        assertLe(IERC20(stEth).balanceOf(address(connector)), 1);
        assertEq(IERC20(weth).balanceOf(address(connector)), 0);
        assertEq(address(connector).balance, 0);

        assertEq(IERC20(weth).balanceOf(user), 200e18 - amountIn);
        assertEq(IERC20(wstEth).balanceOf(user), amountOut);
        assertEq(IERC20(stEth).balanceOf(user), 0);
        assertEq(address(user).balance, 0);
    }

    function test_exchangeOutWstEthToEth() public {
        address weth = 0xC02aaA39b223FE8D0A0e5C4F27eAD9083C756Cc2;
        address wstEth = 0x7f39C581F595B53c5cb19bD0b3f8dA6c935E2Ca0;
        address stEth = 0xae7ab96520DE3A18E5e111B5EaAb095312D7fE84;
        address eth = 0xEeeeeEeeeEeEeeEeEeEeeEEEeeeeEeeeeeeeEEeE;
        CurveExchangeConnector connector =
            new CurveExchangeConnector{salt: bytes32(0)}(0xDC24316b9AE028F1497c275EB9192a3Ea0f67022, 2);
        WethEthWrapper wethEthWrapper = new WethEthWrapper(weth);
        StEthWstEthWrapper stEthWstEthWrapper = new StEthWstEthWrapper();

        uint256 amountOut = 100e18;
        uint256 maxAmountIn = 100e18;

        address user = address(23946);
        deal(wstEth, user, maxAmountIn);
        vm.startPrank(user);
        IERC20(wstEth).approve(address(connector), maxAmountIn);
        uint256 amountIn = connector.exchangeOut(
            ExchangeOutParams({
                assetIn: wstEth,
                poolAssetIn: stEth,
                assetOut: weth,
                poolAssetOut: eth,
                amountOut: amountOut,
                maxAmountIn: maxAmountIn,
                preExchangeWrapper: address(stEthWstEthWrapper),
                postExchangeWrapper: address(wethEthWrapper)
            })
        );
        assertEq(IERC20(wstEth).balanceOf(address(connector)), 0);
        assertLe(IERC20(stEth).balanceOf(address(connector)), 1);
        assertEq(IERC20(weth).balanceOf(address(connector)), 0);
        assertEq(address(connector).balance, 0);

        assertEq(IERC20(weth).balanceOf(user), amountOut);
        assertEq(IERC20(wstEth).balanceOf(user), 100e18 - amountIn);
        assertEq(IERC20(stEth).balanceOf(user), 0);
        assertEq(address(user).balance, 0);
    }

    function test_exchangeInWstEthToEth() public {
        address weth = 0xC02aaA39b223FE8D0A0e5C4F27eAD9083C756Cc2;
        address wstEth = 0x7f39C581F595B53c5cb19bD0b3f8dA6c935E2Ca0;
        address stEth = 0xae7ab96520DE3A18E5e111B5EaAb095312D7fE84;
        address eth = 0xEeeeeEeeeEeEeeEeEeEeeEEEeeeeEeeeeeeeEEeE;
        CurveExchangeConnector connector =
            new CurveExchangeConnector{salt: bytes32(0)}(0xDC24316b9AE028F1497c275EB9192a3Ea0f67022, 2);
        WethEthWrapper wethEthWrapper = new WethEthWrapper(weth);
        StEthWstEthWrapper stEthWstEthWrapper = new StEthWstEthWrapper();

        uint256 minAmountOut = 100e18;
        uint256 amountIn = 100e18;

        address user = address(23946);
        deal(wstEth, user, amountIn);
        vm.startPrank(user);
        IERC20(wstEth).approve(address(connector), amountIn);
        uint256 amountOut = connector.exchangeIn(
            ExchangeInParams({
                assetIn: wstEth,
                poolAssetIn: stEth,
                assetOut: weth,
                poolAssetOut: eth,
                amountIn: amountIn,
                minAmountOut: minAmountOut,
                preExchangeWrapper: address(stEthWstEthWrapper),
                postExchangeWrapper: address(wethEthWrapper)
            })
        );
        assertEq(IERC20(wstEth).balanceOf(address(connector)), 0);
        assertLe(IERC20(stEth).balanceOf(address(connector)), 1);
        assertEq(IERC20(weth).balanceOf(address(connector)), 0);
        assertEq(address(connector).balance, 0);

        assertEq(IERC20(weth).balanceOf(user), amountOut);
        assertLe(IERC20(wstEth).balanceOf(user), amountIn);
        assertEq(IERC20(stEth).balanceOf(user), 0);
        assertEq(address(user).balance, 0);
    }
}
