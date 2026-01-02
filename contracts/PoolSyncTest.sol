// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

contract PoolSyncTest {
    string public name = "PoolSync";
    uint256 public version = 1;
    
    function getName() public view returns (string memory) {
        return name;
    }
    
    function getVersion() public view returns (uint256) {
        return version;
    }
}
