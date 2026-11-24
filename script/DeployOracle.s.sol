// SPDX-License-Identifier: MIT
pragma solidity ^0.8.29;

import { Script, console } from "forge-std/Script.sol";
import { MockToken } from "../src/MockToken.sol";
import { PriceOracle } from "../src/PriceOracle.sol";

/// @notice Step 1 (Base Sepolia): deploys mVOL, mUSDC and the PriceOracle.
/// @dev Run: forge script script/DeployOracle.s.sol --rpc-url $BASE_SEPOLIA_RPC
///      --private-key $DEPLOYER_PRIVATE_KEY --broadcast
///      Env: THRESHOLD (default 1800e18), INITIAL_PRICE (default 2000e18).
contract DeployOracle is Script {
    function run() public {
        uint256 threshold_ = vm.envOr("THRESHOLD", uint256(1800e18));
        uint256 initialPrice_ = vm.envOr("INITIAL_PRICE", uint256(2000e18));
        vm.startBroadcast();
        MockToken vol_ = new MockToken("Sentinel Volatile", "mVOL");
        MockToken stable_ = new MockToken("Sentinel Stable", "mUSDC");
        PriceOracle oracle_ = new PriceOracle(threshold_, initialPrice_);
        vm.stopBroadcast();
        console.log("mVOL:    ", address(vol_));
        console.log("mUSDC:   ", address(stable_));
        console.log("Oracle:  ", address(oracle_));
        console.log("Threshold:", threshold_);
        console.log("Price:   ", initialPrice_);
    }
}
