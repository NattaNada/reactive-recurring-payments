// SPDX-License-Identifier: MIT
pragma solidity ^0.8.29;

import { Test } from "forge-std/Test.sol";
import { IPayable } from "@reactive/src/interfaces/IPayable.sol";
import { AbstractCallback } from "@reactive/src/base/AbstractCallback.sol";
import { AbstractPayer } from "@reactive/src/base/AbstractPayer.sol";
import { RecurringPaymentCallback } from "../src/RecurringPaymentCallback.sol";

/// @notice Tests for the callback contract. The callback proxy is mocked
/// with a plain address: onlyServiceProvider checks msg.sender == proxy.
contract RecurringPaymentCallbackTest is Test {
    address internal proxy = makeAddr("proxy");
    address internal rsc = makeAddr("rsc");
    address internal owner = makeAddr("owner");
    address internal beneficiary = makeAddr("beneficiary");

    RecurringPaymentCallback internal cb;

    event PaymentExecuted(
        address indexed reactive,
        address indexed beneficiary,
        uint256 amount,
        uint256 indexed paymentNumber
    );

    function setUp() public {
        vm.deal(owner, 10 ether);
        vm.prank(owner);
        cb = new RecurringPaymentCallback{ value: 1 ether }(
            IPayable(payable(proxy)),
            rsc,
            beneficiary
        );
    }

    function testConstructor() public view {
        assertEq(cb.owner(), owner);
        assertEq(cb.beneficiary(), beneficiary);
        assertEq(cb._CALLBACK_SENDER(), rsc);
        assertEq(address(cb).balance, 1 ether);
    }

    function testExecutePaymentFromProxy() public {
        uint256 before = beneficiary.balance;
        vm.expectEmit(true, true, false, true, address(cb));
        emit PaymentExecuted(rsc, beneficiary, 0.01 ether, 1);

        vm.prank(proxy);
        cb.executePayment(rsc, 0.01 ether);

        assertEq(cb.paymentsExecuted(), 1);
        assertEq(cb.totalPaid(), 0.01 ether);
        assertEq(beneficiary.balance, before + 0.01 ether);
        assertEq(address(cb).balance, 0.99 ether);
    }

    function testExecutePaymentFromWrongReactiveReverts() public {
        vm.prank(proxy);
        vm.expectRevert(
            abi.encodeWithSelector(
                AbstractCallback.CallbackNotAuthorized.selector,
                makeAddr("other"),
                rsc
            )
        );
        cb.executePayment(makeAddr("other"), 0.01 ether);
    }

    function testExecutePaymentDirectCallReverts() public {
        vm.expectRevert(
            abi.encodeWithSelector(
                AbstractPayer.NotAuthorized.selector,
                address(this),
                proxy
            )
        );
        cb.executePayment(rsc, 0.01 ether);
    }

    function testExecutePaymentInsufficientFundsReverts() public {
        vm.prank(proxy);
        vm.expectRevert("Insufficient funds");
        cb.executePayment(rsc, 2 ether);
    }

    function testExecutePaymentZeroAmountReverts() public {
        vm.prank(proxy);
        vm.expectRevert("Zero amount");
        cb.executePayment(rsc, 0);
    }

    function testSetBeneficiaryOnlyOwner() public {
        address next = makeAddr("next");
        vm.prank(owner);
        cb.setBeneficiary(next);
        assertEq(cb.beneficiary(), next);

        vm.expectRevert(RecurringPaymentCallback.OnlyOwner.selector);
        cb.setBeneficiary(makeAddr("attacker"));
    }
}
