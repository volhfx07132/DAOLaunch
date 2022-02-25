// SPDX-License-Identifier: UNLICENSED


pragma solidity ^0.8.0;

interface IMigrator {
    function migrate(address lpToken, uint256 amount, uint256 unlockDate, address owner) external returns (bool);
}
