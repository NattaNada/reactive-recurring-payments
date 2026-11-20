// SPDX-License-Identifier: MIT
pragma solidity ^0.8.29;

import { Test } from "forge-std/Test.sol";
import { IReactive } from "@reactive/src/interfaces/IReactive.sol";
import { IPayable } from "@reactive/src/interfaces/IPayable.sol";
import { AbstractPayer } from "@reactive/src/base/AbstractPayer.sol";
import { RecurringPaymentReactive } from "../src/RecurringPaymentReactive.sol";

/// @notice Tests for the RSC. The real system contract (0x8888...8888) has
/// no code in the test environment, so calls to it succeed silently — the
/// tests assert on the RSC's own state and events instead. `debt()` reads
/// are mocked where needed.
contract RecurringPaymentReactiveTest is Test {
    address internal constant SYSTEM = 0x8888888888888888888888888888888888888888;
    address internal constant LEGACY_SYSTEM = 0x0000000000000000000000000000000000fffFfF;

    uint256 internal constant BASE_SEPOLIA = 84532;
    uint256 internal constant CRON_1000 =
        0xe20b31294d84c3661ddc8f423abb9c70310d0cf172aa2714ead78029b325e3f4;

    address internal owner = makeAddr("owner");
    address internal beneficiary = makeAddr("beneficiary");
    address internal callback = makeAddr("callback");
    address internal token = makeAddr("token");
    address internal topper = makeAddr("topper");

    uint256 internal constant PAYMENT = 0.01 ether;
    uint256 internal constant INTERVAL = 600; // 10 min (demo)

    RecurringPaymentReactive internal rsc;

    event PaymentRequested(uint256 indexed paymentId, uint256 amount, uint256 at);
    event TopUpDetected(address indexed token, address indexed from, uint256 amount);

    function setUp() public {
        // SYSTEM.debt() is called by _coverDebt(); mock it to 0 so
        // pause/resume flows work in the test env (selector-only mock
        // matches any debt(address) call).
        vm.mockCall(
            SYSTEM,
            abi.encodeWithSelector(IPayable.debt.selector),
            abi.encode(uint256(0))
        );
        vm.prank(owner);
        rsc = new RecurringPaymentReactive(
            BASE_SEPOLIA,
            beneficiary,
            PAYMENT,
            INTERVAL,
            CRON_1000
        );
    }

    function _cronLog() internal view returns (IReactive.LogRecord memory) {
        return
            IReactive.LogRecord({
                chainId: block.chainid,
                contractAddress: LEGACY_SYSTEM,
                topic0: CRON_1000,
                topic1: 0,
                topic2: 0,
                topic3: 0,
                data: abi.encode(block.number),
                blockNumber: block.number,
                opCode: 1,
                blockHash: 0,
                txHash: 0,
                logIndex: 0
            });
    }

    function _transferLog(uint256 amount_) internal view returns (IReactive.LogRecord memory) {
        return
            IReactive.LogRecord({
                chainId: BASE_SEPOLIA,
                contractAddress: token,
                topic0: rsc.TRANSFER_TOPIC_0(),
                topic1: uint256(uint160(topper)),
                topic2: uint256(uint160(callback)),
                topic3: 0,
                data: abi.encode(amount_),
                blockNumber: block.number,
                opCode: 3,
                blockHash: 0,
                txHash: 0,
                logIndex: 0
            });
    }

    function testConstructorSetsSchedule() public view {
        assertEq(rsc.owner(), owner);
        assertEq(rsc.destinationChainId(), BASE_SEPOLIA);
        assertEq(rsc.beneficiary(), beneficiary);
        assertEq(rsc.paymentAmount(), PAYMENT);
        assertEq(rsc.intervalSeconds(), INTERVAL);
        assertEq(rsc.cronTopic(), CRON_1000);
        assertTrue(rsc.active());
        assertEq(rsc.nextPaymentAt(), block.timestamp + INTERVAL);
    }

    function testCronTickBeforeDueDoesNothing() public {
        vm.prank(SYSTEM);
        rsc.react(_cronLog());
        assertEq(rsc.paymentsRequested(), 0);
    }

    function testCronTickWhenDueRequestsPayment() public {
        vm.prank(owner);
        rsc.setCallback(callback);
        vm.warp(block.timestamp + INTERVAL + 1);

        vm.expectEmit(true, false, false, true, address(rsc));
        emit PaymentRequested(1, PAYMENT, block.timestamp);

        vm.prank(SYSTEM);
        rsc.react(_cronLog());

        assertEq(rsc.paymentsRequested(), 1);
        assertEq(rsc.lastPaymentAt(), block.timestamp);
        assertEq(rsc.nextPaymentAt(), block.timestamp + INTERVAL);
    }

    function testCronTickWithoutCallbackDoesNothing() public {
        vm.warp(block.timestamp + INTERVAL + 1);
        vm.prank(SYSTEM);
        rsc.react(_cronLog());
        assertEq(rsc.paymentsRequested(), 0);
    }

    function testReactIgnoresUnrelatedLogs() public {
        IReactive.LogRecord memory log = _cronLog();
        log.topic0 = uint256(keccak256("SomethingElse()"));
        vm.warp(block.timestamp + INTERVAL + 1);
        vm.prank(owner);
        rsc.setCallback(callback);
        vm.prank(SYSTEM);
        rsc.react(log);
        assertEq(rsc.paymentsRequested(), 0);
    }

    function testReactFromNonSystemReverts() public {
        vm.expectRevert(
            abi.encodeWithSelector(
                AbstractPayer.NotAuthorized.selector,
                address(this),
                SYSTEM
            )
        );
        rsc.react(_cronLog());
    }

    function testTopUpAboveThresholdTriggersBonusPayment() public {
        vm.startPrank(owner);
        rsc.setCallback(callback);
        rsc.setTopUpWatch(token, 1 ether);
        vm.stopPrank();

        vm.expectEmit(true, true, false, true, address(rsc));
        emit TopUpDetected(token, topper, 2 ether);

        IReactive.LogRecord memory log = _transferLog(2 ether);
        vm.prank(SYSTEM);
        rsc.react(log);

        assertEq(rsc.lastTopUpAmount(), 2 ether);
        assertEq(rsc.paymentsRequested(), 1); // bonus payment requested
    }

    function testTopUpBelowThresholdOnlyRecords() public {
        vm.startPrank(owner);
        rsc.setCallback(callback);
        rsc.setTopUpWatch(token, 1 ether);
        vm.stopPrank();

        IReactive.LogRecord memory log = _transferLog(0.5 ether);
        vm.prank(SYSTEM);
        rsc.react(log);

        assertEq(rsc.lastTopUpAmount(), 0.5 ether);
        assertEq(rsc.paymentsRequested(), 0); // no bonus payment
    }

    function testPauseStopsPaymentsAndResumeRestarts() public {
        vm.prank(owner);
        rsc.setCallback(callback);
        vm.prank(owner);
        rsc.pause();
        assertFalse(rsc.active());

        vm.warp(block.timestamp + INTERVAL + 1);
        vm.prank(SYSTEM);
        rsc.react(_cronLog());
        assertEq(rsc.paymentsRequested(), 0);

        vm.prank(owner);
        rsc.resume();
        assertTrue(rsc.active());

        vm.prank(SYSTEM);
        rsc.react(_cronLog());
        assertEq(rsc.paymentsRequested(), 1);
    }

    function testOnlyOwnerCanChangeConfig() public {
        vm.expectRevert(RecurringPaymentReactive.OnlyOwner.selector);
        rsc.setBeneficiary(makeAddr("attacker"));
        vm.expectRevert(RecurringPaymentReactive.OnlyOwner.selector);
        rsc.setPaymentAmount(1);
        vm.expectRevert(RecurringPaymentReactive.OnlyOwner.selector);
        rsc.pause();
    }

    function testTriggerPaymentNow() public {
        vm.prank(owner);
        rsc.setCallback(callback);
        vm.prank(owner);
        rsc.triggerPaymentNow();
        assertEq(rsc.paymentsRequested(), 1);
    }

    function testTriggerPaymentNowWithoutCallbackReverts() public {
        vm.prank(owner);
        vm.expectRevert("No callback set");
        rsc.triggerPaymentNow();
    }
}
