// SPDX-License-Identifier: MIT
pragma solidity ^0.8.29;

import { ISystemContract } from "@reactive/src/interfaces/ISystemContract.sol";
import { IReactive } from "@reactive/src/interfaces/IReactive.sol";
import { AbstractReactive } from "@reactive/src/base/AbstractReactive.sol";

/// @title RecurringPaymentReactive
/// @notice Reactive Smart Contract (Omni model) for Track B — "Set It and
/// Forget It" (Reactive Omni Buildathon).
///
/// The user configures a recurring payment once (beneficiary, fixed amount,
/// interval). After that the RSC runs it by itself, with no off-chain bot:
/// it subscribes to CRON ticks emitted by the legacy system contract and,
/// whenever a payment is due, asks the system contract to deliver a
/// callback to the payment contract on the destination chain.
///
/// Optionally it also watches ERC-20 top-ups to the payment contract: a
/// Transfer of at least `topUpThreshold` to the callback contract triggers
/// one immediate bonus payment and restarts the schedule.
///
/// Design notes (from the Reactive docs, dev.reactive.network):
/// - Omni model only: SYSTEM is 0x8888...8888, `react()` is guarded by
///   `onlySystem`, callbacks go through `requestCallbackV_1_0`.
/// - The first payload argument must be an `address` placeholder
///   (address(0)); the callback proxy overwrites it with this contract's
///   address so the destination can authenticate the sender.
/// - `react()` never reverts on unmatched logs: a reverting `react()` is
///   still billed, so non-matching logs simply fall through.
/// - Deployment order: deploy this RSC first, then the callback contract
///   with this address, then call `setCallback()` here.
contract RecurringPaymentReactive is AbstractReactive {
    /// @notice The legacy system contract emits the Cron events.
    address internal constant LEGACY_SYSTEM_ADDR = 0x0000000000000000000000000000000000fffFfF;

    /// @notice ERC-20 Transfer event signature.
    uint256 public constant TRANSFER_TOPIC_0 = uint256(keccak256("Transfer(address,address,uint256)"));

    /// @notice Cron topic hashes (protocol values, from the docs).
    uint256 public constant CRON_100_TOPIC_0 = 0xb49937fb8970e19fd46d48f7e3fb00d659deac0347f79cd7cb542f0fc1503c70; // ~2 min
    uint256 public constant CRON_1000_TOPIC_0 = 0xe20b31294d84c3661ddc8f423abb9c70310d0cf172aa2714ead78029b325e3f4; // ~17 min
    uint256 public constant CRON_10000_TOPIC_0 = 0xd214e1d84db704ed42d37f538ea9bf71e44ba28bc1cc088b2f5deca654677a56; // ~3 h

    /// @notice Gas forwarded to the callback on the destination chain.
    /// Must stay above the 100_000 minimum enforced by the network.
    uint64 private constant CALLBACK_GAS_LIMIT = 1_000_000;

    address public owner;
    address public callback; // RecurringPaymentCallback on the destination chain
    uint256 public destinationChainId;
    address public beneficiary;
    uint256 public paymentAmount; // wei of the destination chain's native currency, per payment
    uint256 public intervalSeconds; // seconds between scheduled payments
    uint256 public cronTopic; // which Cron interval this RSC listens to
    uint256 public lastPaymentAt;
    uint256 public nextPaymentAt;
    uint256 public paymentsRequested;
    bool public active;

    // --- Optional top-up watch ---
    address public watchedToken; // ERC-20 on the destination chain (address(0) = disabled)
    uint256 public topUpThreshold; // a Transfer >= this triggers a bonus payment
    uint256 public lastTopUpAt;
    uint256 public lastTopUpAmount;

    event PaymentRequested(uint256 indexed paymentId, uint256 amount, uint256 at);
    event TopUpDetected(address indexed token, address indexed from, uint256 amount);
    event ConfigUpdated(string what);
    event CallbackSet(address indexed callback);
    event Paused();
    event Resumed();

    error OnlyOwner();

    modifier onlyOwner() {
        if (msg.sender != owner) revert OnlyOwner();
        _;
    }

    constructor(
        uint256 destinationChainId_,
        address beneficiary_,
        uint256 paymentAmount_,
        uint256 intervalSeconds_,
        uint256 cronTopic_
    ) payable {
        owner = msg.sender;
        destinationChainId = destinationChainId_;
        beneficiary = beneficiary_;
        paymentAmount = paymentAmount_;
        intervalSeconds = intervalSeconds_;
        cronTopic = cronTopic_;
        lastPaymentAt = block.timestamp;
        nextPaymentAt = block.timestamp + intervalSeconds_;
        active = true;

        SYSTEM.subscribe(
            block.chainid,
            LEGACY_SYSTEM_ADDR,
            cronTopic_,
            REACTIVE_IGNORE,
            REACTIVE_IGNORE,
            REACTIVE_IGNORE
        );
    }

    /// @notice Point the RSC at the deployed callback contract. Called after
    /// the callback is deployed with this contract's address. Also
    /// (re)subscribes the top-up watch if one is configured.
    function setCallback(address callback_) external onlyOwner {
        callback = callback_;
        emit CallbackSet(callback_);
        _subscribeTopUp();
    }

    function setBeneficiary(address beneficiary_) external onlyOwner {
        beneficiary = beneficiary_;
        emit ConfigUpdated("beneficiary");
    }

    function setPaymentAmount(uint256 amount_) external onlyOwner {
        paymentAmount = amount_;
        emit ConfigUpdated("paymentAmount");
    }

    function setInterval(uint256 intervalSeconds_) external onlyOwner {
        intervalSeconds = intervalSeconds_;
        nextPaymentAt = block.timestamp + intervalSeconds_;
        emit ConfigUpdated("interval");
    }

    /// @notice Configure the optional top-up watch: Transfer events of
    /// `token_` on the destination chain where the recipient is the callback
    /// contract. Pass address(0) to disable.
    function setTopUpWatch(address token_, uint256 threshold_) external onlyOwner {
        if (watchedToken != address(0) && callback != address(0)) {
            SYSTEM.unsubscribe(
                destinationChainId,
                watchedToken,
                TRANSFER_TOPIC_0,
                REACTIVE_IGNORE,
                uint256(uint160(callback)),
                REACTIVE_IGNORE
            );
        }
        watchedToken = token_;
        topUpThreshold = threshold_;
        _subscribeTopUp();
        emit ConfigUpdated("topUpWatch");
    }

    function _subscribeTopUp() internal {
        if (watchedToken != address(0) && callback != address(0)) {
            SYSTEM.subscribe(
                destinationChainId,
                watchedToken,
                TRANSFER_TOPIC_0,
                REACTIVE_IGNORE,
                uint256(uint160(callback)),
                REACTIVE_IGNORE
            );
        }
    }

    /// @notice Pause scheduled payments (unsubscribes from CRON ticks).
    function pause() external onlyOwner {
        if (!active) return;
        active = false;
        SYSTEM.unsubscribe(
            block.chainid,
            LEGACY_SYSTEM_ADDR,
            cronTopic,
            REACTIVE_IGNORE,
            REACTIVE_IGNORE,
            REACTIVE_IGNORE
        );
        emit Paused();
    }

    /// @notice Resume scheduled payments. Settles any debt first, because a
    /// contract in debt receives no reactive transactions.
    function resume() external onlyOwner {
        if (active) return;
        _coverDebt();
        active = true;
        SYSTEM.subscribe(
            block.chainid,
            LEGACY_SYSTEM_ADDR,
            cronTopic,
            REACTIVE_IGNORE,
            REACTIVE_IGNORE,
            REACTIVE_IGNORE
        );
        emit Resumed();
    }

    /// @notice Settle outstanding debt from this contract's balance. Public
    /// so anyone can revive the contract by funding it and calling this.
    function coverDebt() external {
        _coverDebt();
    }

    /// @notice Trigger one payment right now (owner only). Useful for the
    /// demo: no need to wait for the next CRON tick. Resets the schedule.
    function triggerPaymentNow() external onlyOwner {
        require(active, "Paused");
        require(callback != address(0), "No callback set");
        lastPaymentAt = block.timestamp;
        nextPaymentAt = block.timestamp + intervalSeconds;
        _requestPayment(paymentAmount);
    }

    // --- Status reads for the frontend ---
    function debt() external view returns (uint256) {
        return SYSTEM.debt(address(this));
    }

    function reserves() external view returns (uint256) {
        return ISystemReserves(address(SYSTEM)).reserves(address(this));
    }

    /// @inheritdoc IReactive
    function react(LogRecord memory log_) external onlySystem {
        // Route on topic0; anything else falls through silently (never revert:
        // a reverting react() is still billed in full).
        if (log_.topic0 == cronTopic && log_.chainId == block.chainid) {
            _onCronTick();
        } else if (
            log_.topic0 == TRANSFER_TOPIC_0 &&
            watchedToken != address(0) &&
            log_.chainId == destinationChainId &&
            log_.contractAddress == watchedToken &&
            log_.topic2 == uint256(uint160(callback))
        ) {
            _onTopUp(log_);
        }
    }

    function _onCronTick() internal {
        if (!active || callback == address(0)) return;
        if (block.timestamp < nextPaymentAt) return;
        lastPaymentAt = block.timestamp;
        nextPaymentAt = block.timestamp + intervalSeconds;
        _requestPayment(paymentAmount);
    }

    function _onTopUp(LogRecord memory log_) internal {
        uint256 amount = abi.decode(log_.data, (uint256));
        lastTopUpAt = block.timestamp;
        lastTopUpAmount = amount;
        emit TopUpDetected(log_.contractAddress, address(uint160(log_.topic1)), amount);
        // A top-up at or above the threshold triggers one immediate bonus
        // payment (same fixed amount) and restarts the schedule.
        if (active && callback != address(0) && topUpThreshold > 0 && amount >= topUpThreshold) {
            lastPaymentAt = block.timestamp;
            nextPaymentAt = block.timestamp + intervalSeconds;
            _requestPayment(paymentAmount);
        }
    }

    function _requestPayment(uint256 amount_) internal {
        paymentsRequested++;
        // First payload arg is an address placeholder: the callback proxy
        // overwrites its first 160 bits with this contract's address.
        bytes memory payload = abi.encodeWithSignature(
            "executePayment(address,uint256)",
            address(0),
            amount_
        );
        SYSTEM.requestCallbackV_1_0(
            ISystemContract.CallbackConfiguration_V_1_0({
                chainId: destinationChainId,
                recipient: callback,
                gasLimit: CALLBACK_GAS_LIMIT,
                payload: payload
            })
        );
        emit PaymentRequested(paymentsRequested, amount_, block.timestamp);
    }
}

/// @notice Minimal view into the system contract's reserves mapping.
/// `reserves(address)` is not part of IPayable, so it is declared here.
interface ISystemReserves {
    function reserves(address contract_) external view returns (uint256);
}
