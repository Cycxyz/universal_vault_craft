// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.28;

import {Test} from "forge-std/Test.sol";
import {MorphoFlashLoanConnector} from "../src/flash_loan_connectors/MorphoFlashLoanConnector.sol";
import {FlashLoanBorrower} from "./utils/FlashLoanBorrower.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";

contract MorphoFlashLoanConnectorTest is Test {
    MorphoFlashLoanConnector public connector;
    FlashLoanBorrower public borrower;

    address public constant MORPHO_MAINNET = 0xBBBBBbbBBb9cC5e90e3b3Af64bdAF62C37EEFFCb;
    address public constant WETH = 0xC02aaA39b223FE8D0A0e5C4F27eAD9083C756Cc2;

    uint256 public constant FLASH_LOAN_AMOUNT = 1e18;
    uint256 public constant FORK_BLOCK = 24_432_467;

    function setUp() public {
        string memory rpcUrl = vm.envString("RPC_MAINNET");
        vm.createSelectFork(rpcUrl, FORK_BLOCK);

        connector = new MorphoFlashLoanConnector(MORPHO_MAINNET);
        borrower = new FlashLoanBorrower();
        borrower.setFlashLoanParams(address(connector), WETH, FLASH_LOAN_AMOUNT);
    }

    function test_flashLoan_onlyMorphoCanCallOnMorphoFlashLoan() public {
        vm.expectRevert(MorphoFlashLoanConnector.OnlyMorpho.selector);
        connector.onMorphoFlashLoan(FLASH_LOAN_AMOUNT, abi.encode(address(borrower), ""));
    }

    function test_flashLoan_fullFlow() public {
        uint256 morphoBalanceBefore = IERC20(WETH).balanceOf(MORPHO_MAINNET);
        uint256 borrowerBalanceBefore = IERC20(WETH).balanceOf(address(borrower));

        borrower.executeFlashLoan();

        assertTrue(borrower.callbackReceived());
        assertEq(IERC20(WETH).balanceOf(MORPHO_MAINNET), morphoBalanceBefore, "Morpho should have received repayment");
        assertEq(IERC20(WETH).balanceOf(address(borrower)), borrowerBalanceBefore, "Borrower balance should be the same");
    }

    function test_flashLoan_callbackReverts() public {
        vm.expectRevert(MorphoFlashLoanConnector.FlashLoanCallbackFailed.selector);
        borrower.executeFlashLoanAndRevert();
    }

    function test_returnFlashLoan_pullsAndApprovesMorpho() public {
        deal(WETH, address(this), FLASH_LOAN_AMOUNT);
        IERC20(WETH).approve(address(connector), FLASH_LOAN_AMOUNT);

        connector.returnFlashLoan(WETH, FLASH_LOAN_AMOUNT);

        assertEq(IERC20(WETH).balanceOf(address(connector)), FLASH_LOAN_AMOUNT);
        assertEq(IERC20(WETH).allowance(address(connector), MORPHO_MAINNET), FLASH_LOAN_AMOUNT);
    }

    function test_flashLoan_forwardsCorrectDataToMorpho() public {
        deal(WETH, address(borrower), FLASH_LOAN_AMOUNT);
        // borrower.approve(address(connector), FLASH_LOAN_AMOUNT);

        bytes memory userData = abi.encodeCall(FlashLoanBorrower.onFlashLoanCallback, ());
        vm.prank(address(borrower));
        connector.flashLoan(WETH, FLASH_LOAN_AMOUNT, userData);

        assertTrue(borrower.callbackReceived());
    }
}
