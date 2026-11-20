# DoraHacks submission draft — Recurring Payments (Track B)

> **DRAFT ONLY — DO NOT SUBMIT YET.** This file is the preview for the
> user. Actual submission happens on DoraHacks (Submit Build on the
> buildathon page) after the demo video is recorded and the user approves
> the final text. Deadline: **6 Dec 2026 03:00 WIB** (5 Dec 20:00 UTC).

## Title

**Recurring Payments — Set It and Forget It**

## Track

**B — Set It and Forget It** (prize pool $1,500: 1st $1,000 / 2nd $500;
total buildathon $5,500 in REACT)

## Short description (≤ 500 characters)

A Reactive Smart Contract that pays a fixed amount on a schedule you set
once — no bot, no keeper, no server. The RSC on Reactive Lasna listens to
CRON ticks and, when a payment is due, requests a callback that pays the
beneficiary on Base Sepolia. Live demo: every 10 minutes, 0.01 ETH, fully
on-chain and verifiable on Reactscan.

## Long description

Configure a recurring payment once — beneficiary, fixed amount, interval —
and a Reactive Smart Contract runs it by itself. `RecurringPaymentReactive`
on Reactive Lasna subscribes to CRON ticks; on each tick it checks whether
a payment is due and, if so, asks the system contract for a callback to
`RecurringPaymentCallback` on Base Sepolia, which pays the fixed amount of
ETH to the beneficiary.

The RSC is the engine, not a forwarder: the schedule, the due-check, the
top-up logic, and the callback request all live inside it. A bonus path
watches ERC-20 top-ups to the callback contract — a top-up at or above a
threshold triggers one immediate bonus payment and restarts the schedule.
The RSC also supports pause/resume, manual trigger (owner), and debt
coverage, all visible in the frontend status panel.

An optional AI helper (natural-language rule phrasing + Reactive MCP
diagnosis during development) never decides anything on-chain.

## Links

- **Repo (public):** https://github.com/NattaNada/reactive-recurring-payments
- **Frontend (live demo):** https://nattanada.github.io/reactive-recurring-payments/
- **RSC (Lasna, chain 5318007):** `0xE14884a4Db5c97B3ab8d3C4430d6f3aD085E1346`
  - Reactscan: https://lasna.reactscan.net/address/0xE14884a4Db5c97B3ab8d3C4430d6f3aD085E1346
  - Sourcify (exact_match): https://sourcify.dev/server/verify-ui/jobs/92e8cf2c-b734-4acc-80d1-e2cb85542c82
- **Callback (Base Sepolia, chain 84532):** `0x995b75ef4B84E346Dc2fDC73f60554469f24eb9E`
  - Basescan: https://sepolia.basescan.org/address/0x995b75ef4B84E346Dc2fDC73f60554469f24eb9E
  - Sourcify (exact_match): https://sourcify.dev/server/verify-ui/jobs/3b7a9f63-e7d3-409c-9bb2-69ec1f1cf108
- **Demo video (< 3 min):** _PLACEHOLDER — record first (see VIDEO_SCRIPT.md),
  then paste the link here._
- **Deployment record:** https://github.com/NattaNada/reactive-recurring-payments/blob/main/DEPLOYMENT.md

## Proof of execution (for the judges)

- **Reactive tx (Lasna):**
  `0xabaacc73cd4c3521d7cb957b51e70f8cc8ebfcdbc34081c5ee6ce110a4b0dbf6`
  (block 8786001 — `PaymentRequested`, paymentId 1, 0.01 ETH)
  https://lasna.reactscan.net/tx/0xabaacc73cd4c3521d7cb957b51e70f8cc8ebfcdbc34081c5ee6ce110a4b0dbf6
- **Callback tx (Base Sepolia):**
  `0x3d1f165ff29b70faad2a8042d717f3695e74815c40cd5e5e64f18c6f72147b39`
  (block 61144859 — `PaymentExecuted`, paymentId 1, 0.01 ETH)
  https://sepolia.basescan.org/tx/0x3d1f165ff29b70faad2a8042d717f3695e74815c40cd5e5e64f18c6f72147b39
- Beneficiary balance **+0.01 ETH exactly**; `paymentsRequested` 0→1,
  `paymentsExecuted` 0→1, `totalPaid` 0.01 ETH — verified on-chain.
- The schedule keeps recurring every 600 s (10 min demo interval).

## Submission checklist

- [x] Public repo with all code + README
- [x] At least one RSC deployed + verified on Reactscan (Sourcify exact_match)
- [x] Reactive transaction + callback transaction visible on explorers
- [x] Frontend deployed (GitHub Pages, `gh-pages` branch) — see note below
- [ ] Demo video < 3 minutes (script ready in VIDEO_SCRIPT.md — **not recorded yet**)
- [ ] Submit build on DoraHacks (needs user login + approval)

## Notes for the submitter

- **GitHub Pages:** the built frontend is pushed to the `gh-pages` branch
  (commit `458dcdf30cc8a3e2cdd55f23d51a36694992a771`), but GitHub Pages
  must be enabled once in repo Settings → Pages → Source: Deploy from a
  branch → `gh-pages`. Until then the URL returns 404. Enable it before
  submitting so judges can open the link.
- **Demo funds:** callback holds ~0.09 ETH (9 payments of 0.01 ETH) after
  the 0.05 ETH top-up on 20 Nov 2026; RSC reserves ~3 lREACT, debt 0.
  The demo keeps paying every 10 minutes until the callback runs dry.
- **Video:** record from the user's own device (screen + voice), following
  VIDEO_SCRIPT.md. Video generation is unavailable for this account, so
  there is no AI-generated alternative.
