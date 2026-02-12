// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.28;

import {PoolKey} from "../types/UniswapV4Structs.sol";
import {SwapParams} from "../types/UniswapV4Structs.sol";

interface IPoolManager {
    function unlock(bytes calldata data) external returns (bytes memory);
    function swap(PoolKey memory key, SwapParams memory params, bytes calldata hookData)
        external
        returns (int256 swapDelta);
    function settle() external payable returns (uint256 paid);
    function take(address currency, address to, uint256 amount) external;
    function sync(address currency) external;
}
