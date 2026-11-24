// SPDX-License-Identifier: MIT
pragma solidity ^0.8.29;

/// @title Interface for reactive contracts (Omni).
/// @notice Vendored from the CURRENT Reactive docs (dev.reactive.network, read 24 Nov 2026).
/// @dev Field names are the docs' camelCase form. `data` holds the ABI-encoded NON-indexed
///      parameters only; `opCode` is how many topics the original log had (check it before
///      decoding); `blockHash`/`txHash` are uint256, cast to bytes32 when comparing.
interface IReactive {
    struct LogRecord {
        uint256 chainId;
        address contractAddress;
        uint256 topic0;
        uint256 topic1;
        uint256 topic2;
        uint256 topic3;
        bytes data;
        uint256 blockNumber;
        uint256 opCode;
        uint256 blockHash;
        uint256 txHash;
        uint256 logIndex;
    }

    /// @notice Entry point for event notifications; called by the system contract only.
    /// @param log_ Normalized form of the matching EVM log.
    function react(LogRecord memory log_) external;
}
