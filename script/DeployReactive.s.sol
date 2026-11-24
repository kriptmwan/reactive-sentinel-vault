// SPDX-License-Identifier: MIT
pragma solidity ^0.8.29;

import { Script, console } from "forge-std/Script.sol";
import { SentinelReactive } from "../src/SentinelReactive.sol";

/// @notice Step 2 (Reactive Lasna): deploys the SentinelReactive contract.
/// @dev Run: forge script script/DeployReactive.s.sol --rpc-url $LASNA_RPC --chain-id 5318007
///      --private-key $DEPLOYER_PRIVATE_KEY --broadcast --value 0.05ether
///      Env: ORACLE_ADDRESS (Base Sepolia oracle), THRESHOLD (default 1800e18).
///      The contract is funded at deployment (payable constructor) so it can pay for
///      reactive transactions; top up later via SYSTEM.depositTo if needed.
contract DeployReactive is Script {
    function run() public {
        address oracle_ = vm.envAddress("ORACLE_ADDRESS");
        uint256 threshold_ = vm.envOr("THRESHOLD", uint256(1800e18));
        vm.startBroadcast();
        SentinelReactive reactive_ = new SentinelReactive{ value: 0.05 ether }(oracle_, threshold_);
        vm.stopBroadcast();
        console.log("SentinelReactive:", address(reactive_));
        console.log("Oracle:          ", oracle_);
        console.log("Threshold:       ", threshold_);
    }
}
