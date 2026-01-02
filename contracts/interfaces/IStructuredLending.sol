// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

/**
 * @title IStructuredLending - Interface principale du protocole de prêt
 * @notice Interface standardisée pour l'intégration
 */
interface IStructuredLending {
    
    // Structures de données
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
    
    struct InvestmentInfo {
        address investor;
        uint256 amount;
        uint256 tokens;
        uint256 investmentTime;
    }
    
    // Événements
    event PoolCreated(uint256 indexed poolId, address indexed borrower);
    event InvestmentMade(uint256 indexed poolId, address indexed investor, uint256 amount);
    event RepaymentMade(uint256 indexed poolId, uint256 amount);
    event PoolCompleted(uint256 indexed poolId);
    
    // Fonctions principales
    function createPool(
        string memory projectName,
        uint256 targetAmount,
        uint256 duration,
        string memory region,
        bool isEcological,
        string memory activityDomain,
        string memory ipfsHash
    ) external returns (uint256);
    
    function invest(uint256 poolId, uint256 amount) external;
    
    function repay(uint256 poolId, uint256 amount) external;
    
    function getPoolDetails(uint256 poolId) external view returns (PoolData memory);
    
    function getPoolInvestments(uint256 poolId) external view returns (InvestmentInfo[] memory);
    
    function calculateDynamicRate(uint256 poolId) external view returns (uint256);
    
    // Fonctions d'administration
    function setProtocolFee(uint256 fee) external;
    
    function setMinMaxInvestment(uint256 min, uint256 max) external;
    
    function emergencyPause(bool paused) external;
}