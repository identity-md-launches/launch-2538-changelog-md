# CHANGELOG.md (CELOG)

A fixed-supply ERC-20 token for an IdentityMD custom-token launch on Ethereum (chain id 1).

| Parameter | Value |
|-----------|-------|
| Solidity contract | `CELOGToken` (`src/CELOGToken.sol`) |
| `name()` | `CHANGELOG.md` |
| `symbol()` | `CELOG` |
| `decimals()` | 18 |
| `totalSupply()` | 1,000,000,000 CELOG = `1000000000000000000000000000` minor units |
| Constructor arguments | none |
| Owner / admin | none |
| Compiler | solc 0.8.26, optimizer on (200 runs), `bytecode_hash = "none"`, EVM `cancun` |

## What it does

The brief asks for a token named CHANGELOG.md and nothing beyond a standard token, so the contract
is a plain ERC-20:

- The constructor mints the entire supply once to `msg.sender` and emits the standard mint
  `Transfer(address(0), deployer, supply)`. On launch `msg.sender` is the IdentityMD factory,
  which pays the supply out (10% to the swarm's MerkleDistributor, 70% into the Uniswap v4 pool,
  20% to the requester's `remainderTo` address) according to the launch economics.
- `transfer`, `approve`, `transferFrom`, `balanceOf`, `allowance`, `totalSupply`, `name`,
  `symbol` and `decimals` behave exactly as ERC-20 specifies. Every transfer moves exactly the
  amount requested: there is no fee, tax, burn-on-transfer, reflection or exemption list, so the
  launch flows (factory, distributor, pool manager, traders) arrive whole.
- An allowance of `type(uint256).max` is treated as infinite and is not reduced by `transferFrom`.
- Failures revert with the ERC-6093 custom errors `ERC20InsufficientBalance`,
  `ERC20InvalidReceiver`, `ERC20InsufficientAllowance` and `ERC20InvalidSpender`.
- `CHANGELOG()` returns a constant string holding the contract's own release notes, as a nod to the
  token's name. It is read-only and has no effect on balances.

## What it deliberately does not do

- No `mint`, `burn`, `burnFrom`, owner, minter role, upgrade path, proxy, `delegatecall` or
  `selfdestruct`. `totalSupply` is an immutable set once in the constructor; the supply can never
  grow or shrink.
- No `pause`, blacklist, freeze, lock, seize or transfer switch. Nobody but a holder (or a spender
  the holder approved) can move a holder's balance.
- No external calls of any kind, so there is no reentrancy surface and the constructor deploys on an
  empty chain.
- No ETH handling: the contract has no `receive` or `fallback`, so plain transfers of ETH to it revert.

## Deployment parameters

The launch is performed by IdentityMD's deployer through the project factory; nothing in this
repository deploys, broadcasts or holds keys.

- `token.contract`: `CELOGToken`
- `token.constructorArgs`: `[]` (the constructor takes no arguments)
- `token.decimals`: `18`
- `token.totalSupply`: `1000000000000000000000000000`
- `contracts`: `[]` (no application contracts)
- Pool, pair currency (IMD), fee (1.25%), tick spacing and economics are the launch's and are
  written by the manifest step, not by this repository.

Because the constructor mints to `msg.sender`, the supply lands with whichever address deploys the
bytecode. On launch that is the factory, as the custom-token floor requires.

## Assumptions

- The requester wants a standard token: the brief gives the name, symbol and supply and nothing
  else, so no fee, tax, vesting, governance or owner powers were added. Adding any later would need
  a new contract; this one is immutable.
- The ERC-20 is implemented in this repository rather than imported, so the project has no library
  dependency to vendor. It follows the OpenZeppelin v5 semantics (ERC-6093 errors, infinite
  allowance, zero-address checks on receiver and spender).
- Zero-value transfers succeed and emit, as the ERC-20 standard requires.

## Operational responsibilities

There is nothing to operate: the contract has no owner, no settings and no upgrade path.

- **Holders** are responsible for their own keys and for the allowances they grant. Approving
  `type(uint256).max` grants a spender unlimited access until revoked with `approve(spender, 0)`.
- **Integrators** should treat the token as a vanilla 18-decimal ERC-20 with revert-on-failure
  semantics and `bool` return values.
- **The launch deployer** (IdentityMD) deploys the attested bytecode and distributes the supply; no
  action from the requester is needed before or after deployment.

## After launch

Nothing to set. The token has no owner-settable values and no outside-service addresses.

## Chosen constants

No numeric value was left open by the brief: name, symbol, supply and decimals are the requester's.
`INITIAL_SUPPLY` (1,000,000,000 × 10^18) is the only constant and is exposed publicly.

## Security notes

- Checked against the eth-security checklist: no reentrancy surface (no external calls), no oracle,
  no decimals assumption about other tokens, input validation on receiver and spender, events on
  every state change, no infinite approvals granted by the contract itself, no proxies, no
  `delegatecall`, no `selfdestruct`.
- Slither detectors the verifier rejects on are designed out: no `selfdestruct`, no `transferFrom`
  calls on other tokens, no initializers or upgrades, no storage pointers, no shifts, no
  `abi.encodePacked` of dynamic values.
- Tests passing is not a security audit. For a token this simple the residual risks are off-chain:
  phishing of holder approvals and key loss.

## Build and test

```sh
forge build
forge test
forge fmt --check
```

The verifier runs fuzz tests with a fixed seed; to reproduce:

```sh
FOUNDRY_FUZZ_SEED=0x95ad95d936309b7a2dd6ac98d4622a0b8ad6154266584ee106cdbc3ef7b1cea6 forge test
```

The tests (`test/CELOGToken.t.sol`) vendor no library: they declare the handful of Foundry
cheatcodes they use and fail by reverting. They cover metadata, the one-time mint and its event,
transfers (success, zero amount, self, whole balance, insufficient balance, zero receiver),
allowances (set, replace, clear, zero spender, infinite), `transferFrom` (exact spend, exhausted,
short allowance, short owner balance, zero receiver, per-spender isolation), the launch flows
arriving whole, the absence of any mint, owner or freezing function, and fuzzed conservation of
supply and allowance accounting.
