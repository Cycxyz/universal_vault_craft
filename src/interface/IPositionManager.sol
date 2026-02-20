// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.28;

import {IPoolManager} from "./IPoolManager.sol";
interface IPositionManager {


    function poolKeys(bytes25 poolId) external view returns (IPoolManager.PoolKey memory);
}
