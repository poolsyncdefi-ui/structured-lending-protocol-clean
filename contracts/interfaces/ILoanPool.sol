// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

interface ILoanPool {
    struct PoolData {
        uint256 poolId;
        address borrower;
        string projectName;
        uint256 targetAmount;
        uint256 collectedAmount;
        uint256 baseInterestRate;
        uint256 dynamicInterestRate;
        uint256 duration;
        string region;
        bool isEcological;
        string activityDomain;
        uint256 riskScore;
        uint256 status;
        uint256 createdAt;
    }
    
    function getPoolDetails(uint256 poolId) external view returns (PoolData memory);
}