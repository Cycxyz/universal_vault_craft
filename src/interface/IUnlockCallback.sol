// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.28;

interface IUnlockCallback {
    function unlockCallback(bytes calldata data) external returns (bytes memory);
}
