// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/utils/ReentrancyGuard.sol";
import "@openzeppelin/contracts/utils/Pausable.sol";
import "@openzeppelin/contracts/access/AccessControl.sol";

contract DecentralizedGuaranteeFund is ReentrancyGuard, AccessControl {
    // Structures de données
    struct FundTier {
        uint256 tierId;
        string name;
        uint256 minDeposit;
        uint256 maxDeposit;
        uint256 targetAPY;
        uint256 riskLevel; // 0-1000
        uint256 allocationPercentage;
        bool isActive;
    }
    
    struct InvestorPosition {
        address investor;
        uint256 tierId;
        uint256 depositedAmount;
        uint256 shares;
        uint256 entryTime;
        uint256 lastClaimTime;
        uint256 claimedRewards;
        uint256 lockedUntil;
    }
    
    struct LossCoverage {
        uint256 coverageId;
        uint256 loanId;
        uint256 lossAmount;
        uint256 coveredAmount;
        uint256 coverageTime;
        address[] coveringInvestors;
        uint256[] coveringAmounts;
    }
    
    // Variables d'état
    FundTier[] public fundTiers;
    mapping(address => InvestorPosition[]) public investorPositions;
    mapping(uint256 => LossCoverage) public lossCoverages;
    
    uint256 public totalFundAssets;
    uint256 public totalCoveredLosses;
    uint256 public totalInvestorRewards;
    uint256 public coverageReserveRatio = 2000; // 20%
    uint256 public minLockupPeriod = 30 days;
    
    address public loanPool;
    IERC20 public fundToken;
    
    // Événements
    event TierCreated(
        uint256 indexed tierId,
        string name,
        uint256 minDeposit,
        uint256 targetAPY,
        uint256 riskLevel
    );
    
    event DepositMade(
        address indexed investor,
        uint256 indexed tierId,
        uint256 amount,
        uint256 shares,
        uint256 lockedUntil
    );
    
    event LossCovered(
        uint256 indexed coverageId,
        uint256 indexed loanId,
        uint256 lossAmount,
        uint256 coveredAmount,
        uint256 timestamp
    );
    
    event RewardClaimed(
        address indexed investor,
        uint256 amount,
        uint256 timestamp
    );
    
    event WithdrawalMade(
        address indexed investor,
        uint256 tierId,
        uint256 amount,
        uint256 timestamp
    );
    
    // Rôles
    bytes32 public constant FUND_MANAGER = keccak256("FUND_MANAGER");
    bytes32 public constant RISK_MANAGER = keccak256("RISK_MANAGER");
    
    constructor(address _loanPool, address _fundToken) {
        loanPool = _loanPool;
        fundToken = IERC20(_fundToken);
        
        _grantRole(DEFAULT_ADMIN_ROLE, msg.sender);
        _grantRole(FUND_MANAGER, msg.sender);
        _grantRole(RISK_MANAGER, msg.sender);
        
        // Initialisation des tiers par défaut
        _initializeTiers();
    }
    
    // Initialisation des tiers
    function _initializeTiers() private {
        // Tier 1: Bas risque, faible rendement
        fundTiers.push(FundTier({
            tierId: 0,
            name: "Conservative",
            minDeposit: 1000 * 1e18,
            maxDeposit: 100000 * 1e18,
            targetAPY: 500, // 5%
            riskLevel: 200,
            allocationPercentage: 4000, // 40%
            isActive: true
        }));
        
        // Tier 2: Risque moyen, rendement moyen
        fundTiers.push(FundTier({
            tierId: 1,
            name: "Balanced",
            minDeposit: 5000 * 1e18,
            maxDeposit: 500000 * 1e18,
            targetAPY: 1000, // 10%
            riskLevel: 500,
            allocationPercentage: 3000, // 30%
            isActive: true
        }));
        
        // Tier 3: Haut risque, haut rendement
        fundTiers.push(FundTier({
            tierId: 2,
            name: "Growth",
            minDeposit: 10000 * 1e18,
            maxDeposit: 1000000 * 1e18,
            targetAPY: 1500, // 15%
            riskLevel: 800,
            allocationPercentage: 2000, // 20%
            isActive: true
        }));
        
        // Tier 4: Très haut risque, très haut rendement
        fundTiers.push(FundTier({
            tierId: 3,
            name: "Aggressive",
            minDeposit: 50000 * 1e18,
            maxDeposit: 5000000 * 1e18,
            targetAPY: 2500, // 25%
            riskLevel: 950,
            allocationPercentage: 1000, // 10%
            isActive: true
        }));
    }
    
    // Dépôt dans le fonds
    function deposit(uint256 tierId, uint256 amount) external nonReentrant {
        require(tierId < fundTiers.length, "Invalid tier");
        require(fundTiers[tierId].isActive, "Tier inactive");
        
        FundTier memory tier = fundTiers[tierId];
        require(amount >= tier.minDeposit, "Below minimum");
        require(amount <= tier.maxDeposit, "Above maximum");
        
        // Vérifier les allocations disponibles
        uint256 tierAssets = _getTierAssets(tierId);
        uint256 maxTierAllocation = (totalFundAssets * tier.allocationPercentage) / 10000;
        
        require(
            tierAssets + amount <= maxTierAllocation,
            "Tier allocation exceeded"
        );
        
        // Transfert des tokens
        require(
            fundToken.transferFrom(msg.sender, address(this), amount),
            "Transfer failed"
        );
        
        // Calcul des parts
        uint256 shares = _calculateShares(amount, tierId);
        
        // Création de la position
        investorPositions[msg.sender].push(InvestorPosition({
            investor: msg.sender,
            tierId: tierId,
            depositedAmount: amount,
            shares: shares,
            entryTime: block.timestamp,
            lastClaimTime: block.timestamp,
            claimedRewards: 0,
            lockedUntil: block.timestamp + minLockupPeriod
        }));
        
        // Mise à jour des totaux
        totalFundAssets += amount;
        
        emit DepositMade(
            msg.sender,
            tierId,
            amount,
            shares,
            block.timestamp + minLockupPeriod
        );
    }
    
    // Couverture d'une perte
    function coverLoss(
        uint256 loanId,
        uint256 lossAmount,
        uint256 trancheId
    ) external onlyRole(RISK_MANAGER) nonReentrant returns (uint256) {
        require(lossAmount > 0, "Invalid loss amount");
        require(lossAmount <= _getCoverableAmount(), "Insufficient coverage capacity");
        
        // Détermination du montant à couvrir
        uint256 coveredAmount = (lossAmount * coverageReserveRatio) / 10000;
        
        // Allocation de la couverture par tier
        (uint256[] memory tierAllocations, address[][] memory coveringInvestors) = 
            _allocateCoverage(coveredAmount, trancheId);
        
        // Création de l'enregistrement de couverture
        uint256 coverageId = _createCoverageRecord(
            loanId,
            lossAmount,
            coveredAmount,
            coveringInvestors,
            tierAllocations
        );
        
        // Déduction des montants des positions des investisseurs
        _deductFromInvestors(coveringInvestors, tierAllocations);
        
        // Mise à jour des totaux
        totalCoveredLosses += coveredAmount;
        totalFundAssets -= coveredAmount;
        
        emit LossCovered(coverageId, loanId, lossAmount, coveredAmount, block.timestamp);
        
        return coveredAmount;
    }
    
    // Réclamation des récompenses
    function claimRewards(uint256 positionIndex) external nonReentrant {
        require(positionIndex < investorPositions[msg.sender].length, "Invalid position");
        
        InvestorPosition storage position = investorPositions[msg.sender][positionIndex];
        require(block.timestamp >= position.entryTime + 7 days, "Too early to claim");
        
        // Calcul des récompenses accumulées
        uint256 rewards = _calculateAccruedRewards(position);
        require(rewards > 0, "No rewards available");
        
        // Vérifier que le fonds a suffisamment de liquidités
        require(rewards <= _getAvailableRewards(), "Insufficient reward liquidity");
        
        // Transfert des récompenses
        require(fundToken.transfer(msg.sender, rewards), "Transfer failed");
        
        // Mise à jour de la position
        position.lastClaimTime = block.timestamp;
        position.claimedRewards += rewards;
        totalInvestorRewards += rewards;
        
        emit RewardClaimed(msg.sender, rewards, block.timestamp);
    }
    
    // Retrait du capital
    function withdraw(uint256 positionIndex, uint256 amount) external nonReentrant {
        require(positionIndex < investorPositions[msg.sender].length, "Invalid position");
        
        InvestorPosition storage position = investorPositions[msg.sender][positionIndex];
        
        require(block.timestamp >= position.lockedUntil, "Still locked");
        require(amount <= position.depositedAmount, "Exceeds deposited amount");
        require(amount <= _getWithdrawableAmount(position), "Exceeds withdrawable amount");
        
        // Calcul des parts à retirer
        uint256 sharesToWithdraw = (position.shares * amount) / position.depositedAmount;
        
        // Transfert des tokens
        require(fundToken.transfer(msg.sender, amount), "Transfer failed");
        
        // Mise à jour de la position
        position.depositedAmount -= amount;
        position.shares -= sharesToWithdraw;
        totalFundAssets -= amount;
        
        // Si la position est vide, la supprimer
        if (position.depositedAmount == 0) {
            _removePosition(msg.sender, positionIndex);
        }
        
        emit WithdrawalMade(msg.sender, position.tierId, amount, block.timestamp);
    }
    
    // Création d'un nouveau tier
    function createTier(
        string memory name,
        uint256 minDeposit,
        uint256 maxDeposit,
        uint256 targetAPY,
        uint256 riskLevel,
        uint256 allocationPercentage
    ) external onlyRole(FUND_MANAGER) {
        require(allocationPercentage <= 10000, "Invalid allocation");
        
        uint256 tierId = fundTiers.length;
        
        fundTiers.push(FundTier({
            tierId: tierId,
            name: name,
            minDeposit: minDeposit,
            maxDeposit: maxDeposit,
            targetAPY: targetAPY,
            riskLevel: riskLevel,
            allocationPercentage: allocationPercentage,
            isActive: true
        }));
        
        emit TierCreated(tierId, name, minDeposit, targetAPY, riskLevel);
    }
    
    // Fonctions internes
    function _calculateShares(uint256 amount, uint256 tierId) private view returns (uint256) {
        // Les parts sont proportionnelles au dépôt ajusté par le risque du tier
        uint256 riskFactor = fundTiers[tierId].riskLevel;
        return (amount * (1000 + riskFactor)) / 1000;
    }
    
    function _getTierAssets(uint256 tierId) private view returns (uint256) {
        uint256 total = 0;
        // À implémenter: calculer le total des actifs dans ce tier
        return total;
    }
    
    function _getCoverableAmount() private view returns (uint256) {
        return (totalFundAssets * coverageReserveRatio) / 10000;
    }
    
    function _allocateCoverage(
        uint256 coveredAmount,
        uint256 trancheId
    ) private returns (uint256[] memory, address[][] memory) {
        // Logique d'allocation complexe basée sur les tiers et le risque
        // À implémenter: algorithme d'allocation optimale
        
        uint256[] memory tierAllocations = new uint256[](fundTiers.length);
        address[][] memory coveringInvestors = new address[][](fundTiers.length);
        
        // Pour l'instant, répartition proportionnelle simple
        for (uint256 i = 0; i < fundTiers.length; i++) {
            tierAllocations[i] = (coveredAmount * fundTiers[i].allocationPercentage) / 10000;
            coveringInvestors[i] = _selectInvestorsForCoverage(i, tierAllocations[i]);
        }
        
        return (tierAllocations, coveringInvestors);
    }
    
    function _createCoverageRecord(
        uint256 loanId,
        uint256 lossAmount,
        uint256 coveredAmount,
        address[][] memory coveringInvestors,
        uint256[] memory tierAllocations
    ) private returns (uint256) {
        uint256 coverageId = uint256(keccak256(abi.encodePacked(
            loanId,
            block.timestamp,
            lossAmount
        )));
        
        // Aplatir la liste des investisseurs
        address[] memory allInvestors;
        uint256[] memory allAmounts;
        
        // À implémenter: construction des listes aplaties
        
        lossCoverages[coverageId] = LossCoverage({
            coverageId: coverageId,
            loanId: loanId,
            lossAmount: lossAmount,
            coveredAmount: coveredAmount,
            coverageTime: block.timestamp,
            coveringInvestors: allInvestors,
            coveringAmounts: allAmounts
        });
        
        return coverageId;
    }
    
    function _deductFromInvestors(
        address[][] memory coveringInvestors,
        uint256[] memory tierAllocations
    ) private {
        // À implémenter: déduction des montants des positions des investisseurs
    }
    
    function _calculateAccruedRewards(InvestorPosition memory position) private view returns (uint256) {
        FundTier memory tier = fundTiers[position.tierId];
        
        uint256 timeSinceLastClaim = block.timestamp - position.lastClaimTime;
        uint256 annualReward = (position.depositedAmount * tier.targetAPY) / 10000;
        uint256 accruedReward = (annualReward * timeSinceLastClaim) / 365 days;
        
        return accruedReward;
    }
    
    function _getAvailableRewards() private view returns (uint256) {
        // Les récompenses sont payées à partir des revenus du fonds
        return fundToken.balanceOf(address(this)) - totalFundAssets;
    }
    
    function _getWithdrawableAmount(InvestorPosition memory position) private view returns (uint256) {
        // Vérifier les pertes couvertes par cette position
        uint256 coveredLosses = _getCoveredLossesForPosition(position);
        
        // Le montant retirable est le dépôt moins les pertes couvertes
        if (position.depositedAmount > coveredLosses) {
            return position.depositedAmount - coveredLosses;
        } else {
            return 0;
        }
    }
    
    function _getCoveredLossesForPosition(InvestorPosition memory position) private view returns (uint256) {
        // À implémenter: calculer les pertes couvertes par cette position
        return 0;
    }
    
    function _removePosition(address investor, uint256 positionIndex) private {
        uint256 lastIndex = investorPositions[investor].length - 1;
        
        if (positionIndex != lastIndex) {
            investorPositions[investor][positionIndex] = investorPositions[investor][lastIndex];
        }
        
        investorPositions[investor].pop();
    }
    
    function _selectInvestorsForCoverage(uint256 tierId, uint256 amount) private view returns (address[] memory) {
        // À implémenter: sélectionner les investisseurs pour la couverture
        return new address[](0);
    }
    
    // Getters
    function getInvestorPositions(address investor) external view returns (InvestorPosition[] memory) {
        return investorPositions[investor];
    }
    
    function getTierDetails(uint256 tierId) external view returns (
        string memory name,
        uint256 minDeposit,
        uint256 maxDeposit,
        uint256 targetAPY,
        uint256 riskLevel,
        uint256 allocationPercentage,
        bool isActive
    ) {
        require(tierId < fundTiers.length, "Invalid tier");
        
        FundTier memory tier = fundTiers[tierId];
        return (
            tier.name,
            tier.minDeposit,
            tier.maxDeposit,
            tier.targetAPY,
            tier.riskLevel,
            tier.allocationPercentage,
            tier.isActive
        );
    }
    
    function getFundStats() external view returns (
        uint256 totalAssets,
        uint256 coveredLosses,
        uint256 investorRewards,
        uint256 coverageCapacity,
        uint256 availableRewards
    ) {
        return (
            totalFundAssets,
            totalCoveredLosses,
            totalInvestorRewards,
            _getCoverableAmount(),
            _getAvailableRewards()
        );
    }
    
    function calculateProjectedAPY(address investor, uint256 positionIndex) external view returns (uint256) {
        require(positionIndex < investorPositions[investor].length, "Invalid position");
        
        InvestorPosition memory position = investorPositions[investor][positionIndex];
        FundTier memory tier = fundTiers[position.tierId];
        
        // APY projeté basé sur le tier, ajusté par la performance du fonds
        uint256 baseAPY = tier.targetAPY;
        uint256 performanceAdjustment = _calculatePerformanceAdjustment();
        
        return baseAPY + performanceAdjustment;
    }
    
    function _calculatePerformanceAdjustment() private view returns (uint256) {
        // À implémenter: calcul de l'ajustement basé sur la performance
        return 0;
    }
}