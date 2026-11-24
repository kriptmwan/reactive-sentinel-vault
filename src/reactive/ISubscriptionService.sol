// SPDX-License-Identifier: MIT
pragma solidity ^0.8.29;

import "./IPayable.sol";

/// @title Interface for the event subscription service.
/// @notice Vendored from the CURRENT Reactive docs (dev.reactive.network, read 24 Nov 2026).
interface ISubscriptionService is IPayable {
    /// @notice Subscribes the calling contract to events matching the criteria.
    /// @param chainId_ EIP-155 source chain ID, or 0 for all chains.
    /// @param contract_ Contract address to monitor, or address(0) for all contracts.
    /// @param topic0_ Topic 0 to monitor, or REACTIVE_IGNORE for any value.
    /// @param topic1_ Topic 1 to monitor, or REACTIVE_IGNORE for any value.
    /// @param topic2_ Topic 2 to monitor, or REACTIVE_IGNORE for any value.
    /// @param topic3_ Topic 3 to monitor, or REACTIVE_IGNORE for any value.
    function subscribe(
        uint256 chainId_,
        address contract_,
        uint256 topic0_,
        uint256 topic1_,
        uint256 topic2_,
        uint256 topic3_
    ) external;

    /// @notice Removes the subscription matching all six criteria exactly.
    function unsubscribe(
        uint256 chainId_,
        address contract_,
        uint256 topic0_,
        uint256 topic1_,
        uint256 topic2_,
        uint256 topic3_
    ) external;
}
