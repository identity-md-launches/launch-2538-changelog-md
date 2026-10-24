// SPDX-License-Identifier: MIT
pragma solidity 0.8.26;

import {CELOGToken} from "src/CELOGToken.sol";
import {CELOGTestBase} from "./helpers/CELOGTestBase.sol";

/// @dev Four spending actors, including the actual deploying contract, plus the token itself as a
/// passive recipient. Only these five addresses can receive tokens, so their sum is exhaustive.
contract CELOGHandler is CELOGTestBase {
    CELOGToken public immutable token;
    address[5] public actors;

    // Independent transaction journal: never set expected balances from balanceOf after an action.
    uint256[5] public received;
    uint256[5] public sent;
    uint256[4][4] public granted;
    uint256[4][4] public spentSinceApproval;
    uint256 public calls;
    uint256 public positiveTransfers;
    uint256 public expectedReverts;

    constructor() {
        token = new CELOGToken();
        actors = [address(this), ALICE, BOB, CAROL, address(token)];
        // A fresh mint is split equally. No deal/storage cheatcodes create token balances.
        for (uint256 i = 1; i < 4; ++i) {
            require(token.transfer(actors[i], SUPPLY / 4), "initial distribution");
        }
        // Seed useful finite and infinite approvals; later actions replace and revoke them.
        for (uint256 i; i < 4; ++i) {
            _approve(i, (i + 1) % 4, SUPPLY / 8);
        }
        _approve(0, 2, type(uint256).max);
    }

    function expectedBalance(uint256 index) public view returns (uint256) {
        uint256 initial = index < 4 ? SUPPLY / 4 : 0;
        return initial + received[index] - sent[index];
    }

    function expectedAllowance(uint256 owner, uint256 spender) public view returns (uint256) {
        uint256 approval = granted[owner][spender];
        return approval == type(uint256).max ? approval : approval - spentSinceApproval[owner][spender];
    }

    function transfer(uint256 fromSeed, uint256 toSeed, uint256 amountSeed) external {
        ++calls;
        uint256 from = fromSeed % 4;
        uint256 to = toSeed % 5;
        uint256 amount = _amount(amountSeed, expectedBalance(from));
        vm.prank(actors[from]);
        require(token.transfer(actors[to], amount), "valid transfer returned false");
        _recordTransfer(from, to, amount);
    }

    function approve(uint256 ownerSeed, uint256 spenderSeed, uint256 value, uint8 mode) external {
        ++calls;
        // Exercise explicit revocation, the infinite sentinel, its finite neighbor and full-width values.
        if (mode % 5 == 0) value = 0;
        else if (mode % 5 == 1) value = type(uint256).max;
        else if (mode % 5 == 2) value = type(uint256).max - 1;
        else if (mode % 5 == 3) value = bound(value, 0, SUPPLY);
        _approve(ownerSeed % 4, spenderSeed % 4, value);
    }

    function transferFrom(uint256 ownerSeed, uint256 spenderSeed, uint256 toSeed, uint256 amountSeed) external {
        ++calls;
        uint256 owner = ownerSeed % 4;
        uint256 spender = spenderSeed % 4;
        uint256 to = toSeed % 5;
        uint256 limit = expectedBalance(owner);
        uint256 allowed = expectedAllowance(owner, spender);
        if (allowed < limit) limit = allowed;
        uint256 amount = _amount(amountSeed, limit);
        vm.prank(actors[spender]);
        require(token.transferFrom(actors[owner], actors[to], amount), "valid delegated transfer returned false");
        spentSinceApproval[owner][spender] += amount;
        _recordTransfer(owner, to, amount);
    }

    function rejectTransferAboveBalance(uint256 fromSeed, uint256 toSeed, uint256 amountSeed) external {
        ++calls;
        uint256 from = fromSeed % 4;
        uint256 held = expectedBalance(from);
        uint256 amount = bound(amountSeed, held + 1, type(uint256).max);
        _expectFailure(
            actors[from],
            abi.encodeCall(token.transfer, (actors[toSeed % 5], amount)),
            abi.encodeWithSelector(CELOGToken.ERC20InsufficientBalance.selector, actors[from], held, amount)
        );
    }

    function rejectSpendAboveAllowance(uint256 ownerSeed, uint256 spenderSeed, uint256 allowanceSeed) external {
        ++calls;
        uint256 owner = ownerSeed % 4;
        uint256 spender = spenderSeed % 4;
        uint256 allowed = bound(allowanceSeed, 0, SUPPLY);
        _approve(owner, spender, allowed);
        _expectFailure(
            actors[spender],
            abi.encodeCall(token.transferFrom, (actors[owner], actors[(owner + 1) % 4], allowed + 1)),
            abi.encodeWithSelector(
                CELOGToken.ERC20InsufficientAllowance.selector, actors[spender], allowed, allowed + 1
            )
        );
    }

    function rejectSpendAboveBalance(uint256 ownerSeed, uint256 spenderSeed, bool infinite) external {
        ++calls;
        uint256 owner = ownerSeed % 4;
        uint256 spender = spenderSeed % 4;
        uint256 held = expectedBalance(owner);
        uint256 amount = held + 1;
        _approve(owner, spender, infinite ? type(uint256).max : amount);
        _expectFailure(
            actors[spender],
            abi.encodeCall(token.transferFrom, (actors[owner], actors[(owner + 1) % 4], amount)),
            abi.encodeWithSelector(CELOGToken.ERC20InsufficientBalance.selector, actors[owner], held, amount)
        );
        // The invariant compares against the unspent approval, including the finite case where
        // transferFrom tentatively subtracts allowance before discovering insufficient balance.
    }

    function rejectZeroReceiver(uint256 ownerSeed, uint256 spenderSeed, uint256 amountSeed, bool delegated) external {
        ++calls;
        uint256 owner = ownerSeed % 4;
        uint256 spender = spenderSeed % 4;
        uint256 limit = expectedBalance(owner);
        if (delegated && expectedAllowance(owner, spender) < limit) limit = expectedAllowance(owner, spender);
        uint256 amount = _amount(amountSeed, limit);
        bytes memory data = delegated
            ? abi.encodeCall(token.transferFrom, (actors[owner], address(0), amount))
            : abi.encodeCall(token.transfer, (address(0), amount));
        _expectFailure(
            actors[delegated ? spender : owner],
            data,
            abi.encodeWithSelector(CELOGToken.ERC20InvalidReceiver.selector, address(0))
        );
    }

    function rejectZeroSpender(uint256 ownerSeed, uint256 amount) external {
        ++calls;
        _expectFailure(
            actors[ownerSeed % 4],
            abi.encodeCall(token.approve, (address(0), amount)),
            abi.encodeWithSelector(CELOGToken.ERC20InvalidSpender.selector, address(0))
        );
    }

    function roundTrip(uint256 fromSeed, uint256 toSeed, uint256 amountSeed) external {
        ++calls;
        uint256 from = fromSeed % 4;
        uint256 to = toSeed % 4;
        uint256 amount = _amount(amountSeed, expectedBalance(from));
        vm.prank(actors[from]);
        require(token.transfer(actors[to], amount), "round trip out");
        vm.prank(actors[to]);
        require(token.transfer(actors[from], amount), "round trip back");
        // A completed round trip must restore the entire ledger and all approvals. Leave the
        // journal unchanged so the next invariant check compares against the state before it.
        if (amount > 0) positiveTransfers += 2;
    }

    function _approve(uint256 owner, uint256 spender, uint256 value) internal {
        vm.prank(actors[owner]);
        require(token.approve(actors[spender], value), "valid approval returned false");
        granted[owner][spender] = value;
        spentSinceApproval[owner][spender] = 0;
    }

    function _recordTransfer(uint256 from, uint256 to, uint256 amount) internal {
        // Recording both sides naturally handles from == to without copying the token's update order.
        sent[from] += amount;
        received[to] += amount;
        if (amount > 0) ++positiveTransfers;
    }

    function _expectFailure(address caller, bytes memory data, bytes memory expected) internal {
        vm.prank(caller);
        (bool success, bytes memory reason) = address(token).call(data);
        require(!success, "invalid action unexpectedly succeeded");
        assertEq(reason, expected, "wrong failure reason");
        ++expectedReverts;
        // Expected errors are caught here. Any harness assertion or unexpected revert propagates
        // and fails the invariant runner, whose fail_on_revert setting is enabled below.
    }

    function _amount(uint256 seed, uint256 maximum) internal pure returns (uint256) {
        // Bias toward zero, one minor unit and the entire available amount, as well as the interior.
        if (seed % 4 == 0) return 0;
        if (seed % 4 == 1) return maximum == 0 ? 0 : 1;
        if (seed % 4 == 2) return maximum;
        return bound(seed, 0, maximum);
    }
}

/// @notice Conservation, independent accounting, authority isolation and fixed metadata after
/// arbitrary interleavings of successful and rejected operations.
/// forge-config: default.invariant.runs = 256
/// forge-config: default.invariant.depth = 128
/// forge-config: default.invariant.fail-on-revert = true
contract CELOGTokenInvariantTest is CELOGTestBase {
    struct FuzzSelector {
        address addr;
        bytes4[] selectors;
    }

    CELOGHandler internal handler;
    CELOGToken internal token;

    function setUp() public {
        handler = new CELOGHandler();
        token = handler.token();
    }

    // Foundry's invariant-target ABI, supplied locally to avoid introducing a forge-std dependency.
    function targetContracts() public view returns (address[] memory targets) {
        targets = new address[](1);
        targets[0] = address(handler);
    }

    function targetSelectors() public view returns (FuzzSelector[] memory targets) {
        bytes4[] memory selectors = new bytes4[](9);
        selectors[0] = CELOGHandler.transfer.selector;
        selectors[1] = CELOGHandler.approve.selector;
        selectors[2] = CELOGHandler.transferFrom.selector;
        selectors[3] = CELOGHandler.rejectTransferAboveBalance.selector;
        selectors[4] = CELOGHandler.rejectSpendAboveAllowance.selector;
        selectors[5] = CELOGHandler.rejectSpendAboveBalance.selector;
        selectors[6] = CELOGHandler.rejectZeroReceiver.selector;
        selectors[7] = CELOGHandler.rejectZeroSpender.selector;
        selectors[8] = CELOGHandler.roundTrip.selector;
        targets = new FuzzSelector[](1);
        targets[0] = FuzzSelector(address(handler), selectors);
    }

    function invariant_supplyEqualsAllTrackedBalances() public view {
        uint256 sum;
        for (uint256 i; i < 5; ++i) {
            sum += token.balanceOf(handler.actors(i));
        }
        assertEq(sum, SUPPLY, "tokens created, destroyed, or sent outside the closed actor set");
        assertEq(token.totalSupply(), SUPPLY, "fixed total supply changed");
        assertEq(token.balanceOf(address(0)), 0, "zero address received tokens");
        assertEq(token.balanceOf(address(this)), 0, "test contract unexpectedly received tokens");
    }

    function invariant_eachBalanceMatchesAuthorizedTransfers() public view {
        for (uint256 i; i < 5; ++i) {
            assertEq(token.balanceOf(handler.actors(i)), handler.expectedBalance(i), "balance disagrees with journal");
        }
    }

    function invariant_allowancesMatchLatestGrantMinusAuthorizedSpending() public view {
        for (uint256 owner; owner < 4; ++owner) {
            address account = handler.actors(owner);
            for (uint256 spender; spender < 4; ++spender) {
                assertEq(
                    token.allowance(account, handler.actors(spender)),
                    handler.expectedAllowance(owner, spender),
                    "allowance disagrees with grant/spend journal"
                );
            }
            assertEq(token.allowance(account, address(0)), 0, "zero spender gained approval");
            assertEq(token.allowance(address(token), account), 0, "token custody granted approval");
            assertEq(token.allowance(address(0), account), 0, "zero owner gained approval");
        }
    }

    function invariant_metadataIsStable() public view {
        assertEq(bytes(token.name()), bytes("CHANGELOG.md"), "name changed");
        assertEq(bytes(token.symbol()), bytes("CELOG"), "symbol changed");
        assertEq(token.decimals(), 18, "decimals changed");
        assertEq(token.INITIAL_SUPPLY(), SUPPLY, "initial supply constant changed");
    }

    function afterInvariant() public view {
        require(handler.calls() > 0, "invariant campaign did not drive the handler");
    }

    /// @dev Deterministically exercises every entry point and checks the journal after each one;
    /// this also documents the harness independently of random selector/argument selection.
    function test_handlerExercisesAllActionsAndChecksIntermediateState() public {
        handler.transfer(0, 1, 1);
        _checkAll();
        handler.approve(1, 2, 10, 4);
        _checkAll();
        handler.transferFrom(1, 2, 3, 2); // consumes exactly the finite approval
        _checkAll();
        handler.transferFrom(0, 2, 4, 1); // infinite approval, passive token recipient
        _checkAll();
        handler.rejectTransferAboveBalance(0, 0, type(uint256).max);
        _checkAll();
        handler.rejectSpendAboveAllowance(1, 2, 0);
        _checkAll();
        handler.rejectSpendAboveBalance(3, 1, false);
        _checkAll();
        handler.rejectSpendAboveBalance(3, 1, true);
        _checkAll();
        handler.rejectZeroReceiver(3, 1, 2, true);
        _checkAll();
        handler.rejectZeroReceiver(0, 1, 0, false);
        _checkAll();
        handler.rejectZeroSpender(1, type(uint256).max);
        _checkAll();
        handler.roundTrip(2, 3, 2);
        _checkAll();
        assertEq(handler.calls(), 12, "missing deterministic action");
        assertEq(handler.expectedReverts(), 7, "failure paths not reached");
        require(handler.positiveTransfers() >= 5, "only zero transfers executed");
        afterInvariant();
    }

    function _checkAll() internal view {
        invariant_supplyEqualsAllTrackedBalances();
        invariant_eachBalanceMatchesAuthorizedTransfers();
        invariant_allowancesMatchLatestGrantMinusAuthorizedSpending();
        invariant_metadataIsStable();
    }
}
