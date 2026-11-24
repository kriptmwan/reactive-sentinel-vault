// SPDX-License-Identifier: MIT
pragma solidity ^0.8.29;

import "./IPayable.sol";
import "./AbstractPayer.sol";

/// @title Abstract base contract for contracts receiving Reactive Network callbacks (Omni).
/// @notice Vendored from the CURRENT Reactive docs (dev.reactive.network, read 24 Nov 2026).
/// @dev Both guards must be used on every callback method, always:
///      - `onlyServiceProvider`: the caller is the callback proxy (else anyone could call the
///        method directly and forge the first argument).
///      - `onlyCallbackSender(reactive_)`: the injected first argument is the reactive contract
///        authorized at construction (else any reactive contract could drive the callback
///        through the legitimate proxy).
abstract contract AbstractCallback is AbstractPayer {
    /// @notice The reactive contract authorized to trigger callbacks.
    address internal immutable _CALLBACK_SENDER;

    /// @notice Thrown when the injected sender is not the authorized reactive contract.
    error CallbackNotAuthorized();

    constructor(IPayable callbackProxy_, address callbackSender_)
        AbstractPayer(callbackProxy_)
    {
        _CALLBACK_SENDER = callbackSender_;
    }

    /// @notice Rejects callbacks whose injected sender is not the authorized reactive contract.
    modifier onlyCallbackSender(address reactive_) {
        if (reactive_ != _CALLBACK_SENDER) revert CallbackNotAuthorized();
        _;
    }

    /// @notice Settles outstanding debt from this contract's own balance.
    function coverDebt() external {
        _coverDebt();
    }
}
