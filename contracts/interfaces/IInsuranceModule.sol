// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

interface IInsuranceModule {
    function subscribeCoverage(
        uint256 poolId,
        uint256 coverageAmount,
        uint256 insurancePoolId
    ) external;
    
    function fileClaim(uint256 poolId, uint256 claimAmount) external;
}