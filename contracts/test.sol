// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

contract TestContract {
    function createOffer() public pure returns (uint256) {
        return 1;
    }
    
    function callCreateOffer() public pure returns (uint256) {
        return createOffer();
    }
}