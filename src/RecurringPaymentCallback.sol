// SPDX-License-Identifier: MIT
pragma solidity ^0.8.29;

import { IPayable } from "@reactive/src/interfaces/IPayable.sol";
import { AbstractCallback } from "@reactive/src/base/AbstractCallback.sol";

/// @title RecurringPaymentCallback
/// @notice Lives on the destination chain (Base Sepolia for this entry).
/// Receives callbacks from RecurringPaymentReactive and pays a fixed amount
/// of the destination chain's native currency to the beneficiary.
///
/// Security (from the Reactive docs):
/// - `onlyServiceProvider` proves the call came through the callback proxy.
/// - `onlyCallbackSender(reactive_)` proves it originated from the reactive
///   contract this contract trusts. Both are always used together.
/// - The first payload argument is overwritten by the proxy with the
///   reactive contract's address, so it is the authenticated sender.
/// - The contract is funded in advance (destination native currency, NOT
///   REACT) and pays callback execution fees to the proxy from its balance.
///
/// Deployment order: deploy the RSC first, then this contract with the RSC
/// address as `callbackSender_`, then call `setCallback()` on the RSC.
contract RecurringPaymentCallback is AbstractCallback {
    address public owner;
    address public beneficiary;
    uint256 public paymentsExecuted;
    uint256 public totalPaid;

    event PaymentExecuted(
        address indexed reactive,
        address indexed beneficiary,
        uint256 amount,
        uint256 indexed paymentNumber
    );
    event BeneficiaryUpdated(address indexed beneficiary);
    event Funded(address indexed from, uint256 amount);

    error OnlyOwner();

    modifier onlyOwner() {
        if (msg.sender != owner) revert OnlyOwner();
        _;
    }

    constructor(
        IPayable callbackProxy_,
        address callbackSender_,
        address beneficiary_
    ) payable AbstractCallback(callbackProxy_, callbackSender_) {
        owner = msg.sender;
        beneficiary = beneficiary_;
    }

    receive() external payable override {
        emit Funded(msg.sender, msg.value);
    }

    function setBeneficiary(address beneficiary_) external onlyOwner {
        beneficiary = beneficiary_;
        emit BeneficiaryUpdated(beneficiary_);
    }

    /// @notice Called by the Reactive callback proxy on behalf of the RSC.
    /// @param reactive_ Injected by the proxy: the reactive contract that
    /// requested this callback (authenticated via onlyCallbackSender).
    /// @param amount_ Fixed payment amount, in wei of this chain's native
    /// currency, decided by the RSC.
    function executePayment(address reactive_, uint256 amount_)
        external
        onlyServiceProvider
        onlyCallbackSender(reactive_)
    {
        require(amount_ > 0, "Zero amount");
        require(beneficiary != address(0), "No beneficiary");
        require(address(this).balance >= amount_, "Insufficient funds");
        paymentsExecuted++;
        totalPaid += amount_;
        (bool ok, ) = payable(beneficiary).call{ value: amount_ }("");
        require(ok, "Transfer failed");
        emit PaymentExecuted(reactive_, beneficiary, amount_, paymentsExecuted);
    }

    /// @notice Settle outstanding debt from this contract's balance.
    function coverDebt() external {
        _coverDebt();
    }

    function debt() external view returns (uint256) {
        return _SERVICE_PROVIDER.debt(address(this));
    }
}
