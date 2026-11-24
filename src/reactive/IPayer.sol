// SPDX-License-Identifier: MIT
pragma solidity ^0.8.29;

/// @title Common interface for contracts that pay the system contract / callback proxies.
/// @notice Vendored from the CURRENT Reactive docs (dev.reactive.network, read 24 Nov 2026).
interface IPayer {
    /// @notice Called by the system contract / proxy when payment is due.
    /// @dev Implementations MUST check msg.sender (onlyServiceProvider).
    /// @param amount_ Amount owed for reactive transactions and/or callbacks.
    function pay(uint256 amount_) external;

    /// @notice Accepts funds for operational expenses.
    receive() external payable;
}
