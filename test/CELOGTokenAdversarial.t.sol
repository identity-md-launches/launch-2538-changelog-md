// SPDX-License-Identifier: MIT
pragma solidity 0.8.26;

import {CELOGToken} from "src/CELOGToken.sol";
import {CELOGTestBase, CELOGVm} from "./helpers/CELOGTestBase.sol";

/// @notice Edge cases and metamorphic properties supplementing the original unit suite.
/// forge-config: default.fuzz.runs = 1000
contract CELOGTokenAdversarialTest is CELOGTestBase {
    CELOGToken internal token;

    function setUp() public {
        token = new CELOGToken();
        require(token.transfer(ALICE, SUPPLY), "fund holder");
    }

    function test_zeroTransfersFromEmptyAccountsEmitAndNeedNoAllowance() public {
        vm.recordLogs();
        vm.prank(BOB);
        require(token.transfer(CAROL, 0), "zero direct transfer");
        vm.prank(DAVE);
        require(token.transferFrom(BOB, CAROL, 0), "zero delegated transfer");
        CELOGVm.Log[] memory logs = vm.getRecordedLogs();
        assertEq(logs.length, 2, "both zero transfers must emit");
        _assertTransferLog(logs[0], BOB, CAROL, 0);
        _assertTransferLog(logs[1], BOB, CAROL, 0);
        assertEq(token.balanceOf(BOB), 0, "empty sender changed");
        assertEq(token.balanceOf(CAROL), 0, "empty receiver changed");
        assertEq(token.allowance(BOB, DAVE), 0, "zero spend created allowance");
        assertEq(token.totalSupply(), SUPPLY, "zero transfers changed supply");
    }

    function test_oneWeiAndFullSupplyRoundTrips() public {
        _roundTrip(1);
        _roundTrip(SUPPLY);
    }

    function test_fullSupplySelfTransferCannotCreateValue() public {
        vm.prank(ALICE);
        require(token.transfer(ALICE, SUPPLY), "full self transfer");
        assertEq(token.balanceOf(ALICE), SUPPLY, "self transfer changed balance");
        assertEq(token.totalSupply(), SUPPLY, "self transfer changed supply");
    }

    function test_selfTransferStillRequiresEnoughBalance() public {
        _revertsUnchanged(
            ALICE,
            abi.encodeCall(token.transfer, (ALICE, type(uint256).max)),
            abi.encodeWithSelector(CELOGToken.ERC20InsufficientBalance.selector, ALICE, SUPPLY, type(uint256).max)
        );
    }

    function test_ownerCallingTransferFromNeedsSelfApproval() public {
        _revertsUnchanged(
            ALICE,
            abi.encodeCall(token.transferFrom, (ALICE, BOB, 1)),
            abi.encodeWithSelector(CELOGToken.ERC20InsufficientAllowance.selector, ALICE, 0, 1)
        );
        _approve(ALICE, ALICE, 1);
        vm.prank(ALICE);
        require(token.transferFrom(ALICE, BOB, 1), "self-approved spend");
        assertEq(token.allowance(ALICE, ALICE), 0, "self approval not consumed");
        assertEq(token.balanceOf(BOB), 1, "self-approved payment missing");
    }

    function test_delegatedSelfTransferConsumesFiniteAllowanceButNotBalance() public {
        _approve(ALICE, BOB, SUPPLY);
        vm.recordLogs();
        vm.prank(BOB);
        require(token.transferFrom(ALICE, ALICE, SUPPLY), "delegated self transfer");
        assertEq(token.balanceOf(ALICE), SUPPLY, "delegated self transfer changed balance");
        assertEq(token.allowance(ALICE, BOB), 0, "delegated self transfer did not spend approval");
        _assertSingleTransfer(vm.getRecordedLogs(), ALICE, ALICE, SUPPLY);
    }

    function test_maxMinusOneAllowanceIsFinite() public {
        _approve(ALICE, BOB, type(uint256).max - 1);
        vm.prank(BOB);
        require(token.transferFrom(ALICE, CAROL, 1), "near-max finite spend");
        assertEq(token.allowance(ALICE, BOB), type(uint256).max - 2, "only max is infinite");
        assertEq(token.balanceOf(CAROL), 1, "near-max payment");
    }

    function test_infiniteApprovalSurvivesRepeatedSpendsAndCanBeRevoked() public {
        _approve(ALICE, BOB, type(uint256).max);
        vm.prank(BOB);
        require(token.transferFrom(ALICE, CAROL, 1), "first infinite spend");
        vm.prank(BOB);
        require(token.transferFrom(ALICE, ALICE, SUPPLY - 1), "infinite self spend");
        assertEq(token.allowance(ALICE, BOB), type(uint256).max, "infinite allowance decremented");
        _approve(ALICE, BOB, 0);
        _revertsUnchanged(
            BOB,
            abi.encodeCall(token.transferFrom, (ALICE, CAROL, 1)),
            abi.encodeWithSelector(CELOGToken.ERC20InsufficientAllowance.selector, BOB, 0, 1)
        );
    }

    function test_loweringApprovalAfterSpendTakesEffectImmediately() public {
        _approve(ALICE, BOB, 10);
        vm.prank(BOB);
        require(token.transferFrom(ALICE, CAROL, 3), "initial spend");
        _approve(ALICE, BOB, 2);
        _revertsUnchanged(
            BOB,
            abi.encodeCall(token.transferFrom, (ALICE, CAROL, 3)),
            abi.encodeWithSelector(CELOGToken.ERC20InsufficientAllowance.selector, BOB, 2, 3)
        );
        vm.prank(BOB);
        require(token.transferFrom(ALICE, CAROL, 2), "replacement allowance spend");
        assertEq(token.allowance(ALICE, BOB), 0, "replacement allowance exhausted");
        assertEq(token.balanceOf(CAROL), 5, "replacement approval added old allowance");
    }

    function test_approvalDoesNotFollowTokensToAnotherOwner() public {
        _approve(ALICE, BOB, SUPPLY);
        vm.prank(ALICE);
        require(token.transfer(CAROL, SUPPLY), "move to new owner");
        _revertsUnchanged(
            BOB,
            abi.encodeCall(token.transferFrom, (CAROL, DAVE, 1)),
            abi.encodeWithSelector(CELOGToken.ERC20InsufficientAllowance.selector, BOB, 0, 1)
        );
        assertEq(token.allowance(ALICE, BOB), SUPPLY, "direct transfer changed original approval");
    }

    function test_zeroAddressesRejectEvenZeroAmounts() public {
        _revertsUnchanged(
            ALICE,
            abi.encodeCall(token.transfer, (address(0), 0)),
            abi.encodeWithSelector(CELOGToken.ERC20InvalidReceiver.selector, address(0))
        );
        _revertsUnchanged(
            BOB,
            abi.encodeCall(token.transferFrom, (ALICE, address(0), 0)),
            abi.encodeWithSelector(CELOGToken.ERC20InvalidReceiver.selector, address(0))
        );
        _revertsUnchanged(
            ALICE,
            abi.encodeCall(token.approve, (address(0), 0)),
            abi.encodeWithSelector(CELOGToken.ERC20InvalidSpender.selector, address(0))
        );
    }

    function test_maximumTransferFromRevertsWithInfiniteApprovalWithoutChangingIt() public {
        _approve(ALICE, BOB, type(uint256).max);
        _revertsUnchanged(
            BOB,
            abi.encodeCall(token.transferFrom, (ALICE, CAROL, type(uint256).max)),
            abi.encodeWithSelector(CELOGToken.ERC20InsufficientBalance.selector, ALICE, SUPPLY, type(uint256).max)
        );
    }

    function test_finiteAllowanceRollbackAllowsRetryAfterRefill() public {
        _approve(BOB, CAROL, 7);
        _revertsUnchanged(
            CAROL,
            abi.encodeCall(token.transferFrom, (BOB, DAVE, 7)),
            abi.encodeWithSelector(CELOGToken.ERC20InsufficientBalance.selector, BOB, 0, 7)
        );
        vm.prank(ALICE);
        require(token.transfer(BOB, 7), "refill empty owner");
        vm.prank(CAROL);
        require(token.transferFrom(BOB, DAVE, 7), "retry after refill");
        assertEq(token.allowance(BOB, CAROL), 0, "retry did not consume approval");
        assertEq(token.balanceOf(BOB), 0, "retry left owner balance");
        assertEq(token.balanceOf(DAVE), 7, "retry lost value");
    }

    function test_tokenContractCanReceiveWithoutBurningSupply() public {
        vm.prank(ALICE);
        require(token.transfer(address(token), 1), "direct token custody");
        _approve(ALICE, BOB, 2);
        vm.prank(BOB);
        require(token.transferFrom(ALICE, address(token), 2), "delegated token custody");
        assertEq(token.balanceOf(address(token)), 3, "token custody missing");
        assertEq(token.balanceOf(ALICE), SUPPLY - 3, "custody debit wrong");
        assertEq(token.totalSupply(), SUPPLY, "custody burned supply");
    }

    function test_nonzeroEtherRejectedByEmptyCalldataAndKnownFunction() public {
        vm.deal(ALICE, 2);
        bytes32 beforeState = _stateHash();
        vm.prank(ALICE);
        (bool plainAccepted,) = address(token).call{value: 1}("");
        require(!plainAccepted, "plain ETH accepted");
        vm.prank(ALICE);
        (bool functionAccepted,) = address(token).call{value: 1}(abi.encodeCall(token.approve, (BOB, 1)));
        require(!functionAccepted, "payable approve accepted");
        assertEq(ALICE.balance, 2, "reverted ETH left sender");
        assertEq(address(token).balance, 0, "reverted ETH credited token");
        require(_stateHash() == beforeState, "ETH rejection changed token state");
    }

    function testFuzz_transferRoundTripRestoresBothBalances(uint256 amount) public {
        _roundTrip(bound(amount, 0, SUPPLY));
    }

    function testFuzz_splittingTransferEqualsSingleTransfer(uint256 first, uint256 second) public {
        first = bound(first, 0, SUPPLY);
        second = bound(second, 0, SUPPLY - first);
        CELOGToken single = new CELOGToken();
        require(single.transfer(ALICE, SUPPLY), "fund reference deployment");
        vm.prank(ALICE);
        require(single.transfer(BOB, first + second), "single payment");
        vm.prank(ALICE);
        require(token.transfer(BOB, first), "first split");
        vm.prank(ALICE);
        require(token.transfer(BOB, second), "second split");
        assertEq(token.balanceOf(ALICE), single.balanceOf(ALICE), "splitting changed sender debit");
        assertEq(token.balanceOf(BOB), single.balanceOf(BOB), "splitting changed recipient credit");
        assertEq(token.totalSupply(), single.totalSupply(), "splitting changed supply");
    }

    function testFuzz_directAndDelegatedTransfersAgree(uint256 amount, uint256 allowed) public {
        amount = bound(amount, 0, SUPPLY);
        allowed = bound(allowed, amount, type(uint256).max - 1);
        CELOGToken direct = new CELOGToken();
        require(direct.transfer(ALICE, SUPPLY), "fund direct deployment");
        vm.prank(ALICE);
        require(direct.transfer(CAROL, amount), "direct payment");
        _approve(ALICE, BOB, allowed);
        vm.prank(BOB);
        require(token.transferFrom(ALICE, CAROL, amount), "delegated payment");
        assertEq(token.balanceOf(ALICE), direct.balanceOf(ALICE), "different sender debit");
        assertEq(token.balanceOf(CAROL), direct.balanceOf(CAROL), "different recipient credit");
        assertEq(token.balanceOf(BOB), 0, "spender was credited");
        assertEq(token.allowance(ALICE, BOB), allowed - amount, "finite allowance spent incorrectly");
    }

    function testFuzz_delegatedSelfTransferOnlyConsumesAllowance(uint256 amount, uint256 allowed) public {
        amount = bound(amount, 0, SUPPLY);
        allowed = bound(allowed, amount, type(uint256).max - 1);
        _approve(ALICE, BOB, allowed);
        vm.prank(BOB);
        require(token.transferFrom(ALICE, ALICE, amount), "delegated self transfer");
        assertEq(token.balanceOf(ALICE), SUPPLY, "self transfer changed holder balance");
        assertEq(token.balanceOf(BOB), 0, "self transfer credited spender");
        assertEq(token.allowance(ALICE, BOB), allowed - amount, "self spend allowance");
    }

    function testFuzz_spendingInPartsExhaustsFiniteApproval(uint256 first, uint256 second) public {
        first = bound(first, 0, SUPPLY);
        second = bound(second, 0, SUPPLY - first);
        _approve(ALICE, BOB, first + second);
        vm.prank(BOB);
        require(token.transferFrom(ALICE, CAROL, first), "first allowance spend");
        assertEq(token.allowance(ALICE, BOB), second, "first spend accounting");
        vm.prank(BOB);
        require(token.transferFrom(ALICE, DAVE, second), "second allowance spend");
        assertEq(token.allowance(ALICE, BOB), 0, "split allowance not exhausted");
        assertEq(token.balanceOf(CAROL) + token.balanceOf(DAVE), first + second, "split credits");
        _revertsUnchanged(
            BOB,
            abi.encodeCall(token.transferFrom, (ALICE, CAROL, 1)),
            abi.encodeWithSelector(CELOGToken.ERC20InsufficientAllowance.selector, BOB, 0, 1)
        );
    }

    function testFuzz_balanceFailureRollsBackFiniteAllowance(uint256 held, uint256 requested) public {
        held = bound(held, 0, SUPPLY);
        requested = bound(requested, held + 1, type(uint256).max - 1);
        vm.prank(ALICE);
        require(token.transfer(BOB, held), "fund owner");
        _approve(BOB, CAROL, requested);
        _revertsUnchanged(
            CAROL,
            abi.encodeCall(token.transferFrom, (BOB, DAVE, requested)),
            abi.encodeWithSelector(CELOGToken.ERC20InsufficientBalance.selector, BOB, held, requested)
        );
    }

    function testFuzz_invalidReceiverRollsBackAllowance(uint256 amount, bool infinite) public {
        amount = bound(amount, 0, SUPPLY);
        _approve(ALICE, BOB, infinite ? type(uint256).max : amount);
        _revertsUnchanged(
            BOB,
            abi.encodeCall(token.transferFrom, (ALICE, address(0), amount)),
            abi.encodeWithSelector(CELOGToken.ERC20InvalidReceiver.selector, address(0))
        );
    }

    function testFuzz_approvalIsIdempotentAndIsolated(uint256 value) public {
        _approve(ALICE, CAROL, 17);
        _approve(BOB, DAVE, 23);
        _approve(ALICE, BOB, value);
        bytes32 once = _stateHash();
        _approve(ALICE, BOB, value);
        require(_stateHash() == once, "repeating approval changed state");
        assertEq(token.allowance(ALICE, BOB), value, "approval value");
        assertEq(token.allowance(ALICE, CAROL), 17, "another spender's approval changed");
        assertEq(token.allowance(BOB, DAVE), 23, "another owner's approval changed");
        assertEq(token.balanceOf(ALICE), SUPPLY, "approval moved tokens");
    }

    function _roundTrip(uint256 amount) internal {
        _approve(ALICE, CAROL, 123);
        _approve(BOB, DAVE, type(uint256).max);
        bytes32 beforeState = _stateHash();
        vm.prank(ALICE);
        require(token.transfer(BOB, amount), "outbound transfer");
        vm.prank(BOB);
        require(token.transfer(ALICE, amount), "return transfer");
        require(_stateHash() == beforeState, "round trip changed balances or allowances");
    }

    function _approve(address owner, address spender, uint256 value) internal {
        vm.prank(owner);
        require(token.approve(spender, value), "approval returned false");
    }

    function _revertsUnchanged(address caller, bytes memory data, bytes memory expected) internal {
        bytes32 beforeState = _stateHash();
        vm.prank(caller);
        (bool success, bytes memory reason) = address(token).call(data);
        require(!success, "invalid call unexpectedly succeeded");
        assertEq(reason, expected, "wrong custom error or arguments");
        require(_stateHash() == beforeState, "failed call changed balances or allowances");
    }

    function _stateHash() internal view returns (bytes32 state) {
        address[7] memory accounts = [address(this), ALICE, BOB, CAROL, DAVE, address(token), address(0)];
        state = keccak256(abi.encode(token.totalSupply()));
        for (uint256 i; i < accounts.length; ++i) {
            state = keccak256(abi.encode(state, token.balanceOf(accounts[i])));
            for (uint256 j; j < accounts.length; ++j) {
                state = keccak256(abi.encode(state, token.allowance(accounts[i], accounts[j])));
            }
        }
    }

    function _assertSingleTransfer(CELOGVm.Log[] memory logs, address from, address to, uint256 value) internal view {
        uint256 transfers;
        for (uint256 i; i < logs.length; ++i) {
            if (
                logs[i].emitter == address(token) && logs[i].topics[0] == keccak256("Transfer(address,address,uint256)")
            ) {
                _assertTransferLog(logs[i], from, to, value);
                ++transfers;
            }
        }
        assertEq(transfers, 1, "expected one Transfer event");
    }

    function _assertTransferLog(CELOGVm.Log memory entry, address from, address to, uint256 value) internal view {
        require(entry.emitter == address(token), "wrong event emitter");
        assertEq(entry.topics.length, 3, "wrong Transfer topic count");
        require(entry.topics[0] == keccak256("Transfer(address,address,uint256)"), "wrong event signature");
        require(entry.topics[1] == bytes32(uint256(uint160(from))), "wrong event sender");
        require(entry.topics[2] == bytes32(uint256(uint160(to))), "wrong event receiver");
        assertEq(entry.data, abi.encode(value), "wrong event amount");
    }
}
