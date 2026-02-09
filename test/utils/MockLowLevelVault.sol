// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.28;

import {ILowLevelVault} from "../../src/interface/ILowLevelVault.sol";
import {ERC20} from "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import {SafeERC20, IERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import {StdCheats} from "forge-std/StdCheats.sol";

contract MockLowLevelVault is ERC20, StdCheats, ILowLevelVault {
    using SafeERC20 for IERC20;

    uint256 public borrowPrice;
    uint256 public collateralPrice;
    uint256 public sharePrice;
    address public borrowAsset;
    address public collateralAsset;

    int256 public deltaCollateral;
    int256 public deltaBorrow;
    int256 public deltaShares;

    constructor(
        uint256 _borrowPrice,
        uint256 _collateralPrice,
        uint256 _sharePrice,
        address _borrowAsset,
        address _collateralAsset
    )
        ERC20("Mock Vault Shares", "MVS")
    {
        borrowPrice = _borrowPrice;
        collateralPrice = _collateralPrice;
        sharePrice = _sharePrice;
        borrowAsset = _borrowAsset;
        collateralAsset = _collateralAsset;
    }

    function setResult(int256 _deltaCollateral, int256 _deltaBorrow, int256 _deltaShares) external {
        deltaCollateral = _deltaCollateral;
        deltaBorrow = _deltaBorrow;
        deltaShares = _deltaShares;
        _checkResultValidity();
    }

    function _checkResultValidity() internal view {
        require(
            deltaCollateral * int256(collateralPrice)
                == deltaBorrow * int256(borrowPrice) + deltaShares * int256(sharePrice),
            "Invalid result"
        );
    }

    function previewLowLevelRebalanceShares(int256 _deltaShares)
        external
        view
        override
        returns (int256 _deltaCollateral, int256 _deltaBorrow)
    {
        require(deltaShares == _deltaShares, "Invalid deltaShares");
        _checkResultValidity();

        return (deltaCollateral, deltaBorrow);
    }

    function executeLowLevelRebalanceShares(int256 _deltaShares)
        external
        override
        returns (int256 _deltaCollateral, int256 _deltaBorrow)
    {
        require(deltaShares == _deltaShares, "Invalid deltaShares");
        _checkResultValidity();

        if (deltaShares > 0) {
            _mint(msg.sender, uint256(deltaShares));
        } else {
            _burn(msg.sender, uint256(-deltaShares));
        }

        if (deltaCollateral > 0) {
            IERC20(collateralAsset).safeTransferFrom(msg.sender, address(this), uint256(deltaCollateral));
        } else {
            deal(collateralAsset, address(this), uint256(-deltaCollateral));
            IERC20(collateralAsset).safeTransfer(msg.sender, uint256(-deltaCollateral));
        }

        if (deltaBorrow > 0) {
            deal(borrowAsset, address(this), uint256(deltaBorrow));
            IERC20(borrowAsset).safeTransfer(msg.sender, uint256(deltaBorrow));
        } else {
            IERC20(borrowAsset).safeTransferFrom(msg.sender, address(this), uint256(-deltaBorrow));
        }

        return (deltaCollateral, deltaBorrow);
    }
}
