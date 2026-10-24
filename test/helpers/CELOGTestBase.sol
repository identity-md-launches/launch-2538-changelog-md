// SPDX-License-Identifier: MIT
pragma solidity 0.8.26;

/// @dev Keep the existing project's dependency-free test setup. Only testing cheatcodes are exposed.
interface CELOGVm {
    struct Log {
        bytes32[] topics;
        bytes data;
        address emitter;
    }

    function prank(address caller) external;
    function deal(address account, uint256 balance) external;
    function recordLogs() external;
    function getRecordedLogs() external returns (Log[] memory);
}

abstract contract CELOGTestBase {
    CELOGVm internal constant vm = CELOGVm(address(uint160(uint256(keccak256("hevm cheat code")))));
    uint256 internal constant SUPPLY = 1_000_000_000 * 10 ** 18;
    address internal constant ALICE = address(0xCE101);
    address internal constant BOB = address(0xCE102);
    address internal constant CAROL = address(0xCE103);
    address internal constant DAVE = address(0xCE104);

    /// @dev Inclusive bounds without discarded fuzz inputs; also handles the full uint256 range.
    function bound(uint256 value, uint256 minimum, uint256 maximum) internal pure returns (uint256) {
        require(minimum <= maximum, "invalid test bounds");
        if (value >= minimum && value <= maximum) return value;
        uint256 width = maximum - minimum;
        if (width == type(uint256).max) return value;
        return minimum + (value % (width + 1));
    }

    function assertEq(uint256 actual, uint256 expected, string memory message) internal pure {
        require(actual == expected, message);
    }

    function assertEq(bytes memory actual, bytes memory expected, string memory message) internal pure {
        require(keccak256(actual) == keccak256(expected), message);
    }
}
