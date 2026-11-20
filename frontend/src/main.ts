/**
 * Recurring Payments frontend (Track B — "Set It and Forget It").
 *
 * Read-only status works as soon as the contracts are deployed and the
 * addresses below are filled in. Writes (save schedule, fund) are
 * intentionally disabled until deployment: they need a connected wallet
 * and real contract addresses. Nothing here auto-connects a wallet.
 *
 * Chains:
 * - RSC: Reactive Lasna Testnet (chain 5318007, RPC https://lasna-rpc.rnk.dev/)
 * - Callback: Base Sepolia (chain 84532)
 */
import {
  createPublicClient,
  createWalletClient,
  custom,
  formatEther,
  http,
  parseEther,
} from "viem";
import "./style.css";

// ---------------------------------------------------------------------------
// TODO (deployment): fill these in after deploying (see README.md).
// ---------------------------------------------------------------------------
const RSC_ADDRESS = "" as const; // RecurringPaymentReactive on Lasna
const CALLBACK_ADDRESS = "" as const; // RecurringPaymentCallback on Base Sepolia

const LASNA_RPC = "https://lasna-rpc.rnk.dev/";
const BASE_SEPOLIA_RPC = "https://sepolia.base.org";
const LASNA_EXPLORER = "https://lasna.reactscan.net/address/";
const BASE_EXPLORER = "https://sepolia.basescan.org/address/";

const DEPLOYED = RSC_ADDRESS !== "" && CALLBACK_ADDRESS !== "";

// Minimal ABI: only the read methods the status panel needs.
const RSC_ABI = [
  { type: "function", name: "debt", stateMutability: "view", inputs: [], outputs: [{ type: "uint256" }] },
  { type: "function", name: "reserves", stateMutability: "view", inputs: [], outputs: [{ type: "uint256" }] },
  { type: "function", name: "paymentsRequested", stateMutability: "view", inputs: [], outputs: [{ type: "uint256" }] },
  { type: "function", name: "nextPaymentAt", stateMutability: "view", inputs: [], outputs: [{ type: "uint256" }] },
  { type: "function", name: "active", stateMutability: "view", inputs: [], outputs: [{ type: "bool" }] },
  { type: "function", name: "paymentAmount", stateMutability: "view", inputs: [], outputs: [{ type: "uint256" }] },
  { type: "function", name: "beneficiary", stateMutability: "view", inputs: [], outputs: [{ type: "address" }] },
] as const;

const CALLBACK_ABI = [
  { type: "function", name: "paymentsExecuted", stateMutability: "view", inputs: [], outputs: [{ type: "uint256" }] },
  { type: "function", name: "totalPaid", stateMutability: "view", inputs: [], outputs: [{ type: "uint256" }] },
  { type: "function", name: "beneficiary", stateMutability: "view", inputs: [], outputs: [{ type: "address" }] },
] as const;

const lasna = createPublicClient({ transport: http(LASNA_RPC) });
const baseSepolia = createPublicClient({ transport: http(BASE_SEPOLIA_RPC) });

const $ = (id: string) => document.getElementById(id) as HTMLElement;

function setText(id: string, value: string) {
  $(id).textContent = value;
}

async function refreshStatus() {
  if (!DEPLOYED) {
    setText("rsc-balance", "not deployed");
    setText("rsc-debt", "not deployed");
    setText("rsc-reserves", "not deployed");
    setText("rsc-payments", "not deployed");
    setText("rsc-next", "not deployed");
    setText("cb-balance", "not deployed");
    setText("cb-payments", "not deployed");
    setText("cb-total", "not deployed");
    return;
  }

  const rsc = RSC_ADDRESS as `0x${string}`;
  const cb = CALLBACK_ADDRESS as `0x${string}`;

  const [rscBalance, rscDebt, rscReserves, payments, nextAt, cbBalance, executed, total] =
    await Promise.all([
      lasna.getBalance({ address: rsc }),
      lasna.readContract({ address: rsc, abi: RSC_ABI, functionName: "debt" }),
      lasna.readContract({ address: rsc, abi: RSC_ABI, functionName: "reserves" }),
      lasna.readContract({ address: rsc, abi: RSC_ABI, functionName: "paymentsRequested" }),
      lasna.readContract({ address: rsc, abi: RSC_ABI, functionName: "nextPaymentAt" }),
      baseSepolia.getBalance({ address: cb }),
      baseSepolia.readContract({ address: cb, abi: CALLBACK_ABI, functionName: "paymentsExecuted" }),
      baseSepolia.readContract({ address: cb, abi: CALLBACK_ABI, functionName: "totalPaid" }),
    ]);

  setText("rsc-balance", `${formatEther(rscBalance)} lREACT`);
  setText("rsc-debt", `${formatEther(rscDebt)} lREACT`);
  setText("rsc-reserves", `${formatEther(rscReserves)} lREACT`);
  setText("rsc-payments", payments.toString());
  setText(
    "rsc-next",
    nextAt === 0n ? "—" : new Date(Number(nextAt) * 1000).toLocaleString(),
  );
  setText("cb-balance", `${formatEther(cbBalance)} ETH`);
  setText("cb-payments", executed.toString());
  setText("cb-total", `${formatEther(total)} ETH`);
}

function wireUp() {
  if (DEPLOYED) {
    ($("rsc-link") as HTMLAnchorElement).href = LASNA_EXPLORER + RSC_ADDRESS;
    ($("rsc-link") as HTMLAnchorElement).textContent = RSC_ADDRESS;
    ($("cb-link") as HTMLAnchorElement).href = BASE_EXPLORER + CALLBACK_ADDRESS;
    ($("cb-link") as HTMLAnchorElement).textContent = CALLBACK_ADDRESS;
    ($("deploy-banner") as HTMLElement).textContent =
      "✅ Contracts deployed — status is live.";
    ($("save-btn") as HTMLButtonElement).disabled = false;
    ($("fund-rsc-btn") as HTMLButtonElement).disabled = false;
    ($("fund-cb-btn") as HTMLButtonElement).disabled = false;
  }

  $("refresh-btn").addEventListener("click", () => {
    refreshStatus().catch((e) => {
      console.error(e);
      alert(`Status refresh failed: ${e instanceof Error ? e.message : e}`);
    });
  });

  // Explicit, manual wallet connection — never automatic.
  $("connect-btn").addEventListener("click", async () => {
    const eth = (window as unknown as { ethereum?: unknown }).ethereum;
    if (!eth) {
      alert("No injected wallet found (MetaMask etc.).");
      return;
    }
    const wallet = createWalletClient({ transport: custom(eth as never) });
    const [account] = await wallet.getAddresses();
    $("wallet-status").textContent = `Connected: ${account}`;
    console.log("Connected account:", account);
  });

  // Writes are stubs until deployment: they show what they WOULD do.
  $("config-form").addEventListener("submit", (e) => {
    e.preventDefault();
    if (!DEPLOYED) return;
    const beneficiary = ($("beneficiary") as HTMLInputElement).value;
    const amount = parseEther(($("amount") as HTMLInputElement).value || "0");
    const interval = Number(($("interval") as HTMLSelectElement).value);
    alert(
      `TODO (wire to wallet): setBeneficiary(${beneficiary}), setPaymentAmount(${amount} wei), setInterval(${interval}s) on the RSC.`,
    );
  });

  refreshStatus().catch(console.error);
}

wireUp();
