/**
 * Recurring Payments frontend (Track B — "Set It and Forget It").
 *
 * Deployed 20 Nov 2026:
 * - RSC 0xE14884a4Db5c97B3ab8d3C4430d6f3aD085E1346 on Reactive Lasna (5318007)
 * - Callback 0x995b75ef4B84E346Dc2fDC73f60554469f24eb9E on Base Sepolia (84532)
 *
 * Status panel is read-only and works without a wallet. Writes (save
 * schedule, fund) need a connected wallet (MetaMask etc.) and only run
 * after an explicit user action — nothing here auto-connects a wallet.
 *
 * Chains:
 * - RSC: Reactive Lasna Testnet (chain 5318007, RPC https://lasna-rpc.rnk.dev/)
 * - Callback: Base Sepolia (chain 84532)
 */
import {
  createPublicClient,
  createWalletClient,
  custom,
  defineChain,
  formatEther,
  http,
  parseEther,
} from "viem";
import { baseSepolia } from "viem/chains";
import "./style.css";

// ---------------------------------------------------------------------------
// Deployment (see DEPLOYMENT.md).
// ---------------------------------------------------------------------------
const RSC_ADDRESS = "0xE14884a4Db5c97B3ab8d3C4430d6f3aD085E1346" as const; // RecurringPaymentReactive on Lasna
const CALLBACK_ADDRESS = "0x995b75ef4B84E346Dc2fDC73f60554469f24eb9E" as const; // RecurringPaymentCallback on Base Sepolia

const LASNA_RPC = "https://lasna-rpc.rnk.dev/";
const BASE_SEPOLIA_RPC = "https://sepolia.base.org";
const LASNA_EXPLORER = "https://lasna.reactscan.net/address/";
const BASE_EXPLORER = "https://sepolia.basescan.org/address/";

// System contract (Omni) on Lasna and callback proxy on Base Sepolia —
// both expose depositTo(address) so funds become spendable reserves.
const SYSTEM_CONTRACT = "0x8888888888888888888888888888888888888888" as const;
const BASE_SEPOLIA_PROXY = "0x476F44b11F5C942c58f4c8E3d0300E5710743585" as const;

const DEPLOYED = RSC_ADDRESS.length > 0 && CALLBACK_ADDRESS.length > 0;

const lasnaChain = defineChain({
  id: 5318007,
  name: "Reactive Lasna",
  nativeCurrency: { name: "lREACT", symbol: "lREACT", decimals: 18 },
  rpcUrls: { default: { http: [LASNA_RPC] } },
  blockExplorers: {
    default: { name: "Reactscan", url: "https://lasna.reactscan.net" },
  },
  testnet: true,
});

// Minimal ABI: reads for the status panel + the owner-only writes the
// config form and fund buttons need.
const RSC_ABI = [
  { type: "function", name: "debt", stateMutability: "view", inputs: [], outputs: [{ type: "uint256" }] },
  { type: "function", name: "reserves", stateMutability: "view", inputs: [], outputs: [{ type: "uint256" }] },
  { type: "function", name: "paymentsRequested", stateMutability: "view", inputs: [], outputs: [{ type: "uint256" }] },
  { type: "function", name: "nextPaymentAt", stateMutability: "view", inputs: [], outputs: [{ type: "uint256" }] },
  { type: "function", name: "active", stateMutability: "view", inputs: [], outputs: [{ type: "bool" }] },
  { type: "function", name: "paymentAmount", stateMutability: "view", inputs: [], outputs: [{ type: "uint256" }] },
  { type: "function", name: "intervalSeconds", stateMutability: "view", inputs: [], outputs: [{ type: "uint256" }] },
  { type: "function", name: "beneficiary", stateMutability: "view", inputs: [], outputs: [{ type: "address" }] },
  { type: "function", name: "setBeneficiary", stateMutability: "nonpayable", inputs: [{ name: "beneficiary_", type: "address" }], outputs: [] },
  { type: "function", name: "setPaymentAmount", stateMutability: "nonpayable", inputs: [{ name: "amount_", type: "uint256" }], outputs: [] },
  { type: "function", name: "setInterval", stateMutability: "nonpayable", inputs: [{ name: "intervalSeconds_", type: "uint256" }], outputs: [] },
] as const;

const CALLBACK_ABI = [
  { type: "function", name: "paymentsExecuted", stateMutability: "view", inputs: [], outputs: [{ type: "uint256" }] },
  { type: "function", name: "totalPaid", stateMutability: "view", inputs: [], outputs: [{ type: "uint256" }] },
  { type: "function", name: "beneficiary", stateMutability: "view", inputs: [], outputs: [{ type: "address" }] },
] as const;

const DEPOSIT_ABI = [
  { type: "function", name: "depositTo", stateMutability: "payable", inputs: [{ name: "contract_", type: "address" }], outputs: [] },
] as const;

const lasna = createPublicClient({ transport: http(LASNA_RPC) });
const baseSepoliaClient = createPublicClient({ transport: http(BASE_SEPOLIA_RPC) });

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

  const [
    rscBalance,
    rscDebt,
    rscReserves,
    payments,
    nextAt,
    cbBalance,
    executed,
    total,
    beneficiary,
    amount,
    interval,
    active,
  ] = await Promise.all([
    lasna.getBalance({ address: rsc }),
    lasna.readContract({ address: rsc, abi: RSC_ABI, functionName: "debt" }),
    lasna.readContract({ address: rsc, abi: RSC_ABI, functionName: "reserves" }),
    lasna.readContract({ address: rsc, abi: RSC_ABI, functionName: "paymentsRequested" }),
    lasna.readContract({ address: rsc, abi: RSC_ABI, functionName: "nextPaymentAt" }),
    baseSepoliaClient.getBalance({ address: cb }),
    baseSepoliaClient.readContract({ address: cb, abi: CALLBACK_ABI, functionName: "paymentsExecuted" }),
    baseSepoliaClient.readContract({ address: cb, abi: CALLBACK_ABI, functionName: "totalPaid" }),
    lasna.readContract({ address: rsc, abi: RSC_ABI, functionName: "beneficiary" }),
    lasna.readContract({ address: rsc, abi: RSC_ABI, functionName: "paymentAmount" }),
    lasna.readContract({ address: rsc, abi: RSC_ABI, functionName: "intervalSeconds" }),
    lasna.readContract({ address: rsc, abi: RSC_ABI, functionName: "active" }),
  ]);

  setText("rsc-balance", `${formatEther(rscBalance)} lREACT`);
  setText("rsc-debt", `${formatEther(rscDebt)} lREACT`);
  setText("rsc-reserves", `${formatEther(rscReserves)} lREACT`);
  setText("rsc-payments", payments.toString());
  setText(
    "rsc-next",
    nextAt === 0n
      ? "—"
      : `${new Date(Number(nextAt) * 1000).toLocaleString()}${active ? "" : " (paused)"}`,
  );
  setText("cb-balance", `${formatEther(cbBalance)} ETH`);
  setText("cb-payments", executed.toString());
  setText("cb-total", `${formatEther(total)} ETH`);

  // Pre-fill the config form with the live on-chain schedule.
  ($("beneficiary") as HTMLInputElement).value = beneficiary;
  ($("amount") as HTMLInputElement).value = formatEther(amount);
  const intervalSelect = $("interval") as HTMLSelectElement;
  const intervalStr = interval.toString();
  if ([...intervalSelect.options].some((o) => o.value === intervalStr)) {
    intervalSelect.value = intervalStr;
  }
}

type Wallet = ReturnType<typeof createWalletClient>;

function getInjectedProvider() {
  const eth = (window as unknown as { ethereum?: unknown }).ethereum;
  if (!eth) {
    alert("No injected wallet found (MetaMask etc.).");
    return null;
  }
  return eth;
}

async function getWallet(
  chain: typeof lasnaChain | typeof baseSepolia,
): Promise<{ wallet: Wallet; account: `0x${string}` } | null> {
  const eth = getInjectedProvider();
  if (!eth) return null;
  const wallet = createWalletClient({ chain, transport: custom(eth as never) });
  const [account] = await wallet.getAddresses();
  if (!account) {
    alert("No account found in the connected wallet.");
    return null;
  }
  try {
    await wallet.switchChain({ id: chain.id });
  } catch {
    alert(
      `Please switch your wallet to ${chain.name} (chain ${chain.id}) and try again.`,
    );
    return null;
  }
  setText("wallet-status", `Connected: ${account}`);
  return { wallet, account };
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
    const eth = getInjectedProvider();
    if (!eth) return;
    const wallet = createWalletClient({ transport: custom(eth as never) });
    const [account] = await wallet.getAddresses();
    if (!account) {
      alert("No account found in the connected wallet.");
      return;
    }
    setText("wallet-status", `Connected: ${account}`);
    console.log("Connected account:", account);
  });

  // Save schedule: owner-only writes on the RSC (Lasna). Only fields that
  // differ from the on-chain values are sent, one transaction each.
  $("config-form").addEventListener("submit", async (e) => {
    e.preventDefault();
    if (!DEPLOYED) return;
    const beneficiary = ($("beneficiary") as HTMLInputElement).value as `0x${string}`;
    const amount = parseEther(($("amount") as HTMLInputElement).value || "0");
    const interval = BigInt(Number(($("interval") as HTMLSelectElement).value));
    const rsc = RSC_ADDRESS as `0x${string}`;

    const got = await getWallet(lasnaChain);
    if (!got) return;
    const { wallet, account } = got;

    try {
      const [currentBeneficiary, currentAmount, currentInterval] = await Promise.all([
        lasna.readContract({ address: rsc, abi: RSC_ABI, functionName: "beneficiary" }),
        lasna.readContract({ address: rsc, abi: RSC_ABI, functionName: "paymentAmount" }),
        lasna.readContract({ address: rsc, abi: RSC_ABI, functionName: "intervalSeconds" }),
      ]);
      const txs: `0x${string}`[] = [];
      if (beneficiary.toLowerCase() !== currentBeneficiary.toLowerCase()) {
        txs.push(
          await wallet.writeContract({
            address: rsc,
            abi: RSC_ABI,
            functionName: "setBeneficiary",
            args: [beneficiary],
            account,
            chain: lasnaChain,
          }),
        );
      }
      if (amount !== currentAmount) {
        txs.push(
          await wallet.writeContract({
            address: rsc,
            abi: RSC_ABI,
            functionName: "setPaymentAmount",
            args: [amount],
            account,
            chain: lasnaChain,
          }),
        );
      }
      if (interval !== currentInterval) {
        txs.push(
          await wallet.writeContract({
            address: rsc,
            abi: RSC_ABI,
            functionName: "setInterval",
            args: [interval],
            account,
            chain: lasnaChain,
          }),
        );
      }
      if (txs.length === 0) {
        alert("Schedule is already set to these values — nothing to change.");
        return;
      }
      alert(`Schedule update sent (${txs.length} transaction${txs.length > 1 ? "s" : ""}):\n${txs.join("\n")}`);
      await refreshStatus();
    } catch (err) {
      console.error(err);
      alert(`Save failed: ${err instanceof Error ? err.message : err}`);
    }
  });

  // Fund the RSC with lREACT via depositTo() on the Lasna system contract.
  $("fund-rsc-btn").addEventListener("click", async () => {
    if (!DEPLOYED) return;
    const input = window.prompt("Amount of lREACT to deposit to the RSC:", "1");
    if (input === null) return;
    const value = parseEther(input);
    if (value <= 0n) {
      alert("Amount must be greater than 0.");
      return;
    }
    const got = await getWallet(lasnaChain);
    if (!got) return;
    const { wallet, account } = got;
    try {
      const hash = await wallet.writeContract({
        address: SYSTEM_CONTRACT,
        abi: DEPOSIT_ABI,
        functionName: "depositTo",
        args: [RSC_ADDRESS as `0x${string}`],
        value,
        account,
        chain: lasnaChain,
      });
      alert(`Fund RSC sent: ${hash}`);
      await refreshStatus();
    } catch (err) {
      console.error(err);
      alert(`Funding failed: ${err instanceof Error ? err.message : err}`);
    }
  });

  // Fund the callback with ETH via depositTo() on the Base Sepolia proxy.
  $("fund-cb-btn").addEventListener("click", async () => {
    if (!DEPLOYED) return;
    const input = window.prompt("Amount of ETH to deposit to the callback:", "0.05");
    if (input === null) return;
    const value = parseEther(input);
    if (value <= 0n) {
      alert("Amount must be greater than 0.");
      return;
    }
    const got = await getWallet(baseSepolia);
    if (!got) return;
    const { wallet, account } = got;
    try {
      const hash = await wallet.writeContract({
        address: BASE_SEPOLIA_PROXY,
        abi: DEPOSIT_ABI,
        functionName: "depositTo",
        args: [CALLBACK_ADDRESS as `0x${string}`],
        value,
        account,
        chain: baseSepolia,
      });
      alert(`Fund callback sent: ${hash}`);
      await refreshStatus();
    } catch (err) {
      console.error(err);
      alert(`Funding failed: ${err instanceof Error ? err.message : err}`);
    }
  });

  refreshStatus().catch(console.error);
}

wireUp();
