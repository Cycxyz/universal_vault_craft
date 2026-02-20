// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.28;

import {CommonExchangeConnectorTest} from "./utils/CommonExchangeConnectorTest.sol";
import {LidoNativeExchangeConnector} from "../src/exchange_connectors/LidoNativeExchangeConnector.sol";
import {IExchangeConnector} from "../src/interface/IExchangeConnector.sol";
import {WethEthWrapper} from "../src/exchange_connectors/WethEthWrapper.sol";
import {StEthWstEthWrapper} from "../src/exchange_connectors/StEthWstEthWrapper.sol";

contract NativeEthToWstEthTest is CommonExchangeConnectorTest {
    address public constant ETH = 0xEeeeeEeeeEeEeeEeEeEeeEEEeeeeEeeeeeeeEEeE;
    address public constant WETH = 0xC02aaA39b223FE8D0A0e5C4F27eAD9083C756Cc2;
    address public constant WSTETH = 0x7f39C581F595B53c5cb19bD0b3f8dA6c935E2Ca0;
    address public constant STETH = 0xae7ab96520DE3A18E5e111B5EaAb095312D7fE84;

    address public WETH_ETH_WRAPPER = address(new WethEthWrapper(WETH));
    address public STETH_WSTETH_WRAPPER = address(new StEthWstEthWrapper());

    function test_exchangeOutEthToWstEth() public {
        _test_exchangeConnectorOut(WETH, ETH, WSTETH, STETH, 100e18, WETH_ETH_WRAPPER, STETH_WSTETH_WRAPPER);
    }

    function test_exchangeInEthToWstEth() public {
        _test_exchangeConnectorIn(WETH, ETH, WSTETH, STETH, 100e18, WETH_ETH_WRAPPER, STETH_WSTETH_WRAPPER);
    }

    /*
    Unwrapping WSTETH to ETH is not supported
    
    function test_exchangeOutWstEthToEth() public {
        _test_exchangeConnectorOut(WSTETH, STETH, WETH, ETH, 100e18, STETH_WSTETH_WRAPPER, WETH_ETH_WRAPPER);
    }

    function test_exchangeInWstEthToEth() public {
        _test_exchangeConnectorIn(WSTETH, STETH, WETH, ETH, 100e18, STETH_WSTETH_WRAPPER, WETH_ETH_WRAPPER);
    }
    */

    function deployExchangeConnector() internal override returns (IExchangeConnector) {
        return new LidoNativeExchangeConnector{salt: bytes32(0)}(STETH);
    }
}
