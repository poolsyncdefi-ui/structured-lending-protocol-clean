// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/utils/ReentrancyGuard.sol";
import "@openzeppelin/contracts/utils/Pausable.sol";
import "@openzeppelin/contracts/access/AccessControl.sol";

contract FeeDistributor is ReentrancyGuard, AccessControl {
    // Structure de distribution
    struct DistributionPool {
        address recipient;
        uint256 sharePercentage;
        string description;
        bool isActive;
    }
    
    // Structure de frais accumulés
    struct AccruedFees {
        address token;
        uint256 amount;
        uint256 lastDistribution;
    }
    
    // Structure de récompense de performance
    struct PerformanceReward {
        address recipient;
        uint256 rewardAmount;
        uint256 timestamp;
        string performanceMetric;
    }
    
    // Variables d'état
    DistributionPool[] public distributionPools;
    mapping(address => AccruedFees) public accruedFees;
    mapping(address => PerformanceReward[]) public performanceRewards;
    
    uint256 public totalDistributed;
    uint256 public distributionInterval = 7 days;
    uint256 public lastDistributionTime;
    
    address public feeToken;
    
    // Événements
    event FeesAccrued(
        address indexed token,
        uint256 amount,
        address indexed source,
        uint256 timestamp
    );
    
    event DistributionExecuted(
        uint256 distributionId,
        uint256 totalAmount,
        uint256 timestamp
    );
    
    event PoolAdded(
        uint256 poolId,
        address recipient,
        uint256 sharePercentage,
        string description
    );
    
    event PerformanceRewardDistributed(
        address indexed recipient,
        uint256 amount,
        string metric,
        uint256 timestamp
    );
    
    // Rôles
    bytes32 public constant FEE_COLLECTOR = keccak256("FEE_COLLECTOR");
    bytes32 public constant DISTRIBUTOR = keccak256("DISTRIBUTOR");
    
    constructor(address _feeToken) {
        feeToken = _feeToken;
        
        _grantRole(DEFAULT_ADMIN_ROLE, msg.sender);
        _grantRole(FEE_COLLECTOR, msg.sender);
        _grantRole(DISTRIBUTOR, msg.sender);
        
        // Initialisation des pools par défaut
        _initializeDefaultPools();
        
        lastDistributionTime = block.timestamp;
    }
    
    // Initialisation des pools par défaut
    function _initializeDefaultPools() private {
        // Pool 1: Trésorerie du protocole
        distributionPools.push(DistributionPool({
            recipient: msg.sender,
            sharePercentage: 4000, // 40%
            description: "Protocol Treasury",
            isActive: true
        }));
        
        // Pool 2: Récompenses des stakers
        distributionPools.push(DistributionPool({
            recipient: address(0), // À définir
            sharePercentage: 3000, // 30%
            description: "Staker Rewards",
            isActive: true
        }));
        
        // Pool 3: Fonds de développement
        distributionPools.push(DistributionPool({
            recipient: address(0), // À définir
            sharePercentage: 1500, // 15%
            description: "Development Fund",
            isActive: true
        }));
        
        // Pool 4: Fonds d'assurance
        distributionPools.push(DistributionPool({
            recipient: address(0), // À définir
            sharePercentage: 1000, // 10%
            description: "Insurance Fund",
            isActive: true
        }));
        
        // Pool 5: Réserve d'urgence
        distributionPools.push(DistributionPool({
            recipient: address(0), // À définir
            sharePercentage: 500, // 5%
            description: "Emergency Reserve",
            isActive: true
        }));
    }
    
    // Accumulation de frais
    function accrueFees(uint256 amount, address source) external onlyRole(FEE_COLLECTOR) {
        require(amount > 0, "Amount must be > 0");
        
        // Transfert des tokens
        IERC20 token = IERC20(feeToken);
        require(
            token.transferFrom(msg.sender, address(this), amount),
            "Transfer failed"
        );
        
        // Mise à jour des frais accumulés
        AccruedFees storage fees = accruedFees[feeToken];
        fees.token = feeToken;
        fees.amount += amount;
        
        emit FeesAccrued(feeToken, amount, source, block.timestamp);
    }
    
    // Distribution des frais
    function distributeFees() external nonReentrant onlyRole(DISTRIBUTOR) {
        require(
            block.timestamp >= lastDistributionTime + distributionInterval,
            "Too soon for distribution"
        );
        
        AccruedFees storage fees = accruedFees[feeToken];
        require(fees.amount > 0, "No fees to distribute");
        
        uint256 distributionId = uint256(keccak256(abi.encodePacked(
            block.timestamp,
            fees.amount
        )));
        
        uint256 remainingAmount = fees.amount;
        
        // Distribution aux pools actifs
        for (uint256 i = 0; i < distributionPools.length; i++) {
            if (distributionPools[i].isActive && distributionPools[i].recipient != address(0)) {
                uint256 poolShare = (fees.amount * distributionPools[i].sharePercentage) / 10000;
                
                if (poolShare > 0 && poolShare <= remainingAmount) {
                    IERC20 token = IERC20(feeToken);
                    token.transfer(distributionPools[i].recipient, poolShare);
                    
                    remainingAmount -= poolShare;
                }
            }
        }
        
        // Mise à jour des totaux
        totalDistributed += fees.amount;
        fees.amount = 0;
        fees.lastDistribution = block.timestamp;
        lastDistributionTime = block.timestamp;
        
        emit DistributionExecuted(distributionId, totalDistributed, block.timestamp);
    }
    
    // Distribution de récompenses de performance
    function distributePerformanceReward(
        address recipient,
        uint256 amount,
        string memory performanceMetric
    ) external onlyRole(DISTRIBUTOR) nonReentrant {
        require(recipient != address(0), "Invalid recipient");
        require(amount > 0, "Amount must be > 0");
        
        IERC20 token = IERC20(feeToken);
        require(
            token.balanceOf(address(this)) >= amount,
            "Insufficient balance"
        );
        
        token.transfer(recipient, amount);
        
        // Enregistrement de la récompense
        performanceRewards[recipient].push(PerformanceReward({
            recipient: recipient,
            rewardAmount: amount,
            timestamp: block.timestamp,
            performanceMetric: performanceMetric
        }));
        
        emit PerformanceRewardDistributed(
            recipient,
            amount,
            performanceMetric,
            block.timestamp
        );
    }
    
    // Ajout d'un nouveau pool de distribution
    function addDistributionPool(
        address recipient,
        uint256 sharePercentage,
        string memory description
    ) external onlyRole(DEFAULT_ADMIN_ROLE) {
        require(recipient != address(0), "Invalid recipient");
        require(sharePercentage > 0 && sharePercentage <= 10000, "Invalid share");
        
        // Vérifier que le total des parts ne dépasse pas 100%
        uint256 totalShares = sharePercentage;
        for (uint256 i = 0; i < distributionPools.length; i++) {
            if (distributionPools[i].isActive) {
                totalShares += distributionPools[i].sharePercentage;
            }
        }
        
        require(totalShares <= 10000, "Total shares exceed 100%");
        
        uint256 poolId = distributionPools.length;
        
        distributionPools.push(DistributionPool({
            recipient: recipient,
            sharePercentage: sharePercentage,
            description: description,
            isActive: true
        }));
        
        emit PoolAdded(poolId, recipient, sharePercentage, description);
    }
    
    // Mise à jour d'un pool existant
    function updateDistributionPool(
        uint256 poolId,
        address newRecipient,
        uint256 newSharePercentage,
        bool isActive
    ) external onlyRole(DEFAULT_ADMIN_ROLE) {
        require(poolId < distributionPools.length, "Invalid pool ID");
        
        DistributionPool storage pool = distributionPools[poolId];
        
        if (newRecipient != address(0)) {
            pool.recipient = newRecipient;
        }
        
        if (newSharePercentage > 0) {
            // Vérifier que le nouveau total ne dépasse pas 100%
            uint256 totalShares = newSharePercentage;
            for (uint256 i = 0; i < distributionPools.length; i++) {
                if (i != poolId && distributionPools[i].isActive) {
                    totalShares += distributionPools[i].sharePercentage;
                }
            }
            
            require(totalShares <= 10000, "Total shares exceed 100%");
            pool.sharePercentage = newSharePercentage;
        }
        
        pool.isActive = isActive;
    }
    
    // Distribution manuelle (en cas d'urgence)
    function emergencyDistribution(
        address recipient,
        uint256 amount
    ) external onlyRole(DEFAULT_ADMIN_ROLE) nonReentrant {
        require(recipient != address(0), "Invalid recipient");
        require(amount > 0, "Amount must be > 0");
        
        IERC20 token = IERC20(feeToken);
        require(
            token.balanceOf(address(this)) >= amount,
            "Insufficient balance"
        );
        
        token.transfer(recipient, amount);
        
        // Ajuster les frais accumulés
        AccruedFees storage fees = accruedFees[feeToken];
        if (fees.amount >= amount) {
            fees.amount -= amount;
        } else {
            fees.amount = 0;
        }
    }
    
    // Calcul des prochaines distributions
    function calculateNextDistribution() external view returns (
        uint256 nextDistributionTime,
        uint256 estimatedAmount,
        DistributionPool[] memory activePools
    ) {
        nextDistributionTime = lastDistributionTime + distributionInterval;
        
        AccruedFees memory fees = accruedFees[feeToken];
        estimatedAmount = fees.amount;
        
        // Compter les pools actifs
        uint256 activeCount = 0;
        for (uint256 i = 0; i < distributionPools.length; i++) {
            if (distributionPools[i].isActive && distributionPools[i].recipient != address(0)) {
                activeCount++;
            }
        }
        
        // Collecter les pools actifs
        activePools = new DistributionPool[](activeCount);
        uint256 index = 0;
        
        for (uint256 i = 0; i < distributionPools.length; i++) {
            if (distributionPools[i].isActive && distributionPools[i].recipient != address(0)) {
                activePools[index] = distributionPools[i];
                index++;
            }
        }
        
        return (nextDistributionTime, estimatedAmount, activePools);
    }
    
    // Récupération des statistiques de distribution
    function getDistributionStats() external view returns (
        uint256 totalAccrued,
        uint256 totalDistributedAmount,
        uint256 pendingDistribution,
        uint256 poolCount,
        uint256 activePoolCount
    ) {
        AccruedFees memory fees = accruedFees[feeToken];
        
        uint256 activeCount = 0;
        for (uint256 i = 0; i < distributionPools.length; i++) {
            if (distributionPools[i].isActive) {
                activeCount++;
            }
        }
        
        return (
            fees.amount,
            totalDistributed,
            fees.amount,
            distributionPools.length,
            activeCount
        );
    }
    
    // Récupération des récompenses de performance d'un utilisateur
    function getUserPerformanceRewards(address user) 
        external 
        view 
        returns (PerformanceReward[] memory) 
    {
        return performanceRewards[user];
    }
    
    // Configuration
    function setDistributionInterval(uint256 newInterval) external onlyRole(DEFAULT_ADMIN_ROLE) {
        require(newInterval >= 1 days, "Interval too short");
        require(newInterval <= 30 days, "Interval too long");
        
        distributionInterval = newInterval;
    }
    
    function setFeeToken(address newFeeToken) external onlyRole(DEFAULT_ADMIN_ROLE) {
        require(newFeeToken != address(0), "Invalid token");
        feeToken = newFeeToken;
    }
    
    // Récupération des pools de distribution
    function getAllPools() external view returns (DistributionPool[] memory) {
        return distributionPools;
    }
    
    // Fonction pour calculer la part d'un pool
    function calculatePoolShare(uint256 poolId, uint256 totalAmount) 
        external 
        view 
        returns (uint256) 
    {
        require(poolId < distributionPools.length, "Invalid pool ID");
        
        DistributionPool memory pool = distributionPools[poolId];
        if (!pool.isActive) {
            return 0;
        }
        
        return (totalAmount * pool.sharePercentage) / 10000;
    }
}