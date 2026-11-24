# Deployments — Reactive Sentinel Vault

Status: **NOT YET DEPLOYED** — blocked on testnet faucet funds (see below).

## Target deployment

| Contract | Chain | Address |
|---|---|---|
| mVOL (MockToken) | Base Sepolia (84532) | TBD |
| mUSDC (MockToken) | Base Sepolia (84532) | TBD |
| PriceOracle | Base Sepolia (84532) | TBD |
| SentinelVault | Base Sepolia (84532) | TBD |
| SentinelReactive | Lasna (5318007) | TBD |

Threshold: $1,800 (1800e18). Initial price: $2,000 (2000e18). Recovery: $1,890.

## Full-loop proof (to be filled after deployment)

| Step | Tx hash |
|---|---|
| Origin: VaultDeposit (deposit 10 mVOL) | TBD |
| Reactive tx on Lasna (react + callback request) | TBD |
| Callback tx on Base Sepolia (exitToStable) | TBD |
| Origin: PriceUpdated breach ($1700) | TBD |
| Origin: PriceRecovered ($1890) | TBD |
| Second breach + second exit | TBD |

## Blocker

Deployer (throwaway, testnet-only): `0xD35fC23984871E8b814dc3f919C1C551936D4F84`
(balance 0 on Base Sepolia and Sepolia as of 24 Nov 2026 ~13:20 WIB).

Faucet attempts (all public, no login available to the builder):
- **Alchemy Base Sepolia faucet**: no account needed, 0.1 ETH/24h — but requires ≥0.001 ETH
  on Ethereum mainnet + mainnet activity on the claiming wallet. Fresh throwaway wallet
  is ineligible.
- **pk910.de Sepolia PoW faucet**: live config confirms cryptonight PoW, difficulty 11,
  min claim 0.05 ETH — but session start requires a captcha token (`requiredForStart:
  true`, hCaptcha/reCAPTCHA/Turnstile/custom). Direct API start returned nothing.
- **Chainlink faucet**: requires connecting a wallet in the browser.
- **QuickNode faucet**: requires completing a bot-check verification.
- **Coinbase CDP / Superchain / Google Cloud / GetBlock**: account sign-in required.

What unblocks it: 0.1 Base Sepolia ETH sent to the deployer address above (e.g. claimed
from the Alchemy faucet with a wallet that has mainnet history, or from the Chainlink
faucet). Then: ~0.05 ETH of it goes to the Reactive faucet contract
(`0x2afaFD298b23b62760711756088F75B7409f5967` on Base Sepolia) for lREACT, and the rest
funds the deployments + the vault's callback reserves.
