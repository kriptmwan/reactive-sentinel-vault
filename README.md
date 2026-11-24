# Reactive Sentinel Vault

**Reactive Omni Buildathon — Track: Every Second Counts**

An oracle-triggered exit guard: a vault on **Base Sepolia** holds user deposits of a
volatile asset (mVOL). A reactive contract on **Reactive Lasna** watches the price oracle;
the moment the price breaches the threshold it fires a callback that exits the user's whole
position into a stable asset (mUSDC) — with no keeper, no polling, and no key custody.
When the price recovers to threshold + 5%, the sentinel re-arms itself and guards again.

## The loop

```
Base Sepolia                                  Reactive Lasna (chain 5318007)
┌──────────────┐  PriceUpdated(price, ts)    ┌─────────────────────────┐
│ PriceOracle  │ ──────────────────────────▶ │ SentinelReactive      │
└──────────────┘  (subscribe: oracle)        │  isArmed[user]?        │
┌──────────────┐  VaultDeposit(user, ...)    │  breach? → request    │
│ SentinelVault│ ──────────────────────────▶ │  callback             │
│  (callback   │  VaultWithdraw(...)         └───────────┬─────────────┘
│   contract)  │                                     │ requestCallbackV_1_0
└──────┬───────┘                                     │ (SYSTEM 0x8888...)
       │ exitToStable(user, price, ts) ◀─────────────┘
       │ via Base Sepolia callback proxy
       ▼
  SentinelTriggered(user, price, ts, stableAmount)
  user balance: mVOL → mUSDC
```

Deployed addresses and the full-loop transaction hashes are in
[`DEPLOYMENTS.md`](DEPLOYMENTS.md). Measured latency (loop 1, verified on-chain):
breach `0x558c0c20…` (Base Sepolia block 62898757) → callback `0x54c7feab…`
(block 62898761): **4 blocks, 1 second by block timestamps**.

## Why this is event-driven, not a cron job (the track rule)

The track says: *"If you can do it with a cron job, it's not for this track."* A naive
price-threshold monitor **is** a cron job. This build is not — and the first reason is the
one that matters most: there is no keeper to replace.

1. **No keeper, no off-chain liveness assumption.** There is no bot, no key, and no
   operator that must stay online. The Reactive network delivers the origin log to
   `react()` and the callback to the vault; if the sentinel contract is funded, the loop
   runs. A cron-based design fails silently when its operator goes offline; this one
   cannot, because there is no operator. Removing the keeper is the point — "polling is
   bad" is not the argument, the absence of any privileged off-chain actor is.
2. **State machine, not a sampler.** The sentinel exits a user exactly **once** per arming.
   After the first breach it disarms; further price updates below the threshold do nothing.
   A cron polling the oracle would re-fire on every tick. The exit is caused by the *event*
   (the first breach after arming), not by a schedule.
3. **Two-event composition.** An exit requires BOTH a `VaultDeposit` (funds at risk) AND a
   `PriceUpdated` breach. Neither event alone can trigger anything. A cron sees only the
   price; it cannot see the on-chain ordering of deposit → breach → recovery that the
   sentinel's state machine is built from.

## Contracts

| Contract | Chain | Role |
|---|---|---|
| `MockToken` (mVOL / mUSDC) | Base Sepolia | Mock volatile + stable assets, 18 decimals |
| `PriceOracle` | Base Sepolia | Mock price feed; emits `PriceUpdated` / `PriceRecovered` |
| `SentinelVault` | Base Sepolia | Holds deposits; `exitToStable` callback (proxy + sender authed, nonReentrant, idempotent) |
| `SentinelReactive` | Lasna | Subscribes to all four events; per-user armed state machine; requests callbacks |

Key facts (verified against the **current** docs at dev.reactive.network, 24 Nov 2026):

- **Lasna chain ID is 5318007.** (Two AI lane models said 270 and 5318008; both wrong. Docs win.)
- **System contract (Omni):** `0x8888888888888888888888888888888888888888`
- **Base Sepolia callback proxy:** `0x476F44b11F5C942c58f4c8E3d0300E5710743585`
- **Base Sepolia chain ID:** 84532. Lasna RPC: `https://lasna-rpc.rnk.dev/`
- New Omni API: `SYSTEM.subscribe`, `react(LogRecord memory) onlySystem`,
  `SYSTEM.requestCallbackV_1_0`. Callback payloads reserve the first argument for the
  reactive address (passed as `address(0)`); the proxy overwrites it. Callback gas limit
  minimum is 100,000 (we use 500,000). Timestamps in callbacks come from the **origin**
  event payload, never Lasna block time.
- **Docs discrepancy worth knowing:** the published `Reactive-Network/reactive-lib` on
  GitHub is still the LEGACY library (system contract `0xfffFfF`, RVM-based, no
  `requestCallbackV_1_0`), and the docs' `@reactive/src/base/...` import paths do not
  resolve against it. The Omni interfaces in `src/reactive/` are therefore implemented
  here exactly as the current docs specify. The same applies to `reactive-test-lib`
  (legacy simulator); `forge test` uses our own mocks instead.

## State machine (per user, on Lasna)

```
            VaultDeposit
  ─────────────────────────▶ ARMED
  ARMED ── PriceUpdated < threshold ──▶ EXIT (callback requested) ──▶ DISARMED
  DISARMED ── PriceRecovered (≥ threshold + 5%) ──▶ ARMED
  DISARMED ── owner rearmUser ──▶ ARMED
  ARMED ── VaultWithdraw to zero ──▶ DISARMED
```

The vault itself is idempotent: `exitToStable` for a zero balance is a graceful no-op,
so a duplicate or stale callback can never drain anything.

## Trust model

Who can do what — and what happens if a trusted party is compromised.

**The exit path has two independent guards, both enforced on-chain.** `exitToStable` is
callable only through the Base Sepolia callback proxy (`onlyServiceProvider`:
`msg.sender` must be `0x476F44b11F5C942c58f4c8E3d0300E5710743585`, a
Reactive-operated contract — not even the vault owner can call it directly) AND only
when the injected first argument is the authorized Reactive sentinel
(`onlyCallbackSender`: it must equal `0x393Bca85F6eB00cFDd0D431ea47952b0F5Fc7CF8`
on Lasna). Both addresses are **immutables set at construction**
(`AbstractPayer._SERVICE_PROVIDER`, `AbstractCallback._CALLBACK_SENDER`); there is no
rotation function. If the Reactive proxy address ever changed, the vault would need
redeployment — acceptable for this testnet demo; a production version would add an
owner-governed proxy rotation (post-submit scope). The wrong-sender guard is covered by
`testExitRevertsWithWrongReactiveSender` in `test/Sentinel.t.sol` (a call through the
proxy with any other injected sender reverts with `CallbackNotAuthorized`).

**If the Reactive relayer / proxy were compromised**, the worst an attacker could do
through `exitToStable` is force a premature exit of an armed user's position: the
converted stable amount is credited to that user's own `stableBalances` and can only be
withdrawn by that user via `withdrawStable`. Funds can never be redirected to the
attacker, and the vault's stable reserve can only leave as per-user balances. The trust
surface is therefore **griefing (a forced exit at the oracle price), not theft**. The
live loop's callback arrived from relayer
`0xf9f61c1d3325e2d4abb55dd9e0db84f7a0d914b0` to the proxy (see `DEPLOYMENTS.md`).

**Owner powers are narrow.** The vault owner (deployer) has no privileged function that
moves funds — `Ownable` is inherited but no `onlyOwner` function touches balances;
`deposit` / `withdraw` / `withdrawStable` are self-only. The reactive owner can only
`rearmUser` (re-arm a disarmed user) and `setVault` (owner-only, **once** — it reverts
if the vault is already set). Neither owner can trigger an exit: exits originate only
from `react()` called by the Reactive system contract on an origin event.

**Max-drain bound.** One callback converts at most a single user's own deposit, at the
oracle price from the origin event. Total exposure is capped at the vault's seeded
stable reserve (1,000,000 mUSDC on testnet). Duplicate or stale callbacks are
graceful no-ops (zero-balance exit), so a replayed callback costs gas but moves
nothing.

**Known trust assumption (testnet demo).** The price oracle is a **mock** whose price is
set by the deployer (`setPrice`) — it proves the plumbing, not feed security. A
production deployment replaces it with a real feed (Pyth / Chainlink on Base Sepolia);
that swap is post-submit scope and does not change the sentinel or the vault.

## Deploy (testnet)

Prerequisites: Foundry 1.9.0, a throwaway deployer key, Base Sepolia ETH + Lasna lREACT
from public faucets (see "Funding" below).

```bash
# 1. Origin contracts on Base Sepolia
forge script script/DeployOracle.s.sol --rpc-url https://sepolia.base.org \
  --private-key $DEPLOYER_PRIVATE_KEY --broadcast

# 2. Reactive contract on Lasna (needs ORACLE_ADDRESS from step 1)
ORACLE_ADDRESS=0x... forge script script/DeployReactive.s.sol \
  --rpc-url https://lasna-rpc.rnk.dev/ --chain-id 5318007 \
  --private-key $DEPLOYER_PRIVATE_KEY --broadcast --value 0.05ether

# 3. Vault on Base Sepolia (needs REACTIVE_ADDRESS from step 2)
REACTIVE_ADDRESS=0x... MVOL_ADDRESS=0x... MUSDC_ADDRESS=0x... \
  forge script script/DeployVault.s.sol --rpc-url https://sepolia.base.org \
  --private-key $DEPLOYER_PRIVATE_KEY --broadcast --value 0.05ether

# 4. Wire the vault into the sentinel (Lasna, owner-only, once)
cast send $REACTIVE_ADDRESS "setVault(address)" $VAULT_ADDRESS \
  --rpc-url https://lasna-rpc.rnk.dev/ --private-key $DEPLOYER_PRIVATE_KEY

# 5. Fund both sides (if not already funded at deploy)
cast send 0x8888888888888888888888888888888888888888 "depositTo(address)" $REACTIVE_ADDRESS \
  --rpc-url https://lasna-rpc.rnk.dev/ --private-key $DEPLOYER_PRIVATE_KEY --value 0.05ether
cast send 0x476F44b11F5C942c58f4c8E3d0300E5710743585 "depositTo(address)" $VAULT_ADDRESS \
  --rpc-url https://sepolia.base.org --private-key $DEPLOYER_PRIVATE_KEY --value 0.05ether
```

## Demo loop (what the video shows)

```bash
# User deposits 10 mVOL (arms the sentinel)
cast send $VAULT "deposit(uint256)" 10000000000000000000 \
  --rpc-url https://sepolia.base.org --private-key $USER_PRIVATE_KEY
# Oracle breaches: $2000 -> $1700 (below the $1800 threshold)
cast send $ORACLE "setPrice(uint256)" 1700000000000000000000 \
  --rpc-url https://sepolia.base.org --private-key $DEPLOYER_PRIVATE_KEY
# -> Lasna react() fires, callback delivers exitToStable, user holds 17,000 mUSDC
# Oracle recovers: $1700 -> $1890 (threshold + 5%) -> sentinel re-arms
cast send $ORACLE "setPrice(uint256)" 1890000000000000000000 \
  --rpc-url https://sepolia.base.org --private-key $DEPLOYER_PRIVATE_KEY
# -> second breach exits again (proves the state machine cycles)
```

## Tests

```bash
forge test   # 21/21 pass
```

The suite simulates the Reactive network locally: the mock system contract is etched at
the real SYSTEM address, origin logs are captured with `vm.recordLogs` and delivered to
`react()` as the system contract, and callbacks execute through a mock proxy that performs
the same first-argument overwrite as the real one. It covers arming, exactly-once exit,
origin price + timestamp in the callback payload, recovery re-arm, manual-withdraw disarm,
both auth guards (`NotAuthorized` on direct calls, `CallbackNotAuthorized` on a wrong
sender), idempotent no-op exit, and unknown/wrong-chain log fall-through.

## Funding

- **Lasna lREACT:** send ETH on Base Sepolia to the Reactive faucet contract
  `0x2afaFD298b23b62760711756088F75B7409f5967` (or on Ethereum Sepolia to
  `0x9b9BB25f1A81078C544C829c5EB7822d747Cf434`). Per the docs (Debugging page).
- **Base Sepolia ETH:** public faucets only (Alchemy / QuickNode / Chainlink). Note for
  the deployer: the Alchemy faucet requires mainnet balance + activity on the claiming
  wallet, and the pk910.de Sepolia PoW faucet requires a captcha token to start a
  session — a fresh throwaway wallet cannot claim from either without help.

## Submission checklist

- [x] Public repo, MIT
- [x] Contracts + NatSpec + tests (21/21)
- [x] Deployed addresses (Base Sepolia + Lasna) — see [DEPLOYMENTS.md](DEPLOYMENTS.md)
- [x] Full-loop tx hashes (origin event → reactive tx → callback tx) — loop proven twice, see [DEPLOYMENTS.md](DEPLOYMENTS.md)
- [x] Demo video (< 3 min) — `~/workspace/reactive-omni/video/reactive-sentinel-vault-demo.mp4`, 102s, 1280×720; YouTube upload pending (parent handles)
- [ ] DoraHacks registration + submission — parent handles after Gate 2

## License

MIT
