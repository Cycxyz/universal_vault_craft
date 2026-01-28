// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.28;

interface IFlashLoanConnector {
    function flashLoan(address token, uint256 amount, bytes memory data) external;
    function returnFlashLoan(address token, uint256 amount) external;
}