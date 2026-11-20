// SPDX-License-Identifier: MIT
pragma solidity ^0.8.29;

import { Script, console } from "forge-std/Script.sol";
import { RecurringPaymentReactive } from "../src/RecurringPaymentReactive.sol";
import { RecurringPaymentCallback } from "../src/RecurringPaymentCallback.sol";
import { IPayable } from "@reactive/src/interfaces/IPayable.sol";

/// @notice Deployment order (see README.md):
///   1. Deploy the RSC on Lasna (chain 5318007) — DeployReactive.
///   2. Deploy the callback on Base Sepolia (chain 84532) with the RSC
///      address — DeployCallback.
///   3. Call setCallback() on the RSC with the callback address — SetCallback.
///   4. Fund both contracts (see README.md "Funding").
/// @dev All secrets come ONLY from environment variables. Never hardcode a
/// private key. These scripts are NOT run by the build step — deployment is
/// a separate, manual step that needs the user's go-ahead.
contract DeployReactive is Script {
    // Cron1000 ticks roughly every 17 minutes: long enough to avoid paying
    // for useless ticks, short enough that a due payment is never far away.
    // For a fast demo use CRON_100 (~2 min) via the RSC's cronTopic.
    uint256 internal constant CRON_1000_TOPIC =
        0xe20b31294d84c3661ddc8f423abb9c70310d0cf172aa2714ead78029b325e3f4;
    uint256 internal constant BASE_SEPOLIA_CHAIN_ID = 84532;

    function run() external {
        uint256 deployerKey = vm.envUint("PRIVATE_KEY");
        address beneficiary = vm.envAddress("BENEFICIARY");
        uint256 paymentAmount = vm.envUint("PAYMENT_AMOUNT_WEI");
        uint256 intervalSeconds = vm.envUint("INTERVAL_SECONDS");
        uint256 fundReact = vm.envOr("FUND_REACT_WEI", uint256(0));

        vm.startBroadcast(deployerKey);
        RecurringPaymentReactive rsc = new RecurringPaymentReactive{
            value: fundReact
        }(
            BASE_SEPOLIA_CHAIN_ID,
            beneficiary,
            paymentAmount,
            intervalSeconds,
            CRON_1000_TOPIC
        );
        vm.stopBroadcast();

        console.log("RecurringPaymentReactive deployed at:", address(rsc));
        console.log("Next payment at (unix):", rsc.nextPaymentAt());
    }
}

contract DeployCallback is Script {
    // Base Sepolia callback proxy (dev.reactive.network/origins-and-destinations).
    address internal constant BASE_SEPOLIA_PROXY =
        0x476F44b11F5C942c58f4c8E3d0300E5710743585;

    function run() external {
        uint256 deployerKey = vm.envUint("PRIVATE_KEY");
        address rsc = vm.envAddress("RSC_ADDRESS");
        address beneficiary = vm.envAddress("BENEFICIARY");
        uint256 fundEth = vm.envOr("FUND_ETH_WEI", uint256(0));

        vm.startBroadcast(deployerKey);
        RecurringPaymentCallback cb = new RecurringPaymentCallback{
            value: fundEth
        }(
            IPayable(payable(BASE_SEPOLIA_PROXY)),
            rsc,
            beneficiary
        );
        vm.stopBroadcast();

        console.log("RecurringPaymentCallback deployed at:", address(cb));
    }
}

contract SetCallback is Script {
    function run() external {
        uint256 deployerKey = vm.envUint("PRIVATE_KEY");
        address rsc = vm.envAddress("RSC_ADDRESS");
        address cb = vm.envAddress("CALLBACK_ADDRESS");

        vm.startBroadcast(deployerKey);
        RecurringPaymentReactive(payable(rsc)).setCallback(cb);
        vm.stopBroadcast();

        console.log("RSC callback set to:", cb);
    }
}
