// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.28;

import {CurveExchangeConnector} from "../src/exchange_connectors/CurveExchangeConnector.sol";
import {IExchangeConnector} from "../src/interface/IExchangeConnector.sol";
import {WethEthWrapper} from "../src/exchange_connectors/WethEthWrapper.sol";
import {StEthWstEthWrapper} from "../src/exchange_connectors/StEthWstEthWrapper.sol";
import {CommonExchangeConnectorTest} from "./utils/CommonExchangeConnectorTest.sol";

contract CurveEthStEthExchangeConnectorTest is CommonExchangeConnectorTest {
    address public constant WETH = 0xC02aaA39b223FE8D0A0e5C4F27eAD9083C756Cc2;
    address public constant WSTETH = 0x7f39C581F595B53c5cb19bD0b3f8dA6c935E2Ca0;
    address public constant STETH = 0xae7ab96520DE3A18E5e111B5EaAb095312D7fE84;
    address public constant ETH = 0xEeeeeEeeeEeEeeEeEeEeeEEEeeeeEeeeeeeeEEeE;
    address public constant CURVE_POOL = 0xDC24316b9AE028F1497c275EB9192a3Ea0f67022;

    address public WETH_ETH_WRAPPER = address(new WethEthWrapper(WETH));
    address public STETH_WSTETH_WRAPPER = address(new StEthWstEthWrapper());


    function test_exchangeOutWethToWstEth() public {
        _test_exchangeConnectorOut(WETH, ETH, WSTETH, STETH, 10e18, WETH_ETH_WRAPPER, STETH_WSTETH_WRAPPER);
    }

    function test_exchangeInWethToWsteth() public {
        _test_exchangeConnectorIn(WETH, ETH, WSTETH, STETH, 10e18, WETH_ETH_WRAPPER, STETH_WSTETH_WRAPPER);
    }

    function test_exchangeOutWstEthToWeth() public {
        _test_exchangeConnectorOut(WSTETH, STETH, WETH, ETH, 10e18, STETH_WSTETH_WRAPPER, WETH_ETH_WRAPPER);
    }

    function test_exchangeInWstEthToWeth() public {
        _test_exchangeConnectorIn(WSTETH, STETH, WETH, ETH, 10e18, STETH_WSTETH_WRAPPER, WETH_ETH_WRAPPER);
    }

    function deployExchangeConnector() internal override returns (IExchangeConnector) {
        return new CurveExchangeConnector{salt: bytes32(0)}(CURVE_POOL, 2);
    }
}
