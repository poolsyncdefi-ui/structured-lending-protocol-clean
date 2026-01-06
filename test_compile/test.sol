// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;
contract Test {
    function testFunc() public pure returns (uint256) { return 1; }
    function callTest() public pure returns (uint256) { return testFunc(); }
}
