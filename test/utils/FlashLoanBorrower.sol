// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.28;

import {IFlashLoanConnector} from "../../src/interface/IFlashLoanConnector.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {console} from "forge-std/console.sol";

/// @notice Initiator contract that receives the flash loan callback and can return the loan
contract FlashLoanBorrower {
    IFlashLoanConnector public connector;
    address public token;
    uint256 public amount;
    bool public callbackReceived;

    function setFlashLoanParams(address _connector, address _token, uint256 _amount) external {
        connector = IFlashLoanConnector(_connector);
        token = _token;
        amount = _amount;
    }

    function executeFlashLoan() external {
        bytes memory callbackData = abi.encodeCall(FlashLoanBorrower.onFlashLoanCallback, ());
        connector.flashLoan(token, amount, callbackData);
    }

    function onFlashLoanCallback() external {
        callbackReceived = true;
        IERC20(token).approve(address(connector), amount);
        connector.returnFlashLoan(token, amount);
    }

    function executeFlashLoanAndRevert() external {
        bytes memory callbackData = abi.encodeCall(FlashLoanBorrower.onFlashLoanCallbackRevert, ());
        connector.flashLoan(token, amount, callbackData);
    }

    function onFlashLoanCallbackRevert() external pure {
        revert("CallbackReverted");
    }
}
