// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.28;

import {IFlashLoanConnector} from "../interface/IFlashLoanConnector.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";

interface IMorpho {
    function flashLoan(address token, uint256 assets, bytes calldata data) external;
}

interface IMorphoFlashLoanCallback {
    function onMorphoFlashLoan(uint256 assets, bytes calldata data) external;
}

contract MorphoFlashLoanConnector is IFlashLoanConnector, IMorphoFlashLoanCallback {
    using SafeERC20 for IERC20;

    error OnlyMorpho();
    error FlashLoanCallbackFailed();

    IMorpho public immutable MORPHO;

    constructor(address morpho) {
        MORPHO = IMorpho(morpho);
    }

    function flashLoan(address token, uint256 amount, bytes memory data) external override {
        MORPHO.flashLoan(token, amount, abi.encode(msg.sender, token, amount, data));
    }

    function onMorphoFlashLoan(uint256, bytes calldata data) external override {
        require(msg.sender == address(MORPHO), OnlyMorpho());
        (address initiator, address token, uint256 amount, bytes memory callbackData) = abi.decode(data, (address, address, uint256, bytes));

        IERC20(token).safeTransfer(initiator, amount);

        (bool success, ) = initiator.call(callbackData);
        require(success, FlashLoanCallbackFailed());
    }

    function returnFlashLoan(address token, uint256 amount) external override {
        IERC20(token).safeTransferFrom(msg.sender, address(this), amount);
        IERC20(token).forceApprove(address(MORPHO), amount);
    }
}
