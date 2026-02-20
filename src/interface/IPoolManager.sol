// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.28;

interface IPoolManager {
    struct SwapParams {
        bool zeroForOne;
        int256 amountSpecified;
        uint160 sqrtPriceLimitX96;
    }

    struct PoolKey {
        address currency0;
        address currency1;
        uint24 fee;
        int24 tickSpacing;
        address hooks;
    }

    function unlock(bytes calldata data) external returns (bytes memory);
    function swap(PoolKey memory key, SwapParams memory params, bytes calldata hookData)
        external
        returns (int256 swapDelta);
    function settle() external payable returns (uint256 paid);
    function take(address currency, address to, uint256 amount) external;
    function sync(address currency) external;
}
