// SPDX-License-Identifier: MIT
pragma solidity 0.8.26;

/// @title CHANGELOG.md (CELOG)
/// @notice A fixed-supply ERC-20. The whole supply of 1,000,000,000 CELOG (18 decimals) is minted
/// once, in the constructor, to the deployer (`msg.sender`), which on launch is the IdentityMD
/// factory. Nothing can mint afterwards, nothing can pause, freeze, tax or seize, and the token has
/// no owner or administrator. Every transfer, including the launch flows (factory to distributor,
/// factory to pool manager, distributor to claimant, trader to and from the pool), moves exactly
/// the amount requested.
/// @dev Self-contained ERC-20 following the ERC-20 standard and the ERC-6093 custom-error names
/// used by OpenZeppelin v5, so wallets, explorers and integrators decode failures the usual way.
/// An allowance of `type(uint256).max` is treated as infinite and not decreased on `transferFrom`.
contract CELOGToken {
    // ---------------------------------------------------------------------------------------------
    // Metadata
    // ---------------------------------------------------------------------------------------------

    /// @notice The token's name, as the requester wrote it.
    string public constant name = "CHANGELOG.md";

    /// @notice The token's symbol.
    string public constant symbol = "CELOG";

    /// @notice Minor units per whole token: 10 ** 18.
    uint8 public constant decimals = 18;

    /// @notice The entire supply, in minor units: one billion whole tokens.
    uint256 public constant INITIAL_SUPPLY = 1_000_000_000 * 10 ** 18;

    /// @notice The token's own change log, kept on chain as the name promises. Each release of this
    /// contract appends a line; the deployed bytecode is immutable, so the line for a deployment
    /// is the last one it will ever have.
    string public constant CHANGELOG =
        "## 1.0.0\n- Fixed supply of 1,000,000,000 CELOG minted once to the deployer.\n- Plain ERC-20 transfers and allowances; no owner, no mint, no pause, no fee.\n";

    // ---------------------------------------------------------------------------------------------
    // State
    // ---------------------------------------------------------------------------------------------

    /// @notice Tokens in existence. Set once in the constructor; this contract has no mint or burn.
    uint256 public immutable totalSupply;

    /// @notice Balance of each holder, in minor units.
    mapping(address account => uint256) public balanceOf;

    /// @notice Remaining amount `spender` may move from `owner` with `transferFrom`.
    mapping(address owner => mapping(address spender => uint256)) public allowance;

    // ---------------------------------------------------------------------------------------------
    // Events (ERC-20)
    // ---------------------------------------------------------------------------------------------

    event Transfer(address indexed from, address indexed to, uint256 value);
    event Approval(address indexed owner, address indexed spender, uint256 value);

    // ---------------------------------------------------------------------------------------------
    // Errors (ERC-6093)
    // ---------------------------------------------------------------------------------------------

    error ERC20InsufficientBalance(address sender, uint256 balance, uint256 needed);
    error ERC20InvalidReceiver(address receiver);
    error ERC20InsufficientAllowance(address spender, uint256 allowance, uint256 needed);
    error ERC20InvalidSpender(address spender);

    // ---------------------------------------------------------------------------------------------
    // Constructor
    // ---------------------------------------------------------------------------------------------

    /// @notice Mints the whole supply to the deployer. Takes no arguments and calls no other
    /// contract, so it deploys on an empty chain exactly as the launch checks run it.
    constructor() {
        totalSupply = INITIAL_SUPPLY;
        balanceOf[msg.sender] = INITIAL_SUPPLY;
        emit Transfer(address(0), msg.sender, INITIAL_SUPPLY);
    }

    // ---------------------------------------------------------------------------------------------
    // ERC-20
    // ---------------------------------------------------------------------------------------------

    /// @notice Moves `value` from the caller to `to`.
    /// @dev Reverts with `ERC20InvalidReceiver` for the zero address and `ERC20InsufficientBalance`
    /// when the caller holds less than `value`. A zero-value transfer succeeds and emits.
    function transfer(address to, uint256 value) external returns (bool) {
        _transfer(msg.sender, to, value);
        return true;
    }

    /// @notice Lets `spender` move up to `value` of the caller's tokens. Replaces any prior allowance.
    /// @dev Reverts with `ERC20InvalidSpender` for the zero address.
    function approve(address spender, uint256 value) external returns (bool) {
        if (spender == address(0)) revert ERC20InvalidSpender(address(0));
        allowance[msg.sender][spender] = value;
        emit Approval(msg.sender, spender, value);
        return true;
    }

    /// @notice Moves `value` from `from` to `to` using the caller's allowance from `from`.
    /// @dev The allowance is spent before the balance moves. An allowance of `type(uint256).max` is
    /// infinite and is not reduced. Reverts with `ERC20InsufficientAllowance` when the allowance is
    /// short, then with the same errors as `transfer`.
    function transferFrom(address from, address to, uint256 value) external returns (bool) {
        uint256 current = allowance[from][msg.sender];
        if (current != type(uint256).max) {
            if (current < value) revert ERC20InsufficientAllowance(msg.sender, current, value);
            // Unchecked: `current >= value` was just checked.
            unchecked {
                allowance[from][msg.sender] = current - value;
            }
        }
        _transfer(from, to, value);
        return true;
    }

    // ---------------------------------------------------------------------------------------------
    // Internal
    // ---------------------------------------------------------------------------------------------

    function _transfer(address from, address to, uint256 value) internal {
        if (to == address(0)) revert ERC20InvalidReceiver(address(0));
        uint256 fromBalance = balanceOf[from];
        if (fromBalance < value) revert ERC20InsufficientBalance(from, fromBalance, value);
        // Unchecked: `fromBalance >= value` was just checked, and no balance can exceed the fixed
        // total supply, so the credit cannot overflow.
        unchecked {
            balanceOf[from] = fromBalance - value;
            balanceOf[to] += value;
        }
        emit Transfer(from, to, value);
    }
}
