// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/utils/ReentrancyGuard.sol";
import "../security/AccessController.sol";

contract InsuranceModule is ReentrancyGuard {
    // Structures de données
    struct InsurancePolicy {
        uint256 policyId;
        uint256 loanId;
        address insured;
        uint256 coverageAmount;
        uint256 premiumAmount;
        uint256 coveragePercentage;
        uint256 startTime;
        uint256 endTime;
        PolicyStatus status;
        address insurer;
        uint256 claimAmount;
        uint256 claimTime;
    }
    
    struct InsurerPool {
        address insurer;
        uint256 totalCapital;
        uint256 allocatedCapital;
        uint256 availableCapital;
        uint256 totalPremiums;
        uint256 totalClaims;
        uint256 performanceScore;
        bool isActive;
    }
    
    // Types et statuts
    enum PolicyStatus { ACTIVE, EXPIRED, CLAIMED, CANCELLED }
    enum CoverageType { FULL, PARTIAL, EXCESS_LOSS }
    
    // Variables d'état
    mapping(uint256 => InsurancePolicy) public policies;
    mapping(address => uint256[]) public userPolicies;
    mapping(address => InsurerPool) public insurerPools;
    
    uint256 public totalPolicies;
    uint256 public totalCoverage;
    uint256 public totalPremiums;
    uint256 public totalClaimsPaid;
    
    // Paramètres d'assurance
    uint256 public basePremiumRate = 200; // 2%
    uint256 public riskMultiplier = 1000; // 10x
    uint256 public minCoveragePercentage = 5000; // 50%
    uint256 public maxCoveragePercentage = 9000; // 90%
    uint256 public insurerCapitalRequirement = 10000 * 1e18; // 10,000 tokens
    
    // Contrats liés
    AccessController public accessController;
    address public loanPool;
    
    // Événements
    event PolicyCreated(
        uint256 indexed policyId,
        uint256 indexed loanId,
        address indexed insured,
        uint256 coverageAmount,
        uint256 premiumAmount,
        uint256 coveragePercentage
    );
    
    event ClaimFiled(
        uint256 indexed policyId,
        uint256 indexed loanId,
        address claimant,
        uint256 claimAmount,
        uint256 timestamp
    );
    
    event ClaimPaid(
        uint256 indexed policyId,
        address insurer,
        uint256 payoutAmount,
        uint256 timestamp
    );
    
    event InsurerRegistered(
        address indexed insurer,
        uint256 capitalDeposited,
        uint256 timestamp
    );
    
    // Modificateurs
    modifier onlyLoanPool() {
        require(msg.sender == loanPool, "Only LoanPool");
        _;
    }
    
    modifier onlyInsurer() {
        require(insurerPools[msg.sender].isActive, "Not active insurer");
        _;
    }
    
    constructor(address _accessController) {
        accessController = AccessController(_accessController);
    }
    
    // Configuration du LoanPool
    function setLoanPool(address _loanPool) external {
        require(
            accessController.hasRole(msg.sender, "ADMIN"),
            "Not authorized"
        );
        loanPool = _loanPool;
    }
    
    // Vérification d'éligibilité pour l'assurance
    function checkEligibility(
        uint256 loanId,
        uint256 riskScore,
        uint256 loanAmount
    ) public view returns (bool eligible, uint256 premium, uint256 coverage) {
        // Vérifications de base
        if (riskScore > 800) { // Risque trop élevé
            return (false, 0, 0);
        }
        
        if (loanAmount > 1000000 * 1e18) { // Montant trop élevé
            return (false, 0, 0);
        }
        
        // Calcul de la prime
        premium = _calculatePremium(riskScore, loanAmount);
        
        // Pourcentage de couverture basé sur le risque
        coverage = _calculateCoveragePercentage(riskScore);
        
        // Vérifier qu'il y a assez de capital d'assurance disponible
        uint256 requiredCapital = (loanAmount * coverage) / 10000;
        if (_getAvailableInsuranceCapital() < requiredCapital) {
            return (false, 0, 0);
        }
        
        return (true, premium, coverage);
    }
    
    // Création d'une police d'assurance
    function createPolicy(
        uint256 loanId,
        address borrower,
        uint256 loanAmount,
        uint256 riskScore,
        uint256 duration
    ) external onlyLoanPool nonReentrant returns (uint256) {
        (bool eligible, uint256 premium, uint256 coverage) = 
            checkEligibility(loanId, riskScore, loanAmount);
        
        require(eligible, "Not eligible for insurance");
        
        // Allocation à un pool d'assureurs
        address insurer = _allocateToInsurer(loanAmount, coverage, riskScore);
        require(insurer != address(0), "No insurer available");
        
        // Création de la police
        uint256 policyId = ++totalPolicies;
        uint256 coverageAmount = (loanAmount * coverage) / 10000;
        
        policies[policyId] = InsurancePolicy({
            policyId: policyId,
            loanId: loanId,
            insured: borrower,
            coverageAmount: coverageAmount,
            premiumAmount: premium,
            coveragePercentage: coverage,
            startTime: block.timestamp,
            endTime: block.timestamp + duration,
            status: PolicyStatus.ACTIVE,
            insurer: insurer,
            claimAmount: 0,
            claimTime: 0
        });
        
        userPolicies[borrower].push(policyId);
        
        // Mise à jour des statistiques
        totalCoverage += coverageAmount;
        totalPremiums += premium;
        
        // Allocation du capital de l'assureur
        insurerPools[insurer].allocatedCapital += coverageAmount;
        insurerPools[insurer].availableCapital -= coverageAmount;
        insurerPools[insurer].totalPremiums += premium;
        
        // Transfert de la prime (doit être approuvé au préalable)
        IERC20 paymentToken = IERC20(_getPaymentToken());
        require(
            paymentToken.transferFrom(borrower, address(this), premium),
            "Premium transfer failed"
        );
        
        // Distribution de la prime (80% à l'assureur, 20% à la réserve)
        uint256 insurerShare = (premium * 8000) / 10000;
        uint256 reserveShare = premium - insurerShare;
        
        paymentToken.transfer(insurer, insurerShare);
        _addToReserve(reserveShare);
        
        emit PolicyCreated(
            policyId,
            loanId,
            borrower,
            coverageAmount,
            premium,
            coverage
        );
        
        return policyId;
    }
    
    // Traitement d'une réclamation
    function processClaim(
        uint256 loanId,
        uint256 loanAmount,
        uint256 coveragePercentage
    ) external onlyLoanPool nonReentrant returns (uint256) {
        // Trouver la police correspondante
        uint256 policyId = _findPolicyForLoan(loanId);
        require(policyId > 0, "No active policy found");
        
        InsurancePolicy storage policy = policies[policyId];
        require(policy.status == PolicyStatus.ACTIVE, "Policy not active");
        require(block.timestamp <= policy.endTime, "Policy expired");
        
        // Calcul du montant de la réclamation
        uint256 claimAmount = (loanAmount * policy.coveragePercentage) / 10000;
        
        // Vérifier que l'assureur a suffisamment de capital
        require(
            insurerPools[policy.insurer].availableCapital >= claimAmount,
            "Insurer insufficient capital"
        );
        
        // Mise à jour de la police
        policy.status = PolicyStatus.CLAIMED;
        policy.claimAmount = claimAmount;
        policy.claimTime = block.timestamp;
        
        // Paiement de la réclamation
        IERC20 paymentToken = IERC20(_getPaymentToken());
        require(
            paymentToken.transferFrom(policy.insurer, msg.sender, claimAmount),
            "Claim payment failed"
        );
        
        // Mise à jour des statistiques
        totalClaimsPaid += claimAmount;
        insurerPools[policy.insurer].totalClaims += claimAmount;
        
        // Ajustement du score de performance de l'assureur
        _updateInsurerPerformance(policy.insurer, claimAmount);
        
        emit ClaimFiled(policyId, loanId, policy.insured, claimAmount, block.timestamp);
        emit ClaimPaid(policyId, policy.insurer, claimAmount, block.timestamp);
        
        return claimAmount;
    }
    
    // Enregistrement d'un nouvel assureur
    function registerAsInsurer(uint256 capitalAmount) external nonReentrant {
        require(capitalAmount >= insurerCapitalRequirement, "Insufficient capital");
        
        IERC20 paymentToken = IERC20(_getPaymentToken());
        require(
            paymentToken.transferFrom(msg.sender, address(this), capitalAmount),
            "Capital transfer failed"
        );
        
        insurerPools[msg.sender] = InsurerPool({
            insurer: msg.sender,
            totalCapital: capitalAmount,
            allocatedCapital: 0,
            availableCapital: capitalAmount,
            totalPremiums: 0,
            totalClaims: 0,
            performanceScore: 1000, // Score initial
            isActive: true
        });
        
        emit InsurerRegistered(msg.sender, capitalAmount, block.timestamp);
    }
    
    // Retrait de capital par un assureur
    function withdrawCapital(uint256 amount) external onlyInsurer nonReentrant {
        InsurerPool storage pool = insurerPools[msg.sender];
        
        require(amount <= pool.availableCapital, "Insufficient available capital");
        require(
            pool.totalCapital - amount >= insurerCapitalRequirement,
            "Below minimum requirement"
        );
        
        pool.totalCapital -= amount;
        pool.availableCapital -= amount;
        
        IERC20 paymentToken = IERC20(_getPaymentToken());
        paymentToken.transfer(msg.sender, amount);
    }
    
    // Réassurance: transfert de risque à d'autres assureurs
    function reinsurePolicy(uint256 policyId, uint256 percentage) external onlyInsurer {
        require(percentage > 0 && percentage <= 10000, "Invalid percentage");
        
        InsurancePolicy storage policy = policies[policyId];
        require(policy.insurer == msg.sender, "Not policy insurer");
        require(policy.status == PolicyStatus.ACTIVE, "Policy not active");
        
        // Trouver d'autres assureurs pour le risque
        address[] memory reinsurers = _findReinsurers(
            policy.coverageAmount,
            percentage,
            policy.insured
        );
        
        require(reinsurers.length > 0, "No reinsurers found");
        
        // Répartir le risque
        uint256 reinsuredAmount = (policy.coverageAmount * percentage) / 10000;
        uint256 perReinsurer = reinsuredAmount / reinsurers.length;
        
        for (uint256 i = 0; i < reinsurers.length; i++) {
            insurerPools[reinsurers[i]].allocatedCapital += perReinsurer;
            insurerPools[reinsurers[i]].availableCapital -= perReinsurer;
            
            // Ajuster le capital de l'assureur original
            insurerPools[msg.sender].allocatedCapital -= perReinsurer;
            insurerPools[msg.sender].availableCapital += perReinsurer;
        }
    }
    
    // Fonctions internes
    function _calculatePremium(uint256 riskScore, uint256 loanAmount) private view returns (uint256) {
        uint256 basePremium = (loanAmount * basePremiumRate) / 10000;
        
        // Ajustement basé sur le risque
        uint256 riskFactor;
        if (riskScore < 300) {
            riskFactor = 500; // 0.5x
        } else if (riskScore < 500) {
            riskFactor = 750; // 0.75x
        } else if (riskScore < 700) {
            riskFactor = 1000; // 1x
        } else {
            riskFactor = 1500; // 1.5x
        }
        
        return (basePremium * riskFactor) / 1000;
    }
    
    function _calculateCoveragePercentage(uint256 riskScore) private view returns (uint256) {
        if (riskScore < 300) {
            return maxCoveragePercentage; // 90%
        } else if (riskScore < 500) {
            return 8000; // 80%
        } else if (riskScore < 700) {
            return 7000; // 70%
        } else {
            return minCoveragePercentage; // 50%
        }
    }
    
    function _allocateToInsurer(
        uint256 loanAmount,
        uint256 coveragePercentage,
        uint256 riskScore
    ) private returns (address) {
        uint256 requiredCapital = (loanAmount * coveragePercentage) / 10000;
        
        // Trouver l'assureur avec le meilleur score et assez de capital
        address bestInsurer = address(0);
        uint256 bestScore = 0;
        
        // Note: Dans une implémentation réelle, il faudrait un mapping des assureurs
        // Pour cette démo, nous utilisons une approche simplifiée
        
        // Vérifier les assureurs enregistrés
        // À implémenter: logique de sélection basée sur le score de performance
        
        return bestInsurer != address(0) ? bestInsurer : address(this); // Fallback au contrat
    }
    
    function _getAvailableInsuranceCapital() private view returns (uint256) {
        uint256 total = 0;
        // À implémenter: sommer le capital disponible de tous les assureurs
        return total;
    }
    
    function _findPolicyForLoan(uint256 loanId) private view returns (uint256) {
        // Recherche linéaire (à optimiser pour la production)
        for (uint256 i = 1; i <= totalPolicies; i++) {
            if (policies[i].loanId == loanId && policies[i].status == PolicyStatus.ACTIVE) {
                return i;
            }
        }
        return 0;
    }
    
    function _updateInsurerPerformance(address insurer, uint256 claimAmount) private {
        InsurerPool storage pool = insurerPools[insurer];
        
        // Calcul du ratio sinistres/primes
        uint256 lossRatio = pool.totalPremiums > 0 ? 
            (pool.totalClaims * 10000) / pool.totalPremiums : 0;
        
        // Ajustement du score
        if (lossRatio < 3000) { // <30%
            pool.performanceScore = pool.performanceScore * 105 / 100;
        } else if (lossRatio > 8000) { // >80%
            pool.performanceScore = pool.performanceScore * 95 / 100;
        }
        
        if (pool.performanceScore < 500) {
            pool.isActive = false; // Désactiver les assureurs peu performants
        }
    }
    
    function _addToReserve(uint256 amount) private {
        // À implémenter: ajout à la réserve de stabilité
    }
    
    function _getPaymentToken() private view returns (address) {
        // À implémenter: récupérer le token de paiement depuis le LoanPool
        return 0xA0b86991c6218b36c1d19D4a2e9Eb0cE3606eB48; // USDC par défaut
    }
    
    function _findReinsurers(
        uint256 coverageAmount,
        uint256 percentage,
        address insured
    ) private view returns (address[] memory) {
        // À implémenter: logique de recherche de réassureurs
        return new address[](0);
    }
    
    // Getters
    function getUserPolicies(address user) external view returns (uint256[] memory) {
        return userPolicies[user];
    }
    
    function getPolicyDetails(uint256 policyId) external view returns (
        uint256 loanId,
        address insured,
        uint256 coverageAmount,
        uint256 premiumAmount,
        uint256 coveragePercentage,
        PolicyStatus status,
        address insurer
    ) {
        InsurancePolicy memory policy = policies[policyId];
        return (
            policy.loanId,
            policy.insured,
            policy.coverageAmount,
            policy.premiumAmount,
            policy.coveragePercentage,
            policy.status,
            policy.insurer
        );
    }
    
    function getInsurerStats(address insurer) external view returns (
        uint256 totalCapital,
        uint256 allocatedCapital,
        uint256 availableCapital,
        uint256 premiumsAmount,
        uint256 totalClaims,
        uint256 performanceScore,
        bool isActive
    ) {
        InsurerPool memory pool = insurerPools[insurer];
        return (
            pool.totalCapital,
            pool.allocatedCapital,
            pool.availableCapital,
            pool.premiumsAmount,
            pool.totalClaims,
            pool.performanceScore,
            pool.isActive
        );
    }
}