// SPDX-License-Identifier: MIT
pragma solidity 0.8.26;

import {CELOGToken} from "../src/CELOGToken.sol";

/// @dev The subset of Foundry's cheatcodes these tests use, declared here so the project vendors no
/// library. The address is Foundry's well-known cheatcode address, keccak256("hevm cheat code").
interface Vm {
    struct Log {
        bytes32[] topics;
        bytes data;
        address emitter;
    }

    function prank(address msgSender) external;
    function expectRevert(bytes calldata revertData) external;
    function expectRevert() external;
    function expectEmit(bool checkTopic1, bool checkTopic2, bool checkTopic3, bool checkData) external;
    function assume(bool condition) external pure;
    function recordLogs() external;
    function getRecordedLogs() external returns (Log[] memory logs);
}

/// @notice Behaviour tests for CHANGELOG.md (CELOG): metadata, the one-time mint, transfers,
/// allowances, every failure path, and the absence of any mint, owner or freezing power.
/// The test contract deploys the token, so it stands where the factory stands at launch.
contract CELOGTokenTest {
    Vm internal constant vm = Vm(address(uint160(uint256(keccak256("hevm cheat code")))));

    event Transfer(address indexed from, address indexed to, uint256 value);
    event Approval(address indexed owner, address indexed spender, uint256 value);

    uint256 internal constant SUPPLY = 1_000_000_000 * 10 ** 18;

    address internal constant ALICE = address(0xA11CE);
    address internal constant BOB = address(0xB0B);
    address internal constant CAROL = address(0xCA201);

    CELOGToken internal token;

    function setUp() public {
        token = new CELOGToken();
    }

    // ---------------------------------------------------------------------------------------------
    // Metadata and the one-time mint
    // ---------------------------------------------------------------------------------------------

    function test_metadata() public view {
        assertEq(token.name(), "CHANGELOG.md", "name");
        assertEq(token.symbol(), "CELOG", "symbol");
        assertEq(uint256(token.decimals()), 18, "decimals");
        assertEq(token.INITIAL_SUPPLY(), SUPPLY, "INITIAL_SUPPLY");
    }

    function test_changelogIsPublished() public view {
        require(bytes(token.CHANGELOG()).length > 0, "the on-chain changelog is empty");
    }

    function test_constructorMintsWholeSupplyToDeployer() public view {
        assertEq(token.totalSupply(), SUPPLY, "totalSupply");
        assertEq(token.balanceOf(address(this)), SUPPLY, "deployer balance");
    }

    function test_constructorEmitsMintTransfer() public {
        vm.recordLogs();
        CELOGToken fresh = new CELOGToken();
        Vm.Log[] memory logs = vm.getRecordedLogs();
        assertEq(logs.length, 1, "exactly one event in the constructor");
        assertEq(logs[0].emitter, address(fresh), "emitter");
        assertEq(logs[0].topics.length, 3, "Transfer has three topics");
        assertEq(logs[0].topics[0], keccak256("Transfer(address,address,uint256)"), "Transfer signature");
        assertEq(logs[0].topics[1], bytes32(0), "from the zero address");
        assertEq(logs[0].topics[2], bytes32(uint256(uint160(address(this)))), "to the deployer");
        assertEq(abi.decode(logs[0].data, (uint256)), SUPPLY, "minted amount");
    }

    function test_eachDeploymentMintsToItsOwnDeployer() public {
        vm.prank(ALICE);
        CELOGToken fresh = new CELOGToken();
        assertEq(fresh.balanceOf(ALICE), SUPPLY, "Alice's deployment belongs to Alice");
        assertEq(fresh.balanceOf(address(this)), 0, "this contract holds none of Alice's deployment");
        assertEq(token.balanceOf(address(this)), SUPPLY, "the first deployment is untouched");
    }

    // ---------------------------------------------------------------------------------------------
    // transfer
    // ---------------------------------------------------------------------------------------------

    function test_transfer_movesExactAmountAndEmits() public {
        uint256 amount = 1_234 ether;
        vm.expectEmit(true, true, true, true);
        emit Transfer(address(this), ALICE, amount);
        bool ok = token.transfer(ALICE, amount);
        require(ok, "transfer returned false");
        assertEq(token.balanceOf(ALICE), amount, "receiver got exactly the amount");
        assertEq(token.balanceOf(address(this)), SUPPLY - amount, "sender paid exactly the amount");
        assertEq(token.totalSupply(), SUPPLY, "supply unchanged");
    }

    function test_transfer_wholeBalanceLeavesZero() public {
        token.transfer(ALICE, SUPPLY);
        assertEq(token.balanceOf(address(this)), 0, "sender emptied");
        assertEq(token.balanceOf(ALICE), SUPPLY, "receiver holds everything");
    }

    function test_transfer_zeroAmountSucceeds() public {
        vm.expectEmit(true, true, true, true);
        emit Transfer(address(this), ALICE, 0);
        require(token.transfer(ALICE, 0), "zero transfer returned false");
        assertEq(token.balanceOf(ALICE), 0, "nothing arrived");
    }

    function test_transfer_toSelfKeepsBalance() public {
        require(token.transfer(address(this), 500 ether), "self transfer returned false");
        assertEq(token.balanceOf(address(this)), SUPPLY, "self transfer changed the balance");
    }

    function test_transfer_revertsWhenBalanceIsShort() public {
        token.transfer(ALICE, 10 ether);
        vm.expectRevert(
            abi.encodeWithSelector(CELOGToken.ERC20InsufficientBalance.selector, ALICE, 10 ether, 10 ether + 1)
        );
        vm.prank(ALICE);
        token.transfer(BOB, 10 ether + 1);
    }

    function test_transfer_revertsFromEmptyAccount() public {
        vm.expectRevert(abi.encodeWithSelector(CELOGToken.ERC20InsufficientBalance.selector, BOB, 0, 1));
        vm.prank(BOB);
        token.transfer(ALICE, 1);
    }

    function test_transfer_revertsToZeroAddress() public {
        vm.expectRevert(abi.encodeWithSelector(CELOGToken.ERC20InvalidReceiver.selector, address(0)));
        token.transfer(address(0), 1);
    }

    // ---------------------------------------------------------------------------------------------
    // approve / allowance
    // ---------------------------------------------------------------------------------------------

    function test_approve_setsAllowanceAndEmits() public {
        vm.expectEmit(true, true, true, true);
        emit Approval(address(this), ALICE, 42);
        require(token.approve(ALICE, 42), "approve returned false");
        assertEq(token.allowance(address(this), ALICE), 42, "allowance set");
    }

    function test_approve_replacesPriorAllowance() public {
        token.approve(ALICE, 100);
        token.approve(ALICE, 7);
        assertEq(token.allowance(address(this), ALICE), 7, "allowance replaced, not added");
        token.approve(ALICE, 0);
        assertEq(token.allowance(address(this), ALICE), 0, "allowance cleared");
    }

    function test_approve_mayExceedBalance() public {
        vm.prank(ALICE);
        require(token.approve(BOB, type(uint256).max), "approve returned false");
        assertEq(token.allowance(ALICE, BOB), type(uint256).max, "allowance is independent of balance");
    }

    function test_approve_revertsForZeroSpender() public {
        vm.expectRevert(abi.encodeWithSelector(CELOGToken.ERC20InvalidSpender.selector, address(0)));
        token.approve(address(0), 1);
    }

    // ---------------------------------------------------------------------------------------------
    // transferFrom
    // ---------------------------------------------------------------------------------------------

    function test_transferFrom_spendsAllowanceAndMovesExactAmount() public {
        token.approve(ALICE, 100 ether);
        vm.expectEmit(true, true, true, true);
        emit Transfer(address(this), BOB, 60 ether);
        vm.prank(ALICE);
        bool ok = token.transferFrom(address(this), BOB, 60 ether);
        require(ok, "transferFrom returned false");
        assertEq(token.balanceOf(BOB), 60 ether, "receiver got exactly the amount");
        assertEq(token.balanceOf(address(this)), SUPPLY - 60 ether, "owner paid exactly the amount");
        assertEq(token.allowance(address(this), ALICE), 40 ether, "allowance reduced by the amount");
        assertEq(token.balanceOf(ALICE), 0, "the spender received nothing");
    }

    function test_transferFrom_exactAllowanceLeavesZero() public {
        token.approve(ALICE, 5 ether);
        vm.prank(ALICE);
        token.transferFrom(address(this), BOB, 5 ether);
        assertEq(token.allowance(address(this), ALICE), 0, "allowance exhausted");
        vm.expectRevert(abi.encodeWithSelector(CELOGToken.ERC20InsufficientAllowance.selector, ALICE, 0, 1));
        vm.prank(ALICE);
        token.transferFrom(address(this), BOB, 1);
    }

    function test_transferFrom_infiniteAllowanceIsNotReduced() public {
        token.approve(ALICE, type(uint256).max);
        vm.prank(ALICE);
        token.transferFrom(address(this), BOB, 1 ether);
        assertEq(token.allowance(address(this), ALICE), type(uint256).max, "infinite allowance stays infinite");
        assertEq(token.balanceOf(BOB), 1 ether, "tokens moved");
    }

    function test_transferFrom_revertsWithoutAllowance() public {
        vm.expectRevert(abi.encodeWithSelector(CELOGToken.ERC20InsufficientAllowance.selector, ALICE, 0, 1));
        vm.prank(ALICE);
        token.transferFrom(address(this), ALICE, 1);
        assertEq(token.balanceOf(address(this)), SUPPLY, "nothing moved");
    }

    function test_transferFrom_revertsWhenAllowanceIsShort() public {
        token.approve(ALICE, 9);
        vm.expectRevert(abi.encodeWithSelector(CELOGToken.ERC20InsufficientAllowance.selector, ALICE, 9, 10));
        vm.prank(ALICE);
        token.transferFrom(address(this), BOB, 10);
        assertEq(token.allowance(address(this), ALICE), 9, "allowance untouched after a failed spend");
    }

    function test_transferFrom_revertsWhenOwnerBalanceIsShort() public {
        token.transfer(CAROL, 3);
        vm.prank(CAROL);
        token.approve(ALICE, 10);
        vm.expectRevert(abi.encodeWithSelector(CELOGToken.ERC20InsufficientBalance.selector, CAROL, 3, 4));
        vm.prank(ALICE);
        token.transferFrom(CAROL, BOB, 4);
        assertEq(token.allowance(CAROL, ALICE), 10, "allowance untouched when the transfer reverts");
    }

    function test_transferFrom_revertsToZeroAddress() public {
        token.approve(ALICE, 10);
        vm.expectRevert(abi.encodeWithSelector(CELOGToken.ERC20InvalidReceiver.selector, address(0)));
        vm.prank(ALICE);
        token.transferFrom(address(this), address(0), 1);
    }

    function test_transferFrom_allowanceIsPerSpender() public {
        token.approve(ALICE, 10);
        vm.expectRevert(abi.encodeWithSelector(CELOGToken.ERC20InsufficientAllowance.selector, BOB, 0, 1));
        vm.prank(BOB);
        token.transferFrom(address(this), BOB, 1);
    }

    // ---------------------------------------------------------------------------------------------
    // Launch flows: the amounts the factory, distributor and pool manager move arrive whole
    // ---------------------------------------------------------------------------------------------

    function test_launchFlows_arriveWhole() public {
        address distributor = address(0xD157);
        address claimant = address(0xC1A1);
        address remainderTo = address(0x3eD212257958724579F13B3dbA74a07AC6007903);
        uint256 swarm = (SUPPLY * 1_000) / 10_000;
        uint256 pool = (SUPPLY * 7_000) / 10_000;
        uint256 rest = SUPPLY - swarm - pool;

        require(token.transfer(distributor, swarm), "swarm transfer returned false");
        assertEq(token.balanceOf(distributor), swarm, "swarm share arrived short");

        vm.prank(distributor);
        require(token.transfer(claimant, swarm), "claim transfer returned false");
        assertEq(token.balanceOf(claimant), swarm, "claim arrived short");
        assertEq(token.balanceOf(distributor), 0, "distributor kept something back");

        require(token.transfer(remainderTo, rest), "remainder transfer returned false");
        assertEq(token.balanceOf(remainderTo), rest, "remainder arrived short");
        assertEq(token.balanceOf(address(this)), pool, "exactly the pool share remains with the factory");
        assertEq(token.totalSupply(), SUPPLY, "launch flows changed the supply");
    }

    // ---------------------------------------------------------------------------------------------
    // No mint, no owner, no freezing power
    // ---------------------------------------------------------------------------------------------

    function test_noCallIncreasesSupplyOrCreditsCaller() public {
        address attacker = address(0xBEEF);
        string[10] memory signatures = [
            "mint(address,uint256)",
            "mint(uint256)",
            "mint()",
            "issue(uint256)",
            "setOwner(address)",
            "transferOwnership(address)",
            "upgradeTo(address)",
            "initialize(address)",
            "unpause()",
            "setMinter(address)"
        ];
        for (uint256 i = 0; i < signatures.length; i++) {
            bytes memory data = abi.encodeWithSignature(signatures[i], attacker, type(uint128).max);
            vm.prank(attacker);
            (bool okFromAttacker,) = address(token).call(data);
            require(!okFromAttacker, string.concat("unexpected function answered: ", signatures[i]));
            // From the deployer too, which is the address a token would most plausibly trust.
            (bool okFromDeployer,) = address(token).call(data);
            require(!okFromDeployer, string.concat("unexpected function answered the deployer: ", signatures[i]));
            assertEq(token.totalSupply(), SUPPLY, signatures[i]);
            assertEq(token.balanceOf(attacker), 0, signatures[i]);
        }
    }

    function test_noPrivilegedCallMovesOrFreezesAHolder() public {
        token.transfer(ALICE, SUPPLY / 1_000);
        uint256 held = token.balanceOf(ALICE);
        string[12] memory signatures = [
            "pause()",
            "blacklist(address)",
            "blocklist(address)",
            "freeze(address)",
            "freezeAccount(address)",
            "setBlacklist(address,bool)",
            "setBlocked(address,bool)",
            "lock(address)",
            "disableTransfers()",
            "setTransfersEnabled(bool)",
            "burnFrom(address,uint256)",
            "seize(address)"
        ];
        for (uint256 i = 0; i < signatures.length; i++) {
            bytes memory data = abi.encodeWithSignature(signatures[i], ALICE, true);
            (bool ok,) = address(token).call(data);
            require(!ok, string.concat("unexpected privileged function answered: ", signatures[i]));
        }
        // The deployer cannot pull from a holder without an allowance.
        vm.expectRevert(abi.encodeWithSelector(CELOGToken.ERC20InsufficientAllowance.selector, address(this), 0, 1));
        token.transferFrom(ALICE, address(this), 1);
        assertEq(token.balanceOf(ALICE), held, "a privileged call moved the holder's balance");
        vm.prank(ALICE);
        require(token.transfer(BOB, held / 2), "the holder can no longer transfer");
        assertEq(token.balanceOf(BOB), held / 2, "the holder's transfer delivered short");
    }

    function test_noEtherAccepted() public {
        (bool ok,) = address(token).call{value: 0}("");
        require(!ok, "the token accepted a plain call");
    }

    // ---------------------------------------------------------------------------------------------
    // Fuzz
    // ---------------------------------------------------------------------------------------------

    function testFuzz_transferConservesSupply(address to, uint256 amount) public {
        vm.assume(to != address(0) && to != address(this));
        amount = amount % (SUPPLY + 1);
        require(token.transfer(to, amount), "transfer returned false");
        assertEq(token.balanceOf(to), amount, "receiver balance");
        assertEq(token.balanceOf(address(this)), SUPPLY - amount, "sender balance");
        assertEq(token.balanceOf(to) + token.balanceOf(address(this)), SUPPLY, "conservation");
        assertEq(token.totalSupply(), SUPPLY, "supply");
    }

    function testFuzz_transferAboveBalanceReverts(address to, uint256 excess) public {
        vm.assume(to != address(0));
        excess = 1 + (excess % 1_000_000 ether);
        vm.expectRevert(
            abi.encodeWithSelector(CELOGToken.ERC20InsufficientBalance.selector, address(this), SUPPLY, SUPPLY + excess)
        );
        token.transfer(to, SUPPLY + excess);
    }

    function testFuzz_transferFromSpendsExactlyTheAllowance(address spender, uint256 allowed, uint256 amount) public {
        vm.assume(spender != address(0) && spender != address(this) && spender != address(vm));
        allowed = allowed % (SUPPLY + 1);
        amount = amount % (allowed + 1);
        token.approve(spender, allowed);
        vm.prank(spender);
        require(token.transferFrom(address(this), spender, amount), "transferFrom returned false");
        assertEq(token.allowance(address(this), spender), allowed - amount, "allowance spent exactly");
        assertEq(token.balanceOf(spender), amount, "spender received exactly the amount");
        assertEq(token.balanceOf(address(this)), SUPPLY - amount, "owner paid exactly the amount");
    }

    function testFuzz_transferFromAboveAllowanceReverts(address spender, uint256 allowed) public {
        vm.assume(spender != address(0) && spender != address(vm));
        allowed = allowed % SUPPLY; // strictly below the supply, so allowed + 1 is still payable
        token.approve(spender, allowed);
        vm.expectRevert(
            abi.encodeWithSelector(CELOGToken.ERC20InsufficientAllowance.selector, spender, allowed, allowed + 1)
        );
        vm.prank(spender);
        token.transferFrom(address(this), BOB, allowed + 1);
    }

    function testFuzz_approveStoresAnyValue(address spender, uint256 value) public {
        vm.assume(spender != address(0));
        require(token.approve(spender, value), "approve returned false");
        assertEq(token.allowance(address(this), spender), value, "allowance");
    }

    // ---------------------------------------------------------------------------------------------
    // Assertions (a reverting test is a failing test)
    // ---------------------------------------------------------------------------------------------

    function assertEq(uint256 a, uint256 b, string memory what) internal pure {
        require(a == b, string.concat("assertEq(uint256) failed: ", what));
    }

    function assertEq(address a, address b, string memory what) internal pure {
        require(a == b, string.concat("assertEq(address) failed: ", what));
    }

    function assertEq(bytes32 a, bytes32 b, string memory what) internal pure {
        require(a == b, string.concat("assertEq(bytes32) failed: ", what));
    }

    function assertEq(string memory a, string memory b, string memory what) internal pure {
        require(keccak256(bytes(a)) == keccak256(bytes(b)), string.concat("assertEq(string) failed: ", what));
    }
}
