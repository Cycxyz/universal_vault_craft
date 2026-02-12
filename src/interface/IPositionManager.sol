// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.28;

import {PoolKey} from "../types/UniswapV4Structs.sol";

interface IPositionManager {
    function poolKeys(bytes25 poolId) external view returns (PoolKey memory);
}