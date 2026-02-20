// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.28;

import {CurveExchangeConnector} from "../src/exchange_connectors/CurveExchangeConnector.sol";
import {IExchangeConnector} from "../src/interface/IExchangeConnector.sol";
import {DaiToSusdsWrapper} from "../src/exchange_connectors/DaiToSusdsWrapper.sol";
import {CommonExchangeConnectorTest} from "./utils/CommonExchangeConnectorTest.sol";

contract CurveUsdtDaiExchangeConnectorTest is CommonExchangeConnectorTest {
    address public constant DAI = 0x6B175474E89094C44Da98b954EedeAC495271d0F;
    address public constant USDS = 0xdC035D45d973E3EC169d2276DDab16f1e407384F;
    address public constant SUSDS = 0xa3931d71877C0E7a3148CB7Eb4463524FEc27fbD;
    address public constant USDT = 0xdAC17F958D2ee523a2206206994597C13D831ec7;
    address public constant CURVE_POOL = 0xbEbc44782C7dB0a1A60Cb6fe97d0b483032FF1C7;
    address public constant USDS_MIGRATION = 0xf86141a5657Cf52AEB3E30eBccA5Ad3a8f714B89;

    address public DAISUSDS_WRAPPER = address(new DaiToSusdsWrapper(DAI, USDS_MIGRATION, USDS, SUSDS));

    function test_exchangeOutUsdtToSusds() public {
        _test_exchangeConnectorOut(USDT, USDT, SUSDS, DAI, 100e18, address(0), DAISUSDS_WRAPPER);
    }

    function test_exchangeInUsdtToSusds() public {
        _test_exchangeConnectorIn(USDT, USDT, SUSDS, DAI, 100e6, address(0), DAISUSDS_WRAPPER);
    }

    /* 
    Unwrapping SUSDS to DAI is not supported
    
    function test_exchangeOutSusdsToUsdt() public {
        _test_exchangeConnectorOut(SUSDS, DAI, USDT, USDT, 100e6, DAISUSDS_WRAPPER, address(0));
    }

    function test_exchangeInSusdsToUsdt() public {
        _test_exchangeConnectorIn(SUSDS, DAI, USDT, USDT, 100e6, DAISUSDS_WRAPPER, address(0));
    }
    */

    function deployExchangeConnector() internal override returns (IExchangeConnector) {
        return new CurveExchangeConnector{salt: bytes32(0)}(CURVE_POOL, 3);
    }
}
