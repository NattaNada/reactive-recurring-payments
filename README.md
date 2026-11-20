# Recurring Payments — Reactive Omni Buildathon, Track B

**“Set It and Forget It”** — configure a recurring payment once, and a
Reactive Smart Contract (RSC) runs it by itself. No bot, no keeper, no
server, no off-chain automation.

- **Buildathon:** [Reactive Omni Buildathon](https://dorahacks.io/hackathon/reactive-omni-buildathon)
- **Track:** B — Set It and Forget It (pool $1,500: 1st $1,000 / 2nd $500; total buildathon $5,500 in REACT)
- **Deadline:** **6 Dec 2026 03:00 WIB** (5 Dec 2026 20:00 UTC)
- **Status:** scaffold complete — `forge build` ✅, `forge test` 19/19 ✅, frontend builds ✅. **Not deployed yet.**

## What it does

1. The user sets a schedule once: beneficiary, fixed amount, interval (daily by default, 10 minutes for demo).
2. `RecurringPaymentReactive` (on Reactive Lasna Testnet) subscribes to CRON ticks. When a payment is due, it asks the system contract to deliver a callback to `RecurringPaymentCallback` (on Base Sepolia).
3. The callback contract pays the fixed amount of the destination chain's native currency (ETH on Base Sepolia) to the beneficiary.
4. Bonus path: the RSC can also watch ERC-20 top-ups to the callback contract — a top-up at or above a threshold triggers one immediate bonus payment and restarts the schedule.

The RSC is the engine, not a forwarder: the schedule, the due-check, the top-up logic, and the callback request all live inside it. An optional AI helper (natural-language rule phrasing + Reactive MCP diagnosis during development) never decides anything on-chain.

## Architecture

```
CRON tick (Lasna) ──► RecurringPaymentReactive ──► SYSTEM.requestCallbackV_1_0
                          │  (react(), onlySystem)              │
                          │  checks due / top-up                ▼
                          │                          RecurringPaymentCallback
ERC-20 Transfer ──────────┘                          (Base Sepolia)
   (optional top-up watch)                              │ onlyServiceProvider
                                                        │ + onlyCallbackSender
                                                        ▼
                                              pays beneficiary (fixed ETH)
```

- **RSC:** `src/RecurringPaymentReactive.sol` — inherits `AbstractReactive` from the official Omni library (`Reactive-Network/reactive-lib-omni` v0.1.0). Omni model only: system contract `0x8888...8888`, `react()` guarded by `onlySystem`, callbacks via `requestCallbackV_1_0`. (The legacy `0xfffF` system contract is used only as the *emitter* of Cron events, exactly as the current docs prescribe.)
- **Callback:** `src/RecurringPaymentCallback.sol` — inherits `AbstractCallback`; `executePayment(address,uint256)` guarded by `onlyServiceProvider` + `onlyCallbackSender`. The first payload argument is the `address(0)` placeholder the proxy overwrites with the RSC address.
- **Dependencies:** `lib/` contains vendored copies of `forge-std` and `reactive-lib-omni` (plain files, not git submodules), so a plain clone builds with `forge build` and no `forge install` step.
- **Frontend:** `frontend/` — Vite + TypeScript + viem. Config form, read-only status panel (RSC balance/debt/reserves, payments requested, next payment; callback balance, payments executed, total paid), fund buttons, explicit manual wallet connect. Writes stay disabled until deployment.

## Project layout

```
├── foundry.toml / remappings.txt / .env.example
├── src/
│   ├── RecurringPaymentReactive.sol   # RSC (Lasna)
│   └── RecurringPaymentCallback.sol   # callback (Base Sepolia)
├── script/Deploy.s.sol                # DeployReactive / DeployCallback / SetCallback
├── test/
│   ├── RecurringPaymentReactive.t.sol # 12 tests
│   └── RecurringPaymentCallback.t.sol # 7 tests
├── frontend/                          # Vite + viem skeleton
└── README.md
```

## Build & test

```bash
forge build
forge test            # 19 tests, all passing
cd frontend && npm install && npm run build
```

## Funding (verified from dev.reactive.network, 19 Nov 2026)

**Lasna lREACT faucet** — send Sepolia ETH to one of these faucet contracts (plain transfer, or `request(address)` with value):
- Ethereum Sepolia: `0x9b9BB25f1A81078C544C829c5EB7822d747Cf434`
- Base Sepolia: `0x2afaFD298b23b62760711756088F75B7409f5967`

Rate: **1 ETH → 100 lREACT. Max 5 ETH per transaction (500 lREACT) — anything above 5 ETH is lost.**

The RSC pays for reactive transactions in lREACT; the callback contract pays for callback execution in ETH (Base Sepolia) and holds the payment funds. Fund both before the first payment:

```bash
# RSC reserves (preferred: becomes spendable reserves, settles debt first)
cast send --rpc-url https://lasna-rpc.rnk.dev/ --private-key $PRIVATE_KEY \
  0x8888888888888888888888888888888888888888 "depositTo(address)" $RSC_ADDRESS --value 1ether

# Callback reserves (Base Sepolia proxy)
cast send --rpc-url https://sepolia.base.org --private-key $PRIVATE_KEY \
  0x476F44b11F5C942c58f4c8E3d0300E5710743585 "depositTo(address)" $CALLBACK_ADDRESS --value 0.1ether

# Or fund the contracts directly, then settle debt:
cast send $RSC_ADDRESS --rpc-url https://lasna-rpc.rnk.dev/ --private-key $PRIVATE_KEY --value 1ether
cast send --rpc-url https://lasna-rpc.rnk.dev/ --private-key $PRIVATE_KEY $RSC_ADDRESS "coverDebt()"
```

Check status any time:

```bash
cast balance $RSC_ADDRESS --rpc-url https://lasna-rpc.rnk.dev/
cast call 0x8888888888888888888888888888888888888888 "debt(address)" $RSC_ADDRESS --rpc-url https://lasna-rpc.rnk.dev/ | cast to-dec
cast call 0x8888888888888888888888888888888888888888 "reserves(address)" $RSC_ADDRESS --rpc-url https://lasna-rpc.rnk.dev/ | cast to-dec
```

A contract in debt receives nothing — keep both funded and watch debt on [lasna.reactscan.net](https://lasna.reactscan.net/).

## Deploy (manual step — needs the user's go-ahead)

```bash
cp .env.example .env   # fill in PRIVATE_KEY, BENEFICIARY, PAYMENT_AMOUNT_WEI, INTERVAL_SECONDS
source .env

# 1. RSC on Lasna (chain 5318007)
forge script script/Deploy.s.sol:DeployReactive \
  --rpc-url https://lasna-rpc.rnk.dev/ --broadcast --chain-id 5318007

# 2. Callback on Base Sepolia (chain 84532), with RSC_ADDRESS set
forge script script/Deploy.s.sol:DeployCallback \
  --rpc-url https://sepolia.base.org --broadcast --chain-id 84532

# 3. Point the RSC at the callback (RSC_ADDRESS + CALLBACK_ADDRESS set)
forge script script/Deploy.s.sol:SetCallback \
  --rpc-url https://lasna-rpc.rnk.dev/ --broadcast --chain-id 5318007

# 4. Fund both contracts (see "Funding" above), then fill the addresses
#    into frontend/src/main.ts (RSC_ADDRESS / CALLBACK_ADDRESS).
```

**Deployment order matters:** the callback needs the RSC address at construction, and the RSC needs the callback address before it can name a recipient — hence step 3's owner-only `setCallback()`.

**Verify on Reactscan/Sourcify** (required for the execution gate):

```bash
forge verify-contract --verifier sourcify --chain-id 5318007 \
  $RSC_ADDRESS src/RecurringPaymentReactive.sol:RecurringPaymentReactive
forge verify-contract --verifier sourcify --chain-id 84532 \
  $CALLBACK_ADDRESS src/RecurringPaymentCallback.sol:RecurringPaymentCallback
```

## Test end-to-end (after deployment)

1. Deploy with `INTERVAL_SECONDS=600` (10 min) and Cron1000 ticks (~17 min) — or `triggerPaymentNow()` on the RSC for an instant demo payment.
2. Watch the RSC on [lasna.reactscan.net](https://lasna.reactscan.net/): a reactive transaction should appear at the next due tick.
3. Watch the callback on [sepolia.basescan.org](https://sepolia.basescan.org/): a callback transaction paying the beneficiary.
4. Confirm `paymentsRequested` (RSC) and `paymentsExecuted` / `totalPaid` (callback) increment — also visible in the frontend status panel.
5. Optional: send an ERC-20 transfer ≥ threshold to the callback contract and watch the bonus payment fire.

## Judging (from the buildathon page — corrected)

There is **no 80/20 technical/video split**. First an **execution gate**: entries without a reactive transaction + callbacks visible on Reactscan are not scored further. After the gate, 4 equally-weighted criteria scored 1–5: **Execution** (does it work when tested? live demo? reactive tx + callbacks visible?), **Integration** (how uniquely does it use Reactive? how much work lives inside the RSC?), **Usefulness** (real problem? would someone use it after the hackathon?), **Craft** (code quality, docs, polish). Track B emphasis: the RSC must be the engine, not a forwarder.

Submission requirements: public repo with all code + README, demo video **< 3 minutes** showing a **live** working demo (not slides), at least one RSC deployed + verified on Reactscan, one team = one submission, original work, no external automation (Chainlink Automation, Keeper, Gelato, …), no fully-AI-generated submission.

## TODO before submission

- [ ] Create the public GitHub repo (suggested: `NattaNada/reactive-recurring-payments`) and push this project
- [ ] Deploy RSC to Lasna + callback to Base Sepolia (needs deployer key — user decision)
- [ ] Fund both contracts (lREACT via faucet above; ETH on Base Sepolia)
- [ ] Verify both contracts on Sourcify / Reactscan
- [ ] Run the end-to-end test above; confirm reactive tx + callback tx on the explorers
- [ ] Fill deployed addresses into `frontend/src/main.ts`; deploy the frontend (e.g. GitHub Pages / Vercel) so judges can try it
- [ ] Record the demo video (< 3 min, live demo: configure → wait for tick → reactive tx → callback tx → beneficiary paid)
- [ ] Submit the build on DoraHacks before **6 Dec 2026 03:00 WIB**

## References

- Docs: https://dev.reactive.network/ (Reactive Contracts, Callback Contracts, Economy, Origins & Destinations, Lasna Testnet)
- Omni library: https://github.com/Reactive-Network/reactive-lib-omni (v0.1.0)
- Demo patterns (Cron template): https://github.com/Reactive-Network/reactive-smart-contract-demos
- Reactive MCP (diagnosis during development, never asks for keys): https://mcp.rnk.dev/mcp
- Buildathon: https://dorahacks.io/hackathon/reactive-omni-buildathon
