// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

interface IRiskEngine {
    function calculateBaseRate(
        address borrower,
        uint256 amount,
        uint256 duration,
        bool isEcological,
        string calldata activityDomain
    ) external returns (uint256);
    
    function calculateRiskScore(
        address borrower,
        uint256 amount,
        uint256 duration,
        string calldata region,
        bool isEcological,
        string calldata activityDomain
    ) external returns (uint256);
    
    function validatePool(uint256 poolId) external returns (bool);
    
    function adjustRateForMarketConditions(
        uint256 poolId,
        uint256 currentRate
    ) external view returns (uint256);
}