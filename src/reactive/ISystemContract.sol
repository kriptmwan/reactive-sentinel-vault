// SPDX-License-Identifier: MIT
pragma solidity ^0.8.29;

import "./IPayable.sol";
import "./ISubscriptionService.sol";

/// @title Interface for the Reactive Network system contract (Omni).
/// @notice Vendored from the CURRENT Reactive docs (dev.reactive.network, read 24 Nov 2026).
/// @dev System contract address on both Reactive Mainnet and Lasna Testnet:
///      0x8888888888888888888888888888888888888888
interface ISystemContract is IPayable, ISubscriptionService {
    /// @notice Callback version selector.
    enum CallbackVersion {
        V_1_0
    }

    /// @notice Configuration for a V_1_0 callback request.
    struct CallbackConfiguration_V_1_0 {
        uint256 chainId; // destination network
        address recipient; // target contract on the destination chain
        uint64 gasLimit; // execution gas limit (minimum 100,000)
        bytes payload; // ABI-encoded function call; first arg MUST be an address (address(0) placeholder)
    }

    /// @notice Emitted when a callback is requested; indexed fields are destination chain,
    ///         requesting reactive contract, and recipient.
    event CallbackRequest(
        uint256 indexed chainId,
        address indexed sender,
        address indexed recipient,
        CallbackVersion version,
        bytes configuration
    );

    /// @notice Generic callback entry point; `config_` must be ABI-encoded to match `version_`.
    function requestCallback(CallbackVersion version_, bytes memory config_) external;

    /// @notice Typed callback entry point; takes the V_1_0 struct directly.
    function requestCallbackV_1_0(CallbackConfiguration_V_1_0 memory config_) external;

    /// @notice One callback record as returned by `getCallbacks`.
    struct CallbackRecord {
        uint256 blockNumber; // block the callback was posted in
        address sender; // requesting reactive contract
        uint256 index; // callback index within the reactive transaction
        uint256 chainId; // destination chain ID
        uint256 txHash; // destination transaction hash
        bytes err; // error data returned by the destination contract (empty on success)
    }

    /// @notice Returns every callback posted for reactive transaction `reactiveTxHash_`.
    /// @dev Each record: block number, requesting reactive contract, callback index,
    ///      destination chain ID, destination tx hash, error data (empty on success).
    function getCallbacks(uint256 reactiveTxHash_)
        external
        view
        returns (CallbackRecord[] memory);
}
