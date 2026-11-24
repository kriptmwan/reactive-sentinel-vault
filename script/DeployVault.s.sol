// SPDX-License-Identifier: MIT
pragma solidity ^0.8.29;

import { Script, console } from "forge-std/Script.sol";
import { MockToken } from "../src/MockToken.sol";
import { PriceOracle } from "../src/PriceOracle.sol";
import { SentinelVault } from "../src/SentinelVault.sol";
import { IPayable } from "../src/reactive/IPayable.sol";

/// @notice Step 3 (Base Sepolia): deploys the SentinelVault and seeds its stable reserve.
/// @dev Run: forge script script/DeployVault.s.sol --rpc-url $BASE_SEPOLIA_RPC
///      --private-key $DEPLOYER_PRIVATE_KEY --broadcast --value 0.05ether
///      Env: REACTIVE_ADDRESS (Lasna sentinel), MVOL_ADDRESS, MUSDC_ADDRESS.
///      The deployer mints 1,000,000 mUSDC into the vault as the exit reserve and 100 mVOL
///      to itself as the demo user (transfer/approve as needed for the demo).
contract DeployVault is Script {
    /// @notice Base Sepolia callback proxy (docs, Origins & Destinations).
    address payable internal constant BASE_SEPOLIA_CALLBACK_PROXY =
        payable(0x476F44b11F5C942c58f4c8E3d0300E5710743585);

    function run() public {
        address reactive_ = vm.envAddress("REACTIVE_ADDRESS");
        address vol_ = vm.envAddress("MVOL_ADDRESS");
        address stable_ = vm.envAddress("MUSDC_ADDRESS");
        vm.startBroadcast();
        SentinelVault vault_ = new SentinelVault{ value: 0.05 ether }(
            IPayable(BASE_SEPOLIA_CALLBACK_PROXY),
            reactive_,
            vol_,
            stable_
        );
        MockToken(stable_).mint(msg.sender, 1_000_000e18);
        MockToken(stable_).transfer(address(vault_), 1_000_000e18);
        MockToken(vol_).mint(msg.sender, 100e18);
        vm.stopBroadcast();
        console.log("SentinelVault:", address(vault_));
        console.log("Reactive:     ", reactive_);
        console.log("Stable reserve seeded: 1,000,000 mUSDC");
        console.log("Demo user mVOL minted: 100");
    }
}
