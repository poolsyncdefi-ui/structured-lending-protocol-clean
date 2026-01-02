// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import "@openzeppelin/contracts/access/Ownable.sol";
import "../interfaces/ILoanPool.sol";

/**
 * @title CriteriaFilter - Filtre dynamique pour les pools de prêt
 * @notice Permet aux prêteurs de filtrer les pools selon leurs préférences
 */
contract CriteriaFilter is Ownable {
    
    struct LenderPreferences {
        string[] preferredRegions;
        bool ecologicalOnly;
        string[] activityDomains;
        uint256 minInterestRate;     // en points de base
        uint256 maxRiskScore;        // 1-10
        uint256 minInvestmentAmount;
        uint256 maxInvestmentAmount;
        uint256 preferredDurationMin;
        uint256 preferredDurationMax;
        uint256 createdAt;
        uint256 lastUpdated;
    }
    
    // Référence au contrat principal
    ILoanPool public loanPool;
    
    // Stockage des préférences
    mapping(address => LenderPreferences) public preferences;
    
    // Mappings pour l'indexation
    mapping(string => bool) public validRegions;
    mapping(string => bool) public validDomains;
    
    // Événements
    event PreferencesUpdated(address indexed lender);
    event PoolsFiltered(address indexed lender, uint256[] poolIds);
    
    constructor(address _loanPool) Ownable(msg.sender) {
        loanPool = ILoanPool(_loanPool);
        
        // Initialisation des régions valides
        validRegions["Europe"] = true;
        validRegions["North America"] = true;
        validRegions["Asia"] = true;
        validRegions["Africa"] = true;
        validRegions["South America"] = true;
        
        // Initialisation des domaines valides
        validDomains["Renewable Energy"] = true;
        validDomains["Technology"] = true;
        validDomains["Agriculture"] = true;
        validDomains["Real Estate"] = true;
        validDomains["Manufacturing"] = true;
        validDomains["Education"] = true;
        validDomains["Healthcare"] = true;
    }
    
    /**
     * @notice Met à jour les préférences d'un prêteur
     */
    function updatePreferences(
        string[] memory regions,
        bool ecologicalOnly,
        string[] memory domains,
        uint256 minRate,
        uint256 maxRisk,
        uint256 minInvestment,
        uint256 maxInvestment,
        uint256 durationMin,
        uint256 durationMax
    ) external {
        // Validation des régions
        for (uint256 i = 0; i < regions.length; i++) {
            require(validRegions[regions[i]], "Invalid region");
        }
        
        // Validation des domaines
        for (uint256 i = 0; i < domains.length; i++) {
            require(validDomains[domains[i]], "Invalid domain");
        }
        
        // Validation des paramètres
        require(minRate <= 5000, "Min rate too high"); // Max 50%
        require(maxRisk <= 10, "Max risk invalid");
        require(minInvestment <= maxInvestment, "Invalid investment range");
        require(durationMin <= durationMax, "Invalid duration range");
        
        // Mise à jour des préférences
        preferences[msg.sender] = LenderPreferences({
            preferredRegions: regions,
            ecologicalOnly: ecologicalOnly,
            activityDomains: domains,
            minInterestRate: minRate,
            maxRiskScore: maxRisk,
            minInvestmentAmount: minInvestment,
            maxInvestmentAmount: maxInvestment,
            preferredDurationMin: durationMin,
            preferredDurationMax: durationMax,
            createdAt: block.timestamp,
            lastUpdated: block.timestamp
        });
        
        emit PreferencesUpdated(msg.sender);
    }
    
    /**
     * @notice Filtre les pools selon les préférences
     */
    function filterPools(
        string[] memory regions,
        bool ecologicalOnly,
        string[] memory domains,
        uint256 minRate,
        uint256 maxRisk
    ) external view returns (uint256[] memory) {
        // Cette fonction est appelée par LoanPool
        // Dans une implémentation réelle, on parcourrait tous les pools
        
        // Pour l'instant, retourne un tableau vide
        // L'implémentation complète nécessite l'accès à tous les pools
        uint256[] memory filtered = new uint256[](0);
        return filtered;
    }
    
    /**
     * @notice Filtre les pools pour un prêteur spécifique
     */
    function filterPoolsForLender(address lender) external view returns (uint256[] memory) {
        LenderPreferences memory prefs = preferences[lender];
        
        // Logique de filtrage simplifiée
        // Dans la vraie implémentation, il faudrait:
        // 1. Récupérer tous les pools actifs
        // 2. Appliquer chaque critère
        // 3. Trier par score de pertinence
        
        uint256[] memory result = new uint256[](0);
        emit PoolsFiltered(lender, result);
        
        return result;
    }
    
    /**
     * @notice Calcule un score de pertinence pour un pool
     */
    function calculateMatchScore(
        uint256 poolId,
        LenderPreferences memory prefs
    ) public view returns (uint256 score) {
        score = 0;
        
        // Récupération des données du pool
        ILoanPool.PoolData memory pool = loanPool.getPoolDetails(poolId);
        
        // 1. Critère Région (30 points max)
        for (uint256 i = 0; i < prefs.preferredRegions.length; i++) {
            if (keccak256(bytes(pool.region)) == keccak256(bytes(prefs.preferredRegions[i]))) {
                score += 30;
                break;
            }
        }
        
        // 2. Critère Écologique (20 points)
        if (!prefs.ecologicalOnly || pool.isEcological) {
            score += 20;
        }
        
        // 3. Critère Domaine (25 points max)
        for (uint256 i = 0; i < prefs.activityDomains.length; i++) {
            if (keccak256(bytes(pool.activityDomain)) == keccak256(bytes(prefs.activityDomains[i]))) {
                score += 25;
                break;
            }
        }
        
        // 4. Critère Taux d'intérêt (15 points)
        if (pool.dynamicInterestRate >= prefs.minInterestRate) {
            score += 15;
        }
        
        // 5. Critère Risque (10 points)
        if (pool.riskScore <= prefs.maxRiskScore) {
            score += 10;
        }
        
        return score;
    }
    
    // ============ FONCTIONS ADMIN ============
    
    function addValidRegion(string memory region) external onlyOwner {
        validRegions[region] = true;
    }
    
    function removeValidRegion(string memory region) external onlyOwner {
        validRegions[region] = false;
    }
    
    function addValidDomain(string memory domain) external onlyOwner {
        validDomains[domain] = true;
    }
    
    function removeValidDomain(string memory domain) external onlyOwner {
        validDomains[domain] = false;
    }
    
    function setLoanPool(address _loanPool) external onlyOwner {
        loanPool = ILoanPool(_loanPool);
    }
}