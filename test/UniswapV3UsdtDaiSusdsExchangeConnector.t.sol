// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.28;

import {UniswapV3ExchangeConnector} from "../src/exchange_connectors/UniswapV3ExchangeConnector.sol";
import {CommonExchangeConnectorTest} from "./utils/CommonExchangeConnectorTest.sol";
import {IExchangeConnector} from "../src/interface/IExchangeConnector.sol";
import {DaiToSusdsWrapper} from "../src/exchange_connectors/DaiToSusdsWrapper.sol";

contract UniswapV3UsdtDaiSusdsExchangeConnectorTest is CommonExchangeConnectorTest {
    // Mainnet addresses
    address public constant USDT = 0xdAC17F958D2ee523a2206206994597C13D831ec7;
    address public constant DAI = 0x6B175474E89094C44Da98b954EedeAC495271d0F;
    address public constant USDS = 0xdC035D45d973E3EC169d2276DDab16f1e407384F;
    address public constant SUSDS = 0xa3931d71877C0E7a3148CB7Eb4463524FEc27fbD;
    address public constant USDS_MIGRATION = 0xf86141a5657Cf52AEB3E30eBccA5Ad3a8f714B89;

    // Uniswap V3 USDT/DAI pool
    address public constant UNISWAP_V3_POOL = 0x48DA0965ab2d2cbf1C17C09cFB5Cbe67Ad5B1406;

    address public DAI_SUSDS_WRAPPER = address(new DaiToSusdsWrapper{salt: bytes32(0)}(DAI, USDS_MIGRATION, USDS, SUSDS));

    function test_exchangeOutUsdtToDai() public {
        _test_exchangeConnectorOut(USDT, USDT, SUSDS, DAI, 100e18, address(0), DAI_SUSDS_WRAPPER);
    }

    function test_exchangeInUsdtToDai() public {
        _test_exchangeConnectorIn(USDT, USDT, SUSDS, DAI, 100e6, address(0), DAI_SUSDS_WRAPPER);
    }

    function deployExchangeConnector() internal override returns (IExchangeConnector) {
        return new UniswapV3ExchangeConnector{salt: bytes32(0)}(UNISWAP_V3_POOL);
    }
}
