// SPDX-License-Identifier: MIT
pragma solidity ^0.8.29;

import "./IReactive.sol";
import "./ISystemContract.sol";
import "./AbstractPayer.sol";

/// @title Abstract base contract for reactive contracts (Omni).
/// @notice Vendored from the CURRENT Reactive docs (dev.reactive.network, read 24 Nov 2026).
/// @dev The published reactive-lib on GitHub is LEGACY (0xfffFfF system contract, RVM-based)
///      and does not match the current Omni docs; this base implements the Omni API exactly
///      as documented: SYSTEM at 0x8888..., `react(LogRecord memory)` guarded by `onlySystem`.
abstract contract AbstractReactive is IReactive, AbstractPayer {
    /// @notice Wildcard value for any topic position in a subscription.
    uint256 internal constant REACTIVE_IGNORE =
        0xa65f96fc951c35ead38878e0f0b7a3c744a6f5ccc1476b313353ce31712313ad;

    /// @notice The system contract on both Reactive Mainnet and Lasna Testnet.
    ISystemContract internal constant SYSTEM =
        ISystemContract(payable(0x8888888888888888888888888888888888888888));

    constructor() AbstractPayer(SYSTEM) {}

    /// @notice Rejects `react()` calls from anyone but the system contract.
    /// @dev Same check as `onlyServiceProvider`, under a clearer name.
    modifier onlySystem() {
        if (msg.sender != address(SYSTEM)) revert NotAuthorized();
        _;
    }

    /// @inheritdoc IReactive
    function react(LogRecord memory log_) external virtual override;
}
