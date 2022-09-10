// SPDX-License-Identifier: GPL-3.0
pragma solidity =0.6.12;

library SafeCast {
        
    function toInt64(uint256 value) internal pure returns (int64) {
        // Note: Unsafe cast below is okay because `type(int256).max` is guaranteed to be positive
        require(value <= uint256(type(int64).max), "SafeCast: value doesn't fit in an int64");
        return int64(value);
    }

    function toUint64(uint256 value) internal pure returns (uint64) {
        require(value <= type(uint64).max, "SafeCast: value doesn't fit in 64 bits");
        return uint64(value);
    }
}