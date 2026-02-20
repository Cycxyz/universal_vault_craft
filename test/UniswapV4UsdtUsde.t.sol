    // SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.28;

import {IExchangeConnector} from "../src/interface/IExchangeConnector.sol";
import {UniswapV4ExchangeConnector} from "../src/exchange_connectors/UniswapV4ExchangeConnector.sol";
import {CommonExchangeConnectorTest} from "./utils/CommonExchangeConnectorTest.sol";
import {Eip4626Wrapper} from "../src/exchange_connectors/Eip4626Wrapper.sol";

contract UniswapV4UsdtUsdeTest is CommonExchangeConnectorTest {
    address public constant USDT = 0xdAC17F958D2ee523a2206206994597C13D831ec7;
    address public constant USDE = 0x4c9EDD5852cd905f086C759E8383e09bff1E68B3;
    address public constant SUSDE = 0x9D39A5DE30e57443BfF2A8307A4256c8797A3497;
    address public constant POOL_MANAGER = 0x000000000004444c5dc75cB358380D2e3dE08A90;
    address public constant POSITION_MANAGER = 0xbD216513d74C8cf14cf4747E6AaA6420FF64ee9e;
    bytes25 public constant POOL_ID = bytes25(0x63bb22f47c7ede6578a25c873e77eb782ec8e4c19778e36ce6);

    function test_exchangeOutUsdtToUsde() public {
        address usdeSusdeWrapper = deployUsdeSusdeWrapper();
        _test_exchangeConnectorOut(USDT, USDT, SUSDE, USDE, 100e18, address(0), usdeSusdeWrapper);
    }

    function test_exchangeInUsdtToUsde() public {
        address usdeSusdeWrapper = deployUsdeSusdeWrapper();
        _test_exchangeConnectorIn(USDT, USDT, SUSDE, USDE, 100e6, address(0), usdeSusdeWrapper);
    }

    /*
    Withdrawing Susde to Usde is not allowed

    function test_exchangeOutUsdeToUsdt() public {
        address usdeSusdeWrapper = deployUsdeSusdeWrapper();
        _test_exchangeConnectorOut(SUSDE, USDE, USDT, USDT, 100e6, usdeSusdeWrapper, address(0));
    }
    
    function test_exchangeInUsdeToUsdt() public {
        address usdeSusdeWrapper = deployUsdeSusdeWrapper();
        _test_exchangeConnectorIn(SUSDE, USDE, USDT, USDT, 100e18, usdeSusdeWrapper, address(0));
    }
    */

    function deployExchangeConnector() internal override returns (IExchangeConnector) {
        return new UniswapV4ExchangeConnector{salt: bytes32(0)}(POOL_MANAGER, POSITION_MANAGER, POOL_ID);
    }

    function deployUsdeSusdeWrapper() internal returns (address) {
        return address(new Eip4626Wrapper(USDE, SUSDE));
    }
}
