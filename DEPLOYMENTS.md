# Deployments — Reactive Sentinel Vault

Status: **DEPLOYED + FULL LOOP PROVEN ON TESTNET** (24 Nov 2026 ~13:30–14:00 WIB).

## Deployed contracts

| Contract | Chain | Address | Deploy tx |
|---|---|---|---|
| mVOL (MockToken) | Base Sepolia (84532) | `0x7Dae8cf8FBe375F7104633b10Ee93A2c502efdC3` | `0xf849bf8fdb43459900c36f169ae2c8d49cf48ade5cb6aa2c1d605afcea079003` |
| mUSDC (MockToken) | Base Sepolia (84532) | `0xE27b5C2B13410e9818D13420288C19bbE55C33A3` | `0xdded8b1acd31faa20545fbe294f6007b760ff574ddbeccbdb01f914113a46874` |
| PriceOracle | Base Sepolia (84532) | `0xf20E23497a5509A94eAc5e956948937dd436F5E9` | `0xb56a314ee49ebaeb2527551ba8a713bfe4946a50670e5fff56b166170edb69dd` |
| SentinelVault | Base Sepolia (84532) | `0xbd22E422fbdA3487b5b63C4AACF3D9289cF8dF9D` | `0xe4bb6bc1203c4dcf798d62cddf04a71beb6066861f7dee7319041fac1b00d83d` |
| SentinelReactive | Lasna (5318007) | `0x393Bca85F6eB00cFDd0D431ea47952b0F5Fc7CF8` | `0x6d57e6ab17e6273da41e1898a7556f5f5ff8c1917c35736085e6ea4cb0554a73` |

Threshold: $1,800 (1800e18). Initial price: $2,000 (2000e18). Recovery: $1,890 (threshold + 5%).

Key infra (verified from current docs): Lasna chain ID **5318007** (docs, RPC, blog — models saying 270 / 5318008 were wrong); SYSTEM `0x8888888888888888888888888888888888888888`; Base Sepolia callback proxy `0x476F44b11F5C942c58f4c8E3d0300E5710743585`.

## Funding

- Deployer (throwaway, testnet-only): `0xD35fC23984871E8b814dc3f919C1C551936D4F84` — funded by the user with 0.1191 Base Sepolia ETH.
- Faucet: `0x9d845359228eb5df33eb30bb2a87ba751886025683928dbcd284a683bffab181` — 0.05 ETH → 5 lREACT on Lasna (docs rate 1 ETH → 100 lREACT).
- `setVault`: `0x428f9884e1484378152fb060dc0d66676c429280c511defca8c9eb64a2f0ed3b` (Lasna block 9116433).
- `depositTo` SYSTEM for the reactive contract: `0xae1eabcdcbc7046fa647629261c0fa78fab7fec3a63bc90f36c8040b21b1862d` — 1 lREACT into SYSTEM reserves.
- Vault funded at deploy with 0.05 ETH (callback reserve) + 1,000,000 mUSDC reserve; deployer minted 100 mVOL as demo user.

## Full-loop proof — loop 1 (breach → exit)

| Step | Tx hash | Block |
|---|---|---|
| Approve vault (10 mVOL) | `0xd01cd07b3a424629191c39b782ecc583fd93f4cecf39bab0e509205d1597bd40` | Base Sepolia |
| Origin: VaultDeposit (10 mVOL) | `0x5be0213ad5032466c83db9a9362691fe9848cab9a206710675d7392dd7e4c51e` | 62898637 |
| Reactive tx on Lasna (UserArmed) | `0xf015b69a4e8e264fc6e0cecb082c8a7dcab94c718b99b2035ec47341024dc973` | 9116475 |
| Origin: PriceUpdated breach ($2000 → $1700) | `0x558c0c2026361884d7c2118f76580a9af129824de890414368c690a630289cef` | 62898757 |
| Reactive tx on Lasna (ExitRequested) | `0x5686452e8a6b5f3b6790d8458bd678684e4da6597b719eb5a79d6d618e02b995` | 9116498 |
| Callback tx on Base Sepolia (SentinelTriggered, 10 mVOL → 17,000 mUSDC) | `0x54c7feaba1c806a320045f07fb6d69dab1a1afd25dd6077c225db8abeb73f368` | 62898761 |

Callback receipt: status success, from Reactive relayer `0xf9f61c1d3325e2d4abb55dd9e0db84f7a0d914b0`, to callback proxy `0x476F44b11F5C942c58f4c8E3d0300E5710743585`, gas 104,616. Breach → callback landed 4 blocks later. After the exit: vault `balances[user]` = 0, `stableBalances[user]` = 17,000 mUSDC, `isArmed[user]` = false.

## Full-loop proof — loop 2 (recovery re-arm → second breach → second exit)

| Step | Tx hash | Block |
|---|---|---|
| Origin: PriceUpdated + PriceRecovered ($1700 → $1890) | `0x48fb4b0125e437c9c4cd821660eaa2965f1b198355bf44aa6554456743fd7989` | 62900862 |
| Reactive tx on Lasna (UserRearmed) | `0x20cc80925098fde80dc6264b7764eab155b89324713b9fe59323092be92442a8` | 9116897 |
| Approve vault (10 mVOL, 2nd) | `0xfa6c3c8fc0973d013e8f82a2da953409a1678f5406522806a994837870bd61e9` | Base Sepolia |
| Origin: VaultDeposit (10 mVOL, 2nd) | `0x7fc6c71f729ffd0e2fb04719e93b7bbfba816bb52831a03ba138e05b264fd6a1` | 62900956 |
| Origin: PriceUpdated breach ($1890 → $1700) | `0x98733d536b1dd4c6c98589b4fc3ec693c5e9e8311379a99d64f2478f7830c302` | 62900976 |
| Reactive tx on Lasna (ExitRequested, 2nd) | `0x6b934e37c344c2123d8d5c66c8353a4d3fc5f3dfb533d5d7e3bde1216629e17f` | 9116919 |
| Callback tx on Base Sepolia (SentinelTriggered, 10 mVOL → 17,000 mUSDC) | `0xc0e0ad80f03da05b23a5da2b041a796ea3d8e16bb7eb56b4e3440eb8e896059a` | 62900984 |
| Withdraw 34,000 mUSDC to deployer | `0x53f8c18e5293295cf2b14b526d58cfed4bf3990ea72a8798e3d1a495947976e3` | Base Sepolia |

After loop 2: deployer holds 34,000 mUSDC directly + 80 mVOL; vault holds 20 mVOL + 966,000 mUSDC; `isArmed[user]` = false; oracle price $1,700 (below threshold). The state machine cycled fully: armed → exit → disarmed → re-armed → exit → disarmed.

## Final balances (24 Nov 2026 ~14:00 WIB)

- Deployer Base Sepolia ETH: 0.019080856352016311
- Deployer Lasna lREACT: 3.81787499999867875
- SentinelReactive native balance: 0.05 lREACT; SYSTEM reserves 0.9159354 lREACT, debt 0 (4 react executions cost ~0.084 lREACT total)
- SentinelVault: 0.05 ETH, proxy debt 0
- `forge test`: 21/21 PASS (re-run after deployment)

## Verification status

**ALL 5 CONTRACTS VERIFIED ON SOURCIFY — exact_match (creation + runtime), 24 Nov 2026 ~17:04–17:05 WIB (retry approved by user 17:02 WIB).**

| Contract | Chain | Address | Sourcify | Verified at (UTC) |
|---|---|---|---|---|
| mVOL (MockToken) | Base Sepolia 84532 | `0x7Dae8cf8FBe375F7104633b10Ee93A2c502efdC3` | exact_match (runtime; creation null) | 2026-11-24T06:25:18Z |
| mUSDC (MockToken) | Base Sepolia 84532 | `0xE27b5C2B13410e9818D13420288C19bbE55C33A3` | exact_match (runtime; creation null) | 2026-11-24T06:25:18Z |
| PriceOracle | Base Sepolia 84532 | `0xf20E23497a5509A94eAc5e956948937dd436F5E9` | exact_match (creation + runtime) | 2026-11-24T10:04:38Z |
| SentinelVault | Base Sepolia 84532 | `0xBd22e422fBdA3487B5b63c4aacf3D9289cF8Df9D` | exact_match (creation + runtime) | 2026-11-24T10:04:43Z |
| SentinelReactive | Lasna 5318007 | `0x393Bca85F6eB00cFDd0D431ea47952b0F5Fc7CF8` | exact_match (creation + runtime) | 2026-11-24T10:05:22Z |

Notes on the retry (24 Nov 2026 ~17:03–17:05 WIB):
- The two MockTokens were ALREADY verified before this retry — the first (timed-out) attempt's submissions had landed on Sourcify at 06:25:18Z despite the timeouts. No re-submission was needed for them.
- PriceOracle: `forge verify-contract --chain 84532 --verifier sourcify ... --watch` succeeded on the retry (one transient Sourcify POST timeout, auto-retried by forge; job `7aca2d2a-27bf-4dbb-b67f-10afab3d14ae`).
- SentinelVault: same command succeeded (job `bdc4cab8-8ab8-49d6-bcba-0db22ad9455f`). Note: the address as written in this file's earlier sections (`0xbd22E422fbdA3487b5b63C4AACF3D9289cF8dF9D`) has non-canonical EIP-55 casing — Sourcify's API rejected it as "Invalid address". The canonical checksummed form is `0xBd22e422fBdA3487B5b63c4aacf3D9289cF8Df9D` (same address). Use the canonical form in any API call.
- Lasna / SentinelReactive: Sourcify DOES accept chain 5318007 for verification despite it not appearing in Sourcify's listed chains — `forge verify-contract --chain 5318007 --verifier sourcify --rpc-url https://lasna-rpc.rnk.dev/ ...` submitted and verified exact_match (job `332b0cb2-0380-4df1-b41f-c4c9bfbe13c3`). Earlier assumption that Sourcify doesn't support Lasna was wrong.
- Lasna explorer (lasna.reactscan.net) exposes NO public API: `/api/v2/*` returns 404 HTML and the classic `/api?module=contract...` returns the frontend HTML — it is a frontend-only explorer, so the Sourcify verification cannot be confirmed as displayed there from this VM. The contract is verified on Sourcify itself, which is the verifiable fact.
- BaseScan: Etherscan V1 API is deprecated and V2 requires an API key (no key available; none was created), so the BaseScan UI badge could not be confirmed via API from this VM. Etherscan-family explorers import Sourcify matches, so the source should display on sepolia.basescan.org address pages — confirm visually at submission time if needed.
- No redeploy was needed; verification was done from the repo + deployed addresses only.

## Notes / deviations

- `forge script` in Foundry 1.9.0 has NO `--value` flag (README examples used it); the `{ value: ... }` in the deploy scripts draws from the broadcaster's balance in broadcast mode — deployment worked without the flag.
- `isArmed` lives on the reactive contract (decision side), not in the Vault — per Gate 1 deviation note; the Vault enforces idempotency instead.
- Public Base Sepolia RPC (`sepolia.base.org`) limits `eth_getLogs` to a 200-block range — log queries must be chunked.
- Deployer key: throwaway testnet-only, in repo `.env` (0600, gitignored, never committed).
