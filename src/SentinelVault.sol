// SPDX-License-Identifier: MIT
pragma solidity ^0.8.29;

import { IERC20 } from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import { SafeERC20 } from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import { ReentrancyGuard } from "@openzeppelin/contracts/utils/ReentrancyGuard.sol";
import { Ownable } from "@openzeppelin/contracts/access/Ownable.sol";
import { IPayable } from "./reactive/IPayable.sol";
import { AbstractCallback } from "./reactive/AbstractCallback.sol";

/// @title Sentinel Vault — oracle-triggered exit guard (Base Sepolia).
/// @notice Users deposit a volatile mock asset (mVOL). When the Reactive sentinel on Lasna
///         observes the price breach its threshold, it requests a callback to `exitToStable`,
///         which swaps the user's whole mVOL balance into the stable mock asset (mUSDC) at the
///         breached price, from the vault's pre-funded stable reserve. The user then withdraws
///         mUSDC via `withdrawStable`.
/// @dev Callback contract (Omni): `exitToStable` is callable ONLY through the Base Sepolia
///      callback proxy (`onlyServiceProvider`) AND only when the injected sender is the
///      authorized Reactive sentinel (`onlyCallbackSender`). The first payload argument is the
///      injected reactive address and MUST be passed as address(0) by the requester.
///      The armed/disarmed state machine lives on the sentinel (Lasna), where the decision is
///      made; the vault is idempotent — an exit for a zero balance is a graceful no-op, so a
///      duplicate or stale callback can never drain anything ("Already Exited" handled).
///      `exitToStable` is nonReentrant: a malicious token callback during the stable transfer
///      cannot re-enter the exit.
///      The stable reserve is simply the vault's own mUSDC balance; the deployer must seed it
///      (via a plain mUSDC transfer) to at least the largest expected exit.
contract SentinelVault is AbstractCallback, ReentrancyGuard, Ownable {
    using SafeERC20 for IERC20;

    /// @notice Emitted when a user deposits mVOL. `user` indexed; payload (amount, remaining, timestamp).
    event VaultDeposit(address indexed user, uint256 amount, uint256 remaining, uint256 timestamp);

    /// @notice Emitted when a user withdraws mVOL manually. `user` indexed; payload (amount, remaining, timestamp).
    event VaultWithdraw(address indexed user, uint256 amount, uint256 remaining, uint256 timestamp);

    /// @notice Emitted when the sentinel exits a user to stable. `user` indexed; payload (price, timestamp, stableAmount).
    event SentinelTriggered(address indexed user, uint256 price, uint256 timestamp, uint256 stableAmount);

    /// @notice Emitted when a user withdraws mUSDC. `user` indexed; payload (amount, timestamp).
    event StableWithdrawn(address indexed user, uint256 amount, uint256 timestamp);

    /// @notice Volatile asset users deposit (mVOL, 18 decimals).
    IERC20 public immutable volToken;

    /// @notice Stable asset exits convert into (mUSDC, 18 decimals).
    IERC20 public immutable stableToken;

    /// @notice mVOL balance per user.
    mapping(address => uint256) public balances;

    /// @notice mUSDC balance per user (after exits).
    mapping(address => uint256) public stableBalances;

    /// @param callbackProxy_ Base Sepolia callback proxy (0x476F44b11F5C942c58f4c8E3d0300E5710743585).
    /// @param reactive_ Authorized Reactive sentinel contract on Lasna (immutable).
    /// @param volToken_ mVOL token address.
    /// @param stableToken_ mUSDC token address.
    constructor(IPayable callbackProxy_, address reactive_, address volToken_, address stableToken_)
        payable
        AbstractCallback(callbackProxy_, reactive_)
        Ownable(msg.sender)
    {
        require(reactive_ != address(0), "SentinelVault: reactive is zero");
        require(volToken_ != address(0), "SentinelVault: vol token is zero");
        require(stableToken_ != address(0), "SentinelVault: stable token is zero");
        volToken = IERC20(volToken_);
        stableToken = IERC20(stableToken_);
    }

    /// @notice Deposits `amount_` mVOL. Emits VaultDeposit (the sentinel arms this user).
    function deposit(uint256 amount_) external nonReentrant {
        require(amount_ > 0, "SentinelVault: amount is zero");
        volToken.safeTransferFrom(msg.sender, address(this), amount_);
        balances[msg.sender] += amount_;
        emit VaultDeposit(msg.sender, amount_, balances[msg.sender], block.timestamp);
    }

    /// @notice Withdraws `amount_` mVOL manually. Emits VaultWithdraw (the sentinel disarms
    ///         this user when the remaining balance reaches zero).
    function withdraw(uint256 amount_) external nonReentrant {
        require(amount_ > 0, "SentinelVault: amount is zero");
        require(balances[msg.sender] >= amount_, "SentinelVault: insufficient balance");
        balances[msg.sender] -= amount_;
        volToken.safeTransfer(msg.sender, amount_);
        emit VaultWithdraw(msg.sender, amount_, balances[msg.sender], block.timestamp);
    }

    /// @notice Withdraws `amount_` mUSDC from the user's post-exit stable balance.
    function withdrawStable(uint256 amount_) external nonReentrant {
        require(amount_ > 0, "SentinelVault: amount is zero");
        require(stableBalances[msg.sender] >= amount_, "SentinelVault: insufficient stable balance");
        stableBalances[msg.sender] -= amount_;
        stableToken.safeTransfer(msg.sender, amount_);
        emit StableWithdrawn(msg.sender, amount_, block.timestamp);
    }

    /// @notice Sentinel callback: exits `user_`'s whole mVOL balance into mUSDC at `price_`.
    /// @dev Called by the Base Sepolia callback proxy with the first payload argument
    ///      overwritten to the requesting Reactive sentinel's address. `price_` and
    ///      `timestamp_` come from the ORIGIN PriceUpdated event payload (never Lasna time).
    ///      Graceful no-op when the user holds nothing (already exited / already withdrew),
    ///      so a duplicate callback costs gas but cannot revert the loop or drain funds.
    /// @param reactive_ Injected address of the requesting Reactive sentinel.
    /// @param user_ User to exit.
    /// @param price_ Breached price (USD per mVOL, 18 decimals) from the origin event.
    /// @param timestamp_ Origin block timestamp from the PriceUpdated event.
    function exitToStable(address reactive_, address user_, uint256 price_, uint256 timestamp_)
        external
        nonReentrant
        onlyServiceProvider
        onlyCallbackSender(reactive_)
    {
        uint256 volBalance_ = balances[user_];
        if (volBalance_ == 0) {
            return;
        }
        uint256 stableAmount_ = (volBalance_ * price_) / 1e18;
        require(stableAmount_ > 0, "SentinelVault: stable amount is zero");
        require(
            stableToken.balanceOf(address(this)) >= stableAmount_,
            "SentinelVault: insufficient stable reserve"
        );
        balances[user_] = 0;
        stableBalances[user_] += stableAmount_;
        emit SentinelTriggered(user_, price_, timestamp_, stableAmount_);
    }
}
