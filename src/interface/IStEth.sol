// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.28;

interface IStEth {
    function totalSupply() external view returns (uint256);
    function getTotalShares() external view returns (uint256);
}
