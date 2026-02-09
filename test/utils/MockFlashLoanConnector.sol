// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.28;

import {IFlashLoanConnector} from "../../src/interface/IFlashLoanConnector.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import {StdCheats} from "forge-std/StdCheats.sol";

contract MockFlashLoanConnector is IFlashLoanConnector, StdCheats {
    using SafeERC20 for IERC20;

    error FlashLoanCallbackFailed();

    function flashLoan(address token, uint256 amount, bytes memory data) external override {
        uint256 balance = IERC20(token).balanceOf(address(this));
        if (balance < amount) {
            deal(token, address(this), amount);
        }
        
        IERC20(token).safeTransfer(msg.sender, amount);
        
        (bool success, ) = msg.sender.call(data);
        if (!success) {
            revert FlashLoanCallbackFailed();
        }
    }

    function returnFlashLoan(address token, uint256 amount) external override {
        IERC20(token).safeTransferFrom(msg.sender, address(this), amount);
    }
}
