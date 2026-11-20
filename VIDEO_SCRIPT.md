# Demo video script — Recurring Payments (Track B)

**Format:** screen recording with voiceover (no slides). **Total: 2:55 — under 3 minutes.**
**Record on a computer with the frontend open in one tab and the two
explorers in other tabs.** Have all links open BEFORE you start recording.
Speak naturally; the demo is live, so times on screen are real.

## Links to have open while recording

| Tab | URL |
|---|---|
| Frontend | https://nattanada.github.io/reactive-recurring-payments/ |
| RSC (Reactscan) | https://lasna.reactscan.net/address/0xE14884a4Db5c97B3ab8d3C4430d6f3aD085E1346 |
| Callback (Basescan) | https://sepolia.basescan.org/address/0x995b75ef4B84E346Dc2fDC73f60554469f24eb9E |
| Reactive tx (proof) | https://lasna.reactscan.net/tx/0xabaacc73cd4c3521d7cb957b51e70f8cc8ebfcdbc34081c5ee6ce110a4b0dbf6 |
| Callback tx (proof) | https://sepolia.basescan.org/tx/0x3d1f165ff29b70faad2a8042d717f3695e74815c40cd5e5e64f18c6f72147b39 |
| Repo | https://github.com/NattaNada/reactive-recurring-payments |

Live facts (20 Nov 2026): beneficiary `0xa2e0e5EB2F94b5267b09ECDEb2F90B06261276DD`,
0.01 ETH per payment, interval 600 s (10 min), Cron1000 ticks (~17 min).
Callback holds ~0.09 ETH (9 payments). RSC reserves ~3 lREACT, debt 0.

## Shot list

### Shot 0 — Intro (0:00–0:08, 8 s)
Show the frontend header. Say: *"Recurring Payments — set a schedule once,
and a Reactive Smart Contract pays it by itself. No bot, no keeper, no
server."*

### Shot 1 — The schedule + live status (0:08–0:50, 42 s)
- Frontend, section 1: show the pre-filled config — beneficiary `0xa2e0…`,
  amount **0.01 ETH**, interval **Every 10 minutes (demo)**.
- Scroll to section 2 (status): point at RSC balance / debt / reserves,
  **Payments requested**, **Next payment**, callback balance, **Payments
  executed**, **Total paid**. Say: *"This is live on-chain data — the RSC on
  Reactive Lasna, the callback on Base Sepolia."*
- Click **Refresh status** once to show it updates.

### Shot 2 — Wait for the CRON tick (0:50–1:15, 25 s)
- Point at **Next payment** (a time a few minutes away).
- Say: *"The RSC listens to CRON ticks. When the payment is due, it asks the
  system contract for a callback — nobody triggers it."*
- Wait (or cut) until **Payments requested** increments by 1. Refresh the
  status to show the new count and the next payment time moving +10 min.
- Tip: start recording a few minutes before the next payment is due (read
  "Next payment" on the frontend), so the wait is short.

### Shot 3 — Reactive transaction on Reactscan (1:15–1:50, 35 s)
- Open the RSC address on Reactscan → Transactions → open the newest
  reactive transaction.
- Show the **PaymentRequested** event (paymentId, amount 0.01 ETH) and the
  callback request to the Base Sepolia callback.
- Say: *"That transaction was fired by the CRON tick itself — the RSC is the
  engine, not a forwarder."*
- (Already-proven example tx: `0xabaacc73…0dbf6`, block 8786001.)

### Shot 4 — Callback transaction on Basescan (1:50–2:25, 35 s)
- Open the callback address on Basescan → Transactions → open the matching
  callback transaction.
- Show the **PaymentExecuted** event (RSC `0xE14884…`, beneficiary
  `0xa2e0e5…`, paymentId, amount 0.01 ETH).
- Say: *"The callback paid the beneficiary on Base Sepolia — same paymentId,
  same amount."*
- (Already-proven example tx: `0x3d1f165f…47b39`, block 61144859.)

### Shot 5 — The money moved + close (2:25–2:55, 30 s)
- Back on the frontend, refresh status: **Payments executed** up by 1,
  **Total paid** up by 0.01 ETH, callback balance down by 0.01 ETH.
- Optionally show the beneficiary balance on Basescan (+0.01 ETH).
- Say: *"One schedule, set once — the contract keeps paying every ten
  minutes. Repo and contracts are linked below."* End.

## Recording tips

- Record the screen + your voice (OBS, Loom, or phone screen-record with mic).
  No slides, no static images — judges must see it working live.
- If a payment does not land within the shot, do NOT fake it: keep the
  already-proven transactions (Shot 3/4 links above) on screen and narrate
  them, then show the live counters catching up.
- Keep the wallet disconnected during recording unless you demo a write;
  the status panel needs no wallet.
- Check audio levels before the take; one clean take beats three edited ones.
- Export < 3:00 total. If the take runs long, trim pauses, not content.
