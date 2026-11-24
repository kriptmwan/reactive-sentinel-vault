// SPDX-License-Identifier: MIT
pragma solidity ^0.8.29;

import "../../src/reactive/ISystemContract.sol";

/// @title Mock of the Reactive system contract (Omni) for forge tests.
/// @notice Etched at the SYSTEM address (0x8888...) in tests so contracts calling
///         SYSTEM.subscribe / SYSTEM.requestCallbackV_1_0 hit this mock. Records every
///         subscription and callback request for assertions. Payment functions are stubs
///         (zero debt, zero reserves) — funding logic is covered by the live testnet loop.
contract MockSystemContract is ISystemContract {
    struct Subscription {
        uint256 chainId;
        address contractAddress;
        uint256 topic0;
        uint256 topic1;
        uint256 topic2;
        uint256 topic3;
    }

    struct CallbackRequestRecord {
        uint256 chainId;
        address recipient;
        uint64 gasLimit;
        bytes payload;
    }

    Subscription[] public subscriptions;
    CallbackRequestRecord[] public callbackRequests;

    receive() external payable override {}

    function depositTo(address /* recipient_ */) external payable override {}

    function debt(address /* contract_ */) external view override returns (uint256) {
        return 0;
    }

    function reserves(address /* contract_ */) external view override returns (uint256) {
        return 0;
    }

    function subscribe(
        uint256 chainId_,
        address contract_,
        uint256 topic0_,
        uint256 topic1_,
        uint256 topic2_,
        uint256 topic3_
    ) external override {
        subscriptions.push(
            Subscription(chainId_, contract_, topic0_, topic1_, topic2_, topic3_)
        );
    }

    function unsubscribe(
        uint256 chainId_,
        address contract_,
        uint256 topic0_,
        uint256 topic1_,
        uint256 topic2_,
        uint256 topic3_
    ) external override {
        uint256 len_ = subscriptions.length;
        for (uint256 i_; i_ < len_; ++i_) {
            Subscription storage s_ = subscriptions[i_];
            if (
                s_.chainId == chainId_ && s_.contractAddress == contract_ && s_.topic0 == topic0_
                    && s_.topic1 == topic1_ && s_.topic2 == topic2_ && s_.topic3 == topic3_
            ) {
                subscriptions[i_] = subscriptions[len_ - 1];
                subscriptions.pop();
                return;
            }
        }
    }

    function requestCallback(CallbackVersion /* version_ */, bytes memory /* config_ */)
        external
        override
    {
        revert("MockSystemContract: use requestCallbackV_1_0");
    }

    function requestCallbackV_1_0(CallbackConfiguration_V_1_0 memory config_) external override {
        callbackRequests.push(
            CallbackRequestRecord(config_.chainId, config_.recipient, config_.gasLimit, config_.payload)
        );
        emit CallbackRequest(config_.chainId, msg.sender, config_.recipient, CallbackVersion.V_1_0, "");
    }

    function getCallbacks(uint256 /* reactiveTxHash_ */)
        external
        view
        override
        returns (CallbackRecord[] memory)
    {
        return new CallbackRecord[](0);
    }

    function subscriptionCount() external view returns (uint256) {
        return subscriptions.length;
    }

    function callbackCount() external view returns (uint256) {
        return callbackRequests.length;
    }
}
