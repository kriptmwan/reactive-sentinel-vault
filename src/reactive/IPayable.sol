// SPDX-License-Identifier: MIT
pragma solidity ^0.8.29;

/// @title Common interface for the system contract and callback proxies.
/// @notice Vendored from the CURRENT Reactive docs (dev.reactive.network, read 24 Nov 2026).
/// @dev The published reactive-lib on GitHub is the LEGACY library (0xfffFfF system contract,
///      vm/detectVm, no requestCallbackV_1_0) and does NOT match the current Omni docs, so the
///      Omni interfaces are implemented here exactly as the docs specify.
interface IPayable {
    /// @notice Accepts native currency (REACT on Reactive, ETH/etc. on destination chains).
    receive() external payable;

    /// @notice Credits reserves for `recipient_`; settles outstanding debt first.
    function depositTo(address recipient_) external payable;

    /// @notice Outstanding debt of `contract_` (fees owed but not yet paid).
    function debt(address contract_) external view returns (uint256);

    /// @notice Pre-paid reserves of `contract_` held by the system contract / proxy.
    function reserves(address contract_) external view returns (uint256);
}
