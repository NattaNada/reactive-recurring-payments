# Deployment Record — Recurring Payments (Reactive Omni Buildathon, Track B)

Deployed: **20 Nov 2026** (all times UTC unless noted). Deployer + beneficiary:
burner `0xa2e0e5EB2F94b5267b09ECDEb2F90B06261276DD` (testnet only).

## Repository

- **https://github.com/NattaNada/reactive-recurring-payments**
- Initial snapshot commit: `83ae748c054f470fe5fa32f188387407c825c9f3`
  (176 files; `lib/` vendored as plain files, not submodules — snapshot push
  cannot represent gitlinks. `frontend/src/assets/hero.png` excluded: unused
  Vite template asset, binary, not referenced anywhere.)
- Note: the provider created its own empty-repo initial commit `500cae79`
  ("Initial commit") seconds before the snapshot; the snapshot commit replaced
  its generated README with the project README.

## Deployment parameters

| Param | Value |
|---|---|
| BENEFICIARY | `0xa2e0e5EB2F94b5267b09ECDEb2F90B06261276DD` |
| PAYMENT_AMOUNT_WEI | `10000000000000000` (0.01 ETH) |
| INTERVAL_SECONDS | `600` (10 min, demo interval) |
| FUND_REACT_WEI (RSC constructor) | `2000000000000000000` (2 lREACT) |
| FUND_ETH_WEI (callback constructor) | `50000000000000000` (0.05 ETH) |
| CRON topic | Cron1000 (~17 min ticks) |
| Top-up watch | disabled (`WATCHED_TOKEN = 0x0`) |

## Funding — Lasna lREACT faucet

- Sent **0.1 Sepolia ETH** to faucet `0x9b9BB25f1A81078C544C829c5EB7822d747Cf434`
- Faucet tx (Sepolia): `0x6277c8f395eefbaab04dbc2b1c4014812aaf2cb316118ff0b53b405aa95b86b2` (status 1)
- Credited **10 lREACT** to the burner on Lasna (balance check immediately after: `10000000000000000000`).

## Contracts

### RSC — RecurringPaymentReactive (Reactive Lasna, chain 5318007)

- Address: `0xE14884a4Db5c97B3ab8d3C4430d6f3aD085E1346`
- Deploy tx (Lasna): `0xf75b6f160231ce325e04aca768761072dcbcd97d3de33372841e3d43f1afe70e`
- Explorer: https://lasna.reactscan.net/address/0xE14884a4Db5c97B3ab8d3C4430d6f3aD085E1346
- First payment due: unix `1795150767` (2026-11-20 04:59:27 UTC / 11:59:27 WIB)
- Balance at deploy: `2000000000000000000` (2 lREACT), debt `0`, reserves `0`

### Callback — RecurringPaymentCallback (Base Sepolia, chain 84532)

- Address: `0x995b75ef4B84E346Dc2fDC73f60554469f24eb9E`
- Deploy tx (Base Sepolia): `0x161ee3df55226b0c09b1170422b12b39c76b54863cc330f7238da5389c4e3061`
- Explorer: https://sepolia.basescan.org/address/0x995b75ef4B84E346Dc2fDC73f60554469f24eb9E
- Balance at deploy: `50000000000000000` (0.05 ETH)

### SetCallback (Lasna)

- Tx: `0x72c68999b25c9bb4467bb3160c929c3667b3ce68a9848243468b5c48bb4dd711` (status 1)
- RSC callback set to `0x995b75ef4B84E346Dc2fDC73f60554469f24eb9E`

### Extra RSC reserves (preferred funding path)

- `depositTo(RSC)` — **3 lREACT** to the system contract
  `0x8888888888888888888888888888888888888888`
- Tx (Lasna): `0x666de3849e39da67dd8c0721d858856b725ccb349e437d22ce70f2cf334a28ca` (status 1)
- After: RSC reserves `3000000000000000000` (3 lREACT), debt `0`,
  RSC balance `2000000000000000000` (2 lREACT),
  burner Lasna balance `5340343599998403436` (~5.34 lREACT).

## Verification (Sourcify — required for the execution gate)

Both contracts verified with **exact_match** at 2026-11-20T04:51:10Z:

| Contract | Chain | Job | Result |
|---|---|---|---|
| RecurringPaymentReactive `0xE14884a4Db5c97B3ab8d3C4430d6f3aD085E1346` | 5318007 | `92e8cf2c-b734-4acc-80d1-e2cb85542c82` | exact_match |
| RecurringPaymentCallback `0x995b75ef4B84E346Dc2fDC73f60554469f24eb9E` | 84532 | `3b7a9f63-e7d3-409c-9bb2-69ec1f1cf108` | exact_match |

Verify links:
- https://sourcify.dev/server/verify-ui/jobs/92e8cf2c-b734-4acc-80d1-e2cb85542c82
- https://sourcify.dev/server/verify-ui/jobs/3b7a9f63-e7d3-409c-9bb2-69ec1f1cf108

## End-to-end test

Baseline (2026-11-20 04:51:23 UTC, before first due payment):

- Beneficiary Base Sepolia balance: `99995915385997148` wei (~0.0999959 ETH)
- RSC `paymentsRequested`: `0`
- Callback `paymentsExecuted`: `0`

First payment due 2026-11-20 04:59:27 UTC (11:59:27 WIB); Cron1000 tick
expected within ~17 min after that.

**Status: ✅ CONFIRMED — end-to-end works via natural CRON tick
(no manual trigger needed).**

Timeline (UTC 2026-11-20):

- 04:59:27 — first payment due (unix `1795150767`)
- 05:00:38 — CRON tick fires `react()` on the RSC
- 05:00:40 — callback executes the payment on Base Sepolia

Evidence:

- **Reactive tx (Lasna):**
  `0xabaacc73cd4c3521d7cb957b51e70f8cc8ebfcdbc34081c5ee6ce110a4b0dbf6`,
  block `8786001`, status 1 —
  https://lasna.reactscan.net/tx/0xabaacc73cd4c3521d7cb957b51e70f8cc8ebfcdbc34081c5ee6ce110a4b0dbf6
  (contains the `PaymentRequested` event: paymentId 1, amount 0.01 ETH,
  and the system-contract callback request to the Base Sepolia callback)
- **Callback tx (Base Sepolia):**
  `0x3d1f165ff29b70faad2a8042d717f3695e74815c40cd5e5e64f18c6f72147b39`,
  block `61144859`, status 1 —
  https://sepolia.basescan.org/tx/0x3d1f165ff29b70faad2a8042d717f3695e74815c40cd5e5e64f18c6f72147b39
  (contains the `PaymentExecuted` event: RSC `0xE14884…`, beneficiary
  `0xa2e0e5…`, paymentId 1, amount 0.01 ETH)

On-chain counters after the payment (checked 05:01–05:02 UTC):

- RSC `paymentsRequested`: `1`
- Callback `paymentsExecuted`: `1`
- Callback `totalPaid`: `0x2386f26fc10000` (0.01 ETH)
- Beneficiary Base Sepolia balance: `99995915385997148` → `109995915385997148`
  wei — exactly **+0.01 ETH**
- RSC `nextPaymentAt`: `1795151438` (2026-11-20 05:10:38 UTC / 12:10:38 WIB)
  — the schedule keeps recurring every 600 s
- RSC debt `0`, reserves `~2.997` lREACT, RSC balance `2` lREACT,
  callback balance `39999060021400000` wei (~0.04 ETH — enough for 4 more
  0.01 ETH payments)

## Burner balances (start of deployment)

- Sepolia: `449999999999136000` wei (~0.45 ETH) → ~0.35 ETH after faucet send + gas
- Base Sepolia: `149999495999999630` wei (~0.15 ETH) → ~0.0999959 ETH after callback funding + deploy gas
- Lasna: `0` lREACT → 10 lREACT via faucet → ~5.34 lREACT after RSC funding (2), reserves deposit (3), and gas
