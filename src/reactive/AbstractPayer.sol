// SPDX-License-Identifier: MIT
pragma solidity ^0.8.29;

import "./IPayable.sol";
import "./IPayer.sol";

/// @title Abstract base for contracts that pay the system contract or a callback proxy.
/// @notice Vendored from the CURRENT Reactive docs (dev.reactive.network, read 24 Nov 2026).
/// @dev Holds a single immutable `_SERVICE_PROVIDER` (SYSTEM for reactive contracts, the
///      callback proxy for callback contracts). The service provider bills the contract;
///      charges draw on reserves first, then `pay()` settles any shortfall from the balance.
abstract contract AbstractPayer is IPayer {
    /// @notice The contract allowed to bill this contract (SYSTEM or callback proxy).
    IPayable internal immutable _SERVICE_PROVIDER;

    /// @notice Thrown when a caller other than the service provider attempts a restricted call.
    error NotAuthorized();

    constructor(IPayable serviceProvider_) {
        _SERVICE_PROVIDER = serviceProvider_;
    }

    /// @notice Accepts native currency (REACT on Reactive, ETH/etc. on destination chains).
    receive() external payable virtual override {}

    /// @notice Rejects calls from anyone but the service provider.
    modifier onlyServiceProvider() {
        if (msg.sender != address(_SERVICE_PROVIDER)) revert NotAuthorized();
        _;
    }

    /// @notice Called by the service provider to settle `amount_` of outstanding debt.
    /// @dev Transfers `amount_` to the caller (the service provider). Do not write your own.
    function pay(uint256 amount_) external virtual override onlyServiceProvider {
        _pay(payable(msg.sender), amount_);
    }

    /// @notice Settles outstanding debt from this contract's own balance.
    /// @dev Internal: expose it yourself (e.g. `coverDebt()`) if an outside call should trigger it.
    function _coverDebt() internal {
        uint256 amount_ = _SERVICE_PROVIDER.debt(address(this));
        _pay(payable(_SERVICE_PROVIDER), amount_);
    }

    /// @notice Transfers `amount_` to `recipient_`; reverts if the balance is insufficient.
    function _pay(address payable recipient_, uint256 amount_) internal {
        require(address(this).balance >= amount_, "AbstractPayer: insufficient funds");
        if (amount_ > 0) {
            (bool success_, ) = recipient_.call{ value: amount_ }("");
            require(success_, "AbstractPayer: transfer failed");
        }
    }
}
