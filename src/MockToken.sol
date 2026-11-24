// SPDX-License-Identifier: MIT
pragma solidity ^0.8.29;

import { ERC20 } from "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import { Ownable } from "@openzeppelin/contracts/access/Ownable.sol";

/// @title Mock ERC20 for the Sentinel Vault demo.
/// @notice Two instances are deployed on Base Sepolia: a volatile asset (mVOL) users deposit,
///         and a stable asset (mUSDC) the vault exits into. Minting is owner-only (the deployer
///         seeds the vault's stable reserve and funds demo users). 18 decimals throughout so
///         the oracle price math stays in one fixed-point scale.
contract MockToken is ERC20, Ownable {
    /// @param name_ Token name (e.g. "Sentinel Volatile").
    /// @param symbol_ Token symbol (e.g. "mVOL").
    constructor(string memory name_, string memory symbol_) ERC20(name_, symbol_) Ownable(msg.sender) {}

    /// @notice Mints `amount_` to `to_`. Owner only.
    function mint(address to_, uint256 amount_) external onlyOwner {
        _mint(to_, amount_);
    }
}
