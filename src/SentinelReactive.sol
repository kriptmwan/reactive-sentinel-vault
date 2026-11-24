// SPDX-License-Identifier: MIT
pragma solidity ^0.8.29;

import { Ownable } from "@openzeppelin/contracts/access/Ownable.sol";
import { IReactive } from "./reactive/IReactive.sol";
import { ISystemContract } from "./reactive/ISystemContract.sol";
import { AbstractReactive } from "./reactive/AbstractReactive.sol";

/// @title Sentinel Reactive — oracle-triggered exit guard, decision side (Reactive Lasna).
/// @notice Subscribes to Base Sepolia events and decides, entirely on-chain, when a vault
///         user must be exited to stable. No off-chain keeper, no polling, no key custody:
///         every action is caused by an origin event arriving at `react()`.
/// @dev STATE MACHINE (per user) — this is what makes the loop NOT cron-equivalent:
///      - ARMED on VaultDeposit (user has funds at risk).
///      - EXIT on the FIRST PriceUpdated below `threshold` after arming: requests the
///        `exitToStable` callback on Base Sepolia, then DISARMS. Later price updates below
///        the threshold do nothing — a cron job polling the oracle would re-fire every tick;
///        this fires exactly once per arming.
///      - RE-ARMED on PriceRecovered (price back to threshold + 5%) or by owner `rearmUser`.
///      - DISARMED on VaultWithdraw to a zero remaining balance (user left manually).
///      Two-event composition: the exit requires BOTH a VaultDeposit (funds at risk) AND a
///      PriceUpdated breach — neither event alone can trigger an exit.
///      Unknown logs fall through silently: reverting as a filter is a mistake (the system
///      contract catches the revert, emits ReactiveContractReverted, and still bills gas).
///      Timestamps used in callbacks come from the ORIGIN event payload, never Lasna time.
///      Deployment order (docs): deploy this contract first (oracle known upfront), then the
///      Vault with this address, then `setVault` (owner-only, once) to subscribe to the
///      Vault's events and name it as the callback recipient.
contract SentinelReactive is AbstractReactive, Ownable {
    /// @notice Base Sepolia chain ID (origin + destination).
    uint256 public constant BASE_SEPOLIA_CHAIN_ID = 84532;

    /// @notice Gas limit for the exitToStable callback (docs minimum is 100,000).
    uint64 public constant CALLBACK_GAS_LIMIT = 500_000;

    /// @notice Topic 0 of PriceOracle.PriceUpdated(uint256,uint256).
    uint256 public constant PRICE_UPDATED_TOPIC = uint256(keccak256("PriceUpdated(uint256,uint256)"));

    /// @notice Topic 0 of PriceOracle.PriceRecovered(uint256,uint256).
    uint256 public constant PRICE_RECOVERED_TOPIC =
        uint256(keccak256("PriceRecovered(uint256,uint256)"));

    /// @notice Topic 0 of SentinelVault.VaultDeposit(address,uint256,uint256,uint256).
    uint256 public constant VAULT_DEPOSIT_TOPIC =
        uint256(keccak256("VaultDeposit(address,uint256,uint256,uint256)"));

    /// @notice Topic 0 of SentinelVault.VaultWithdraw(address,uint256,uint256,uint256).
    uint256 public constant VAULT_WITHDRAW_TOPIC =
        uint256(keccak256("VaultWithdraw(address,uint256,uint256,uint256)"));

    /// @notice Emitted when a user becomes armed (deposit observed).
    event UserArmed(address indexed user, uint256 timestamp);

    /// @notice Emitted when an exit callback is requested for a user.
    event ExitRequested(address indexed user, uint256 price, uint256 timestamp);

    /// @notice Emitted when a user is re-armed after a price recovery.
    event UserRearmed(address indexed user, uint256 timestamp);

    /// @notice Emitted when a user is disarmed (manual withdrawal to zero).
    event UserDisarmed(address indexed user, uint256 timestamp);

    /// @notice Price oracle on Base Sepolia.
    address public immutable oracle;

    /// @notice Breach threshold (USD per mVOL, 18 decimals). Exit fires below this.
    uint256 public immutable threshold;

    /// @notice Vault on Base Sepolia (callback recipient). Set once via `setVault`.
    address public vault;

    /// @notice Per-user armed state. True = the next breach exits this user.
    mapping(address => bool) public isArmed;

    /// @notice Every user ever armed (append-only; drives breach/recovery iteration).
    address[] public trackedUsers;

    /// @notice True once `user_` has been appended to `trackedUsers`.
    mapping(address => bool) internal _tracked;

    /// @param oracle_ PriceOracle address on Base Sepolia.
    /// @param threshold_ Breach threshold (18 decimals). Must match the oracle's threshold.
    constructor(address oracle_, uint256 threshold_) payable Ownable(msg.sender) {
        require(oracle_ != address(0), "SentinelReactive: oracle is zero");
        require(threshold_ > 0, "SentinelReactive: threshold is zero");
        oracle = oracle_;
        threshold = threshold_;
        _subscribeToOracle();
    }

    /// @notice Names the Vault and subscribes to its deposit/withdraw events. Owner only, once.
    /// @dev Must be called after the Vault is deployed with this contract as its reactive sender.
    function setVault(address vault_) external onlyOwner {
        require(vault == address(0), "SentinelReactive: vault already set");
        require(vault_ != address(0), "SentinelReactive: vault is zero");
        vault = vault_;
        SYSTEM.subscribe(
            BASE_SEPOLIA_CHAIN_ID,
            vault_,
            VAULT_DEPOSIT_TOPIC,
            REACTIVE_IGNORE,
            REACTIVE_IGNORE,
            REACTIVE_IGNORE
        );
        SYSTEM.subscribe(
            BASE_SEPOLIA_CHAIN_ID,
            vault_,
            VAULT_WITHDRAW_TOPIC,
            REACTIVE_IGNORE,
            REACTIVE_IGNORE,
            REACTIVE_IGNORE
        );
    }

    /// @notice Re-arms `user_` manually (owner reset). No-op if already armed.
    function rearmUser(address user_) external onlyOwner {
        if (!isArmed[user_]) {
            isArmed[user_] = true;
            emit UserRearmed(user_, block.timestamp);
        }
    }

    /// @notice Settles outstanding debt from this contract's own balance.
    function coverDebt() external {
        _coverDebt();
    }

    /// @notice Number of users ever tracked.
    function trackedUserCount() external view returns (uint256) {
        return trackedUsers.length;
    }

    /// @inheritdoc IReactive
    /// @dev Routes on topic0 first; unknown logs fall through (never revert as a filter).
    function react(LogRecord memory log_) external override onlySystem {
        if (log_.chainId != BASE_SEPOLIA_CHAIN_ID) {
            return;
        }
        if (log_.topic0 == PRICE_UPDATED_TOPIC && log_.opCode == 1) {
            (uint256 price_, uint256 timestamp_) = abi.decode(log_.data, (uint256, uint256));
            _onPriceUpdated(price_, timestamp_);
        } else if (log_.topic0 == PRICE_RECOVERED_TOPIC && log_.opCode == 1) {
            (uint256 price_, uint256 timestamp_) = abi.decode(log_.data, (uint256, uint256));
            _onPriceRecovered(price_, timestamp_);
        } else if (log_.topic0 == VAULT_DEPOSIT_TOPIC && log_.opCode == 2) {
            address user_ = address(uint160(log_.topic1));
            (uint256 amount_, , uint256 timestamp_) = abi.decode(
                log_.data,
                (uint256, uint256, uint256)
            );
            _onDeposit(user_, amount_, timestamp_);
        } else if (log_.topic0 == VAULT_WITHDRAW_TOPIC && log_.opCode == 2) {
            address user_ = address(uint160(log_.topic1));
            (, uint256 remaining_, uint256 timestamp_) = abi.decode(
                log_.data,
                (uint256, uint256, uint256)
            );
            _onWithdraw(user_, remaining_, timestamp_);
        }
    }

    /// @notice Subscribes to the oracle's PriceUpdated + PriceRecovered events.
    function _subscribeToOracle() internal {
        SYSTEM.subscribe(
            BASE_SEPOLIA_CHAIN_ID,
            oracle,
            PRICE_UPDATED_TOPIC,
            REACTIVE_IGNORE,
            REACTIVE_IGNORE,
            REACTIVE_IGNORE
        );
        SYSTEM.subscribe(
            BASE_SEPOLIA_CHAIN_ID,
            oracle,
            PRICE_RECOVERED_TOPIC,
            REACTIVE_IGNORE,
            REACTIVE_IGNORE,
            REACTIVE_IGNORE
        );
    }

    /// @notice Arms the depositor (funds now at risk). No-op if already armed.
    function _onDeposit(address user_, uint256 amount_, uint256 timestamp_) internal {
        if (amount_ == 0 || isArmed[user_]) {
            return;
        }
        isArmed[user_] = true;
        if (!_tracked[user_]) {
            _tracked[user_] = true;
            trackedUsers.push(user_);
        }
        emit UserArmed(user_, timestamp_);
    }

    /// @notice On breach: exit every armed user exactly once, then disarm them.
    /// @dev A price at or above the threshold does nothing here — recovery is handled by
    ///      the separate PriceRecovered event, keeping the two transitions distinct.
    function _onPriceUpdated(uint256 price_, uint256 timestamp_) internal {
        if (price_ >= threshold) {
            return;
        }
        require(vault != address(0), "SentinelReactive: vault not set");
        uint256 count_ = trackedUsers.length;
        for (uint256 i_; i_ < count_; ++i_) {
            address user_ = trackedUsers[i_];
            if (!isArmed[user_]) {
                continue;
            }
            isArmed[user_] = false;
            emit ExitRequested(user_, price_, timestamp_);
            _requestExit(user_, price_, timestamp_);
        }
    }

    /// @notice On recovery: re-arm every tracked user that is currently disarmed.
    function _onPriceRecovered(uint256 /* price_ */, uint256 timestamp_) internal {
        uint256 count_ = trackedUsers.length;
        for (uint256 i_; i_ < count_; ++i_) {
            address user_ = trackedUsers[i_];
            if (isArmed[user_]) {
                continue;
            }
            isArmed[user_] = true;
            emit UserRearmed(user_, timestamp_);
        }
    }

    /// @notice Disarms a user who manually withdrew their whole balance.
    function _onWithdraw(address user_, uint256 remaining_, uint256 timestamp_) internal {
        if (remaining_ == 0 && isArmed[user_]) {
            isArmed[user_] = false;
            emit UserDisarmed(user_, timestamp_);
        }
    }

    /// @notice Requests the exitToStable callback on Base Sepolia for `user_`.
    /// @dev Payload first argument is address(0): the network overwrites it with this
    ///      contract's address, which the Vault authenticates via onlyCallbackSender.
    function _requestExit(address user_, uint256 price_, uint256 timestamp_) internal {
        bytes memory payload_ = abi.encodeWithSignature(
            "exitToStable(address,address,uint256,uint256)",
            address(0),
            user_,
            price_,
            timestamp_
        );
        SYSTEM.requestCallbackV_1_0(
            ISystemContract.CallbackConfiguration_V_1_0({
                chainId: BASE_SEPOLIA_CHAIN_ID,
                recipient: vault,
                gasLimit: CALLBACK_GAS_LIMIT,
                payload: payload_
            })
        );
    }
}
