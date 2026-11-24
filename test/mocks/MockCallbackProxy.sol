// SPDX-License-Identifier: MIT
pragma solidity ^0.8.29;

import "../../src/reactive/IPayable.sol";

/// @title Mock of a destination-chain callback proxy for forge tests.
/// @notice Stands in for the Base Sepolia callback proxy (0x476F44b11F5C942c58f4c8E3d0300E5710743585).
///         `deliver` simulates the proxy exactly as the docs describe it: it overwrites the
///         first 160 bits of the payload (the first address argument) with the reactive
///         contract's address, then calls the target. Payment functions are stubs.
contract MockCallbackProxy is IPayable {
    receive() external payable override {}

    function depositTo(address /* recipient_ */) external payable override {}

    function debt(address /* contract_ */) external view override returns (uint256) {
        return 0;
    }

    function reserves(address /* contract_ */) external view override returns (uint256) {
        return 0;
    }

    /// @notice Delivers `payload_` to `target_`, injecting `reactive_` as the first argument.
    /// @dev The payload's first 32-byte word after the 4-byte selector is overwritten with
    ///      the reactive address — the same overwrite the real proxy performs, so the
    ///      target's onlyCallbackSender check sees the true requesting contract.
    function deliver(address target_, bytes memory payload_, address reactive_) external {
        bytes memory payloadCopy_ = payload_;
        assembly {
            // payload layout: [length][selector (4 bytes)][arg0 word][arg1 word]...
            // arg0 word starts at payloadCopy + 32 (length) + 4 (selector).
            mstore(add(payloadCopy_, 36), reactive_)
        }
        (bool ok_, bytes memory ret_) = target_.call(payloadCopy_);
        require(ok_, string(abi.encodePacked("MockCallbackProxy: delivery failed: ", ret_)));
    }
}
