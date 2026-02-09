// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.28;

import {ILowLevelVault} from "../../interface/ILowLevelVault.sol";
import {IFlashLoanConnector} from "../../interface/IFlashLoanConnector.sol";
import {IExchangeConnector} from "../../interface/IExchangeConnector.sol";
import {SafeERC20, IERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";

contract MintWithNegativeFlashLoanBorrow {
    using SafeERC20 for IERC20;
    using SafeERC20 for ILowLevelVault;

    error MintWithNegativeFlashLoanBorrowSlippageExceeded(uint256 userAssetsIn, uint256 maxBorrowAssets);

    struct MintWithNegativeFlashLoanBorrowInput {
        int256 deltaShares;
        int256 deltaCollateral;
        int256 deltaBorrow;
        address borrowFlashLoan;
        address collateralToBorrowExchange;
        address vault;
        address user;
        address collateralAsset;
        address borrowAsset;
        uint256 maxAssetsBorrow;
    }

    struct MintWithNegativeFlashLoanBorrowCallbackPayload {
        int256 deltaShares;
        address borrowFlashLoan;
        address collateralToBorrowExchange;
        address vault;
        address user;
        address collateralAsset;
        address borrowAsset;
        uint256 maxAssetsBorrow;
        int256 deltaCollateral;
        int256 deltaBorrow;
    }

    function mintWithNegativeFlashLoanBorrow(MintWithNegativeFlashLoanBorrowInput memory input)
        internal
        returns (uint256)
    {
        uint256 userBorrowBalance = IERC20(input.borrowAsset).balanceOf(input.user);
        MintWithNegativeFlashLoanBorrowCallbackPayload memory payload = MintWithNegativeFlashLoanBorrowCallbackPayload({
            deltaShares: input.deltaShares,
            borrowFlashLoan: input.borrowFlashLoan,
            collateralToBorrowExchange: input.collateralToBorrowExchange,
            vault: input.vault,
            user: input.user,
            collateralAsset: input.collateralAsset,
            borrowAsset: input.borrowAsset,
            maxAssetsBorrow: input.maxAssetsBorrow,
            deltaCollateral: input.deltaCollateral,
            deltaBorrow: input.deltaBorrow
        });
        IFlashLoanConnector(input.borrowFlashLoan).flashLoan(
            input.borrowAsset,
            uint256(-input.deltaBorrow),
            abi.encodeCall(MintWithNegativeFlashLoanBorrow.mintWithNegativeFlashLoanBorrowFallback, (payload))
        );

        return userBorrowBalance - IERC20(input.borrowAsset).balanceOf(input.user);
    }

    function mintWithNegativeFlashLoanBorrowFallback(MintWithNegativeFlashLoanBorrowCallbackPayload calldata payload)
        external
    {
        IERC20(payload.borrowAsset).forceApprove(payload.vault, uint256(-payload.deltaBorrow));
        ILowLevelVault(payload.vault).executeLowLevelRebalanceShares(payload.deltaShares);

        IERC20(payload.collateralAsset).forceApprove(
            payload.collateralToBorrowExchange, uint256(-payload.deltaCollateral)
        );
        uint256 borrowAssetsOut = IExchangeConnector(payload.collateralToBorrowExchange).exchangeIn(
            payload.collateralAsset, payload.borrowAsset, uint256(-payload.deltaCollateral), 0
        );

        uint256 borrowNeeded = uint256(-payload.deltaBorrow);
        uint256 userAssetsIn = borrowAssetsOut >= borrowNeeded ? 0 : borrowNeeded - borrowAssetsOut;
        require(
            userAssetsIn <= payload.maxAssetsBorrow,
            MintWithNegativeFlashLoanBorrowSlippageExceeded(userAssetsIn, payload.maxAssetsBorrow)
        );
        IERC20(payload.borrowAsset).safeTransferFrom(payload.user, address(this), userAssetsIn);

        IERC20(payload.vault).safeTransfer(payload.user, uint256(payload.deltaShares));

        IERC20(payload.borrowAsset).forceApprove(payload.borrowFlashLoan, uint256(-payload.deltaBorrow));
        IFlashLoanConnector(payload.borrowFlashLoan).returnFlashLoan(payload.borrowAsset, uint256(-payload.deltaBorrow));
    }
}
