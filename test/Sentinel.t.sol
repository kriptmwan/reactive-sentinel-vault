// SPDX-License-Identifier: MIT
pragma solidity ^0.8.29;

import { Test, Vm } from "forge-std/Test.sol";
import { MockToken } from "../src/MockToken.sol";
import { PriceOracle } from "../src/PriceOracle.sol";
import { SentinelVault } from "../src/SentinelVault.sol";
import { SentinelReactive } from "../src/SentinelReactive.sol";
import { IReactive } from "../src/reactive/IReactive.sol";
import { AbstractPayer } from "../src/reactive/AbstractPayer.sol";
import { AbstractCallback } from "../src/reactive/AbstractCallback.sol";
import { MockSystemContract } from "./mocks/MockSystemContract.sol";
import { MockCallbackProxy } from "./mocks/MockCallbackProxy.sol";

/// @title Sentinel Vault — full-loop forge tests.
/// @notice Simulates the Reactive Network locally: the mock system contract is etched at the
///         real SYSTEM address (0x8888...), origin logs are captured with vm.recordLogs and
///         delivered to react() as the system contract, and callbacks are executed through
///         the mock proxy, which performs the same first-argument overwrite as the real one.
///         The live testnet loop (real Lasna sequencer + real Base Sepolia proxy) is proven
///         separately; these tests prove the decision logic and the auth guards.
contract SentinelTest is Test {
    address payable internal constant SYSTEM_ADDR =
        payable(0x8888888888888888888888888888888888888888);
    uint256 internal constant BASE_SEPOLIA = 84532;
    uint256 internal constant THRESHOLD = 1800e18;
    uint256 internal constant INITIAL_PRICE = 2000e18;

    MockToken internal vol;
    MockToken internal stable;
    PriceOracle internal oracle;
    SentinelVault internal vault;
    SentinelReactive internal reactive;
    MockCallbackProxy internal proxy;
    MockSystemContract internal system; // reads mock state at the SYSTEM address

    address internal user = address(0xBEEF);
    address internal user2 = address(0xCAFE);

    function setUp() public {
        vm.deal(address(this), 10 ether);
        vm.deal(user, 1 ether);
        vm.deal(user2, 1 ether);

        // Etch the mock system contract at the real SYSTEM address.
        MockSystemContract systemMock_ = new MockSystemContract();
        vm.etch(SYSTEM_ADDR, address(systemMock_).code);
        system = MockSystemContract(SYSTEM_ADDR);

        proxy = new MockCallbackProxy();

        vol = new MockToken("Sentinel Volatile", "mVOL");
        stable = new MockToken("Sentinel Stable", "mUSDC");
        oracle = new PriceOracle(THRESHOLD, INITIAL_PRICE);

        // Deploy reactive first (oracle known upfront), fund it, then the vault, then wire.
        reactive = new SentinelReactive{ value: 1 ether }(address(oracle), THRESHOLD);
        vault = new SentinelVault{ value: 1 ether }(
            proxy, address(reactive), address(vol), address(stable)
        );
        reactive.setVault(address(vault));

        // Seed the vault's stable reserve and fund demo users.
        stable.mint(address(this), 1_000_000e18);
        stable.transfer(address(vault), 1_000_000e18);
        vol.mint(user, 100e18);
        vol.mint(user2, 100e18);
        vm.prank(user);
        vol.approve(address(vault), type(uint256).max);
        vm.prank(user2);
        vol.approve(address(vault), type(uint256).max);
    }

    // ---------------------------------------------------------------- helpers

    /// @notice Delivers every log recorded since the last vm.recordLogs() to react() as SYSTEM.
    function _deliverRecorded() internal {
        Vm.Log[] memory logs_ = vm.getRecordedLogs();
        for (uint256 i_; i_ < logs_.length; ++i_) {
            _deliverLog(logs_[i_]);
        }
    }

    /// @notice Builds a LogRecord from a recorded EVM log and delivers it as the system contract.
    function _deliverLog(Vm.Log memory log_) internal {
        IReactive.LogRecord memory rec_ = IReactive.LogRecord({
            chainId: BASE_SEPOLIA,
            contractAddress: log_.emitter,
            topic0: log_.topics.length > 0 ? uint256(log_.topics[0]) : 0,
            topic1: log_.topics.length > 1 ? uint256(log_.topics[1]) : 0,
            topic2: log_.topics.length > 2 ? uint256(log_.topics[2]) : 0,
            topic3: log_.topics.length > 3 ? uint256(log_.topics[3]) : 0,
            data: log_.data,
            blockNumber: block.number,
            opCode: log_.topics.length,
            blockHash: 0,
            txHash: 0,
            logIndex: 0
        });
        vm.prank(SYSTEM_ADDR);
        reactive.react(rec_);
    }

    /// @notice Executes the next unexecuted callback request, in request order.
    uint256 internal _nextCallback;

    /// @notice Executes the next requested callback through the mock proxy.
    function _executeNextCallback() internal {
        uint256 n_ = system.callbackCount();
        require(_nextCallback < n_, "no unexecuted callback");
        (, address recipient_, , bytes memory payload_) = system.callbackRequests(_nextCallback);
        _nextCallback++;
        proxy.deliver(recipient_, payload_, address(reactive));
    }

    /// @notice Decodes a callback payload's arguments (selector stripped).
    function _decodePayload(bytes memory payload_)
        internal
        pure
        returns (address injected_, address user_, uint256 price_, uint256 timestamp_)
    {
        bytes memory args_ = new bytes(payload_.length - 4);
        for (uint256 i_; i_ < args_.length; ++i_) {
            args_[i_] = payload_[i_ + 4];
        }
        (injected_, user_, price_, timestamp_) = abi.decode(
            args_,
            (address, address, uint256, uint256)
        );
    }

    function _deposit(address user_, uint256 amount_) internal {
        vm.recordLogs();
        vm.prank(user_);
        vault.deposit(amount_);
        _deliverRecorded();
    }

    function _setPrice(uint256 price_) internal {
        vm.recordLogs();
        oracle.setPrice(price_);
        _deliverRecorded();
    }

    // ---------------------------------------------------------------- wiring

    function testWiring() public view {
        assertEq(system.subscriptionCount(), 4, "expected 4 subscriptions");
        assertEq(reactive.oracle(), address(oracle));
        assertEq(reactive.threshold(), THRESHOLD);
        assertEq(reactive.vault(), address(vault));
        assertEq(vault.balances(user), 0);
    }

    // ---------------------------------------------------------------- arming

    function testDepositArmsUser() public {
        _deposit(user, 10e18);
        assertTrue(reactive.isArmed(user), "user should be armed after deposit");
        assertEq(reactive.trackedUserCount(), 1);
        assertEq(vault.balances(user), 10e18);
    }

    function testDepositZeroDoesNotArm() public {
        vm.prank(user);
        vm.expectRevert("SentinelVault: amount is zero");
        vault.deposit(0);
        assertFalse(reactive.isArmed(user));
    }

    // ---------------------------------------------------------------- breach

    function testFullLoopBreachExitsOnce() public {
        _deposit(user, 10e18);
        assertTrue(reactive.isArmed(user));

        // Breach: price 1700 < threshold 1800.
        _setPrice(1700e18);
        assertEq(system.callbackCount(), 1, "exactly one callback on first breach");
        assertFalse(reactive.isArmed(user), "user disarmed after exit request");

        _executeNextCallback();
        assertEq(vault.balances(user), 0, "mVOL balance cleared");
        assertEq(vault.stableBalances(user), 17_000e18, "10 mVOL * $1700 = 17000 mUSDC");

        // Second breach while disarmed: NO new callback (not cron-equivalent).
        _setPrice(1600e18);
        assertEq(system.callbackCount(), 1, "no second callback while disarmed");
    }

    function testPayloadCarriesOriginPriceAndTimestamp() public {
        _deposit(user, 10e18);
        vm.warp(1_700_000_000);
        _setPrice(1700e18);
        (, , , bytes memory payload_) = system.callbackRequests(0);
        (address injected_, address user_, uint256 price_, uint256 timestamp_) = _decodePayload(
            payload_
        );
        assertEq(injected_, address(0), "first arg is the address(0) placeholder");
        assertEq(user_, user);
        assertEq(price_, 1700e18, "price from the origin event");
        assertEq(timestamp_, 1_700_000_000, "timestamp from the origin event, not Lasna time");
    }

    function testPriceAtThresholdDoesNotExit() public {
        _deposit(user, 10e18);
        _setPrice(1800e18); // exactly at threshold: not a breach
        assertEq(system.callbackCount(), 0, "no callback at threshold");
        assertTrue(reactive.isArmed(user));
    }

    function testMultipleUsersExitOnOneBreach() public {
        _deposit(user, 10e18);
        _deposit(user2, 5e18);
        _setPrice(1700e18);
        assertEq(system.callbackCount(), 2, "one callback per armed user");
        _executeNextCallback(); // user (requested first)
        _executeNextCallback(); // user2 (requested second)
        assertEq(vault.stableBalances(user), 17_000e18);
        assertEq(vault.stableBalances(user2), 8_500e18);
    }

    // ---------------------------------------------------------------- recovery

    function testRecoveryRearmsAndSecondExit() public {
        _deposit(user, 10e18);
        _setPrice(1700e18);
        _executeNextCallback();
        assertEq(vault.stableBalances(user), 17_000e18);

        // Recovery: price 1890 = threshold + 5% -> PriceRecovered re-arms.
        _setPrice(1890e18);
        assertTrue(reactive.isArmed(user), "user re-armed on recovery");

        // Second cycle: new deposit + second breach exits again.
        _deposit(user, 5e18);
        _setPrice(1700e18);
        assertEq(system.callbackCount(), 2, "second breach requests a second callback");
        _executeNextCallback();
        assertEq(vault.stableBalances(user), 17_000e18 + 8_500e18);
    }

    function testRecoveryBelowRecoveryPriceDoesNotRearm() public {
        _deposit(user, 10e18);
        _setPrice(1700e18);
        _executeNextCallback();
        assertFalse(reactive.isArmed(user));
        _setPrice(1850e18); // above threshold but below recovery (1890)
        assertFalse(reactive.isArmed(user), "no re-arm below recovery price");
    }

    function testOwnerRearm() public {
        _deposit(user, 10e18);
        _setPrice(1700e18);
        assertFalse(reactive.isArmed(user));
        reactive.rearmUser(user);
        assertTrue(reactive.isArmed(user), "owner reset re-arms");
    }

    // ---------------------------------------------------------------- manual exit

    function testManualWithdrawDisarms() public {
        _deposit(user, 10e18);
        assertTrue(reactive.isArmed(user));
        vm.recordLogs();
        vm.prank(user);
        vault.withdraw(10e18);
        _deliverRecorded();
        assertFalse(reactive.isArmed(user), "full manual withdraw disarms");
        _setPrice(1700e18);
        assertEq(system.callbackCount(), 0, "no callback for a user who left");
    }

    function testPartialWithdrawKeepsArmed() public {
        _deposit(user, 10e18);
        vm.recordLogs();
        vm.prank(user);
        vault.withdraw(4e18);
        _deliverRecorded();
        assertTrue(reactive.isArmed(user), "partial withdraw keeps user armed");
        _setPrice(1700e18);
        _executeNextCallback();
        assertEq(vault.stableBalances(user), 6e18 * 1700, "only the remaining 6 mVOL exit");
    }

    // ---------------------------------------------------------------- auth

    function testExitRevertsWhenCalledDirectly() public {
        _deposit(user, 10e18);
        vm.prank(user);
        vm.expectRevert(AbstractPayer.NotAuthorized.selector);
        vault.exitToStable(address(reactive), user, 1700e18, block.timestamp);
    }

    function testExitRevertsWithWrongReactiveSender() public {
        _deposit(user, 10e18);
        vm.prank(address(proxy));
        vm.expectRevert(AbstractCallback.CallbackNotAuthorized.selector);
        vault.exitToStable(address(0xDEAD), user, 1700e18, block.timestamp);
    }

    function testExitSucceedsViaProxyPrank() public {
        // The required vm.prank test: impersonate the Base Sepolia callback proxy.
        _deposit(user, 10e18);
        vm.prank(address(proxy));
        vault.exitToStable(address(reactive), user, 1700e18, 1_700_000_000);
        assertEq(vault.balances(user), 0);
        assertEq(vault.stableBalances(user), 17_000e18);
    }

    function testExitIsIdempotentNoOp() public {
        // Already exited (zero balance): a duplicate callback is a graceful no-op.
        _deposit(user, 10e18);
        _setPrice(1700e18);
        _executeNextCallback();
        uint256 stableBefore_ = vault.stableBalances(user);
        vm.prank(address(proxy));
        vault.exitToStable(address(reactive), user, 1700e18, block.timestamp);
        assertEq(vault.stableBalances(user), stableBefore_, "no double exit");
        assertEq(vault.balances(user), 0);
    }

    function testReactRevertsForNonSystemCaller() public {
        IReactive.LogRecord memory rec_ = IReactive.LogRecord({
            chainId: BASE_SEPOLIA,
            contractAddress: address(oracle),
            topic0: reactive.PRICE_UPDATED_TOPIC(),
            topic1: 0,
            topic2: 0,
            topic3: 0,
            data: abi.encode(uint256(1700e18), uint256(block.timestamp)),
            blockNumber: block.number,
            opCode: 1,
            blockHash: 0,
            txHash: 0,
            logIndex: 0
        });
        vm.prank(user);
        vm.expectRevert(AbstractPayer.NotAuthorized.selector);
        reactive.react(rec_);
    }

    function testUnknownLogFallsThrough() public {
        _deposit(user, 10e18);
        IReactive.LogRecord memory rec_ = IReactive.LogRecord({
            chainId: BASE_SEPOLIA,
            contractAddress: address(oracle),
            topic0: uint256(keccak256("SomethingElse(uint256)")),
            topic1: 0,
            topic2: 0,
            topic3: 0,
            data: abi.encode(uint256(123)),
            blockNumber: block.number,
            opCode: 1,
            blockHash: 0,
            txHash: 0,
            logIndex: 0
        });
        vm.prank(SYSTEM_ADDR);
        reactive.react(rec_); // must not revert
        assertEq(system.callbackCount(), 0);
        assertTrue(reactive.isArmed(user));
    }

    function testWrongChainLogIgnored() public {
        _deposit(user, 10e18);
        IReactive.LogRecord memory rec_ = IReactive.LogRecord({
            chainId: 1, // Ethereum mainnet, not Base Sepolia
            contractAddress: address(oracle),
            topic0: reactive.PRICE_UPDATED_TOPIC(),
            topic1: 0,
            topic2: 0,
            topic3: 0,
            data: abi.encode(uint256(100e18), uint256(block.timestamp)),
            blockNumber: block.number,
            opCode: 1,
            blockHash: 0,
            txHash: 0,
            logIndex: 0
        });
        vm.prank(SYSTEM_ADDR);
        reactive.react(rec_);
        assertEq(system.callbackCount(), 0, "foreign chain logs are ignored");
    }

    // ---------------------------------------------------------------- vault ops

    function testWithdrawStableAfterExit() public {
        _deposit(user, 10e18);
        _setPrice(1700e18);
        _executeNextCallback();
        vm.prank(user);
        vault.withdrawStable(17_000e18);
        assertEq(stable.balanceOf(user), 17_000e18);
        assertEq(vault.stableBalances(user), 0);
    }

    function testExitRevertsWhenReserveTooSmall() public {
        // Drain the stable reserve, then breach: exit must revert (CallbackFailure on live).
        _deposit(user, 10e18);
        // Move the reserve out by deploying a second vault-less drain is not possible;
        // instead use a fresh vault with a tiny reserve.
        MockToken tinyStable_ = new MockToken("Tiny Stable", "tUSDC");
        SentinelVault tinyVault_ = new SentinelVault{ value: 0.1 ether }(
            proxy, address(reactive), address(vol), address(tinyStable_)
        );
        tinyStable_.mint(address(this), 100e18);
        tinyStable_.transfer(address(tinyVault_), 100e18);
        vm.prank(user);
        vol.approve(address(tinyVault_), type(uint256).max);
        vm.prank(user);
        tinyVault_.deposit(10e18);
        vm.prank(address(proxy));
        vm.expectRevert("SentinelVault: insufficient stable reserve");
        tinyVault_.exitToStable(address(reactive), user, 1700e18, block.timestamp);
    }
}
