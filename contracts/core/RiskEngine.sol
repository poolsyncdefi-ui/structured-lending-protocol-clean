// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import "@openzeppelin/contracts/access/Ownable.sol";
import "@chainlink/contracts/src/v0.8/shared/interfaces/AggregatorV3Interface.sol";

/**
 * @title RiskEngine - Moteur de calcul des risques et taux dynamiques
 * @notice Calcule les scores de risque et ajuste les taux en temps réel
 */
contract RiskEngine is Ownable {
    
    struct RiskParameters {
        uint256 baseRateMultiplier;      // Multiplicateur de taux de base
        uint256 ecologicalBonus;          // Bonus pour projets écologiques
        uint256 regionRiskModifier;       // Modificateur par région
        uint256 sectorRiskModifier;       // Modificateur par secteur
        uint256 amountRiskModifier;       // Modificateur par montant
        uint256 durationRiskModifier;     // Modificateur par durée
    }
    
    struct MarketConditions {
        uint256 overallDemand;           // Demande globale (0-100)
        uint256 sectorDemand;            // Demande par secteur (0-100)
        uint256 defaultRate;             // Taux de défaut historique
        uint256 lastUpdate;
    }
    
    // Données de risque par emprunteur
    struct BorrowerProfile {
        uint256 creditScore;             // Score de crédit (1-1000)
        uint256 totalBorrowed;           // Montant total emprunté
        uint256 activeLoans;             // Prêts actifs
        uint256 defaultCount;            // Nombre de défauts
        uint256 reputationScore;         // Score de réputation (1-100)
    }
    
    // Mappings
    mapping(address => BorrowerProfile) public borrowerProfiles;
    mapping(string => uint256) public regionRiskScores;      // Ex: "Europe" = 300
    mapping(string => uint256) public sectorRiskScores;      // Ex: "Renewable" = 250
    mapping(string => MarketConditions) public sectorConditions;
    
    // Oracles Chainlink
    AggregatorV3Interface internal creditScoreOracle;
    AggregatorV3Interface internal marketDataOracle;
    
    // Paramètres configurables
    RiskParameters public riskParams;
    uint256 public constant BASIS_POINTS = 10000;
    uint256 public minBaseRate = 300;    // 3% minimum
    uint256 public maxBaseRate = 1500;   // 15% maximum
    
    // Événements
    event RiskScoreCalculated(address indexed borrower, uint256 score);
    event BaseRateCalculated(uint256 poolId, uint256 rate);
    event MarketConditionsUpdated(uint256 timestamp);
    
	constructor(address _creditOracle, address _marketOracle) Ownable(msg.sender) {
		creditScoreOracle = AggregatorV3Interface(_creditOracle);
		marketDataOracle = AggregatorV3Interface(_marketOracle);
    
		// Initialisation des paramètres par défaut
		riskParams = RiskParameters({
			baseRateMultiplier: 10000,   // 1.0x
			ecologicalBonus: 200,        // -2% pour projets écologiques
			regionRiskModifier: 5000,    // 50% de poids
			sectorRiskModifier: 3000,    // 30% de poids
			amountRiskModifier: 1000,    // 10% de poids
			durationRiskModifier: 1000   // 10% de poids
		});
    
		// Initialisation des scores de région
		regionRiskScores["Europe"] = 300;
		regionRiskScores["North America"] = 350;
		regionRiskScores["Asia"] = 450;
		regionRiskScores["Africa"] = 600;
		regionRiskScores["South America"] = 550;
    
		// Initialisation des scores de secteur
		sectorRiskScores["Renewable Energy"] = 250;
		sectorRiskScores["Technology"] = 350;
		sectorRiskScores["Agriculture"] = 400;
		sectorRiskScores["Real Estate"] = 450;
		sectorRiskScores["Manufacturing"] = 500;
	}
    
    /**
     * @notice Calcule le taux de base pour un prêt
     */
    function calculateBaseRate(
        address borrower,
        uint256 amount,
        uint256 duration,
        bool isEcological,
        string calldata activityDomain
    ) external returns (uint256) {
        // 1. Score de crédit de l'emprunteur
        uint256 creditScore = _getCreditScore(borrower);
        
        // 2. Score de risque du projet
        uint256 projectRisk = _calculateProjectRisk(
            amount,
            duration,
            isEcological,
            activityDomain
        );
        
        // 3. Taux de base = Base + Risque projet - Score crédit
        uint256 baseRate = 500; // 5% de base
        
        // Ajustement par risque projet
        baseRate = baseRate * projectRisk / BASIS_POINTS;
        
        // Ajustement par score de crédit
        if (creditScore > 700) {
            baseRate = baseRate * 80 / 100; // -20% pour bon crédit
        } else if (creditScore < 400) {
            baseRate = baseRate * 130 / 100; // +30% pour mauvais crédit
        }
        
        // Bonus écologique
        if (isEcological) {
            baseRate = baseRate - riskParams.ecologicalBonus;
            if (baseRate < minBaseRate) baseRate = minBaseRate;
        }
        
        // Ajustement aux conditions de marché
        baseRate = _adjustForMarketConditions(baseRate, activityDomain);
        
        // Limites
        if (baseRate < minBaseRate) baseRate = minBaseRate;
        if (baseRate > maxBaseRate) baseRate = maxBaseRate;
        
        return baseRate;
    }
    
    /**
     * @notice Calcule le score de risque (1-10)
     */
    function calculateRiskScore(
        address borrower,
        uint256 amount,
        uint256 duration,
        string calldata region,
        bool isEcological,
        string calldata activityDomain
    ) external returns (uint256) {
        uint256 score = 5; // Score moyen de départ
        
        // Facteur région (30%)
        uint256 regionScore = regionRiskScores[region];
        if (regionScore == 0) regionScore = 500; // Défaut
        score = score * 70 / 100 + (regionScore / 100) * 30 / 100;
        
        // Facteur secteur (25%)
        uint256 sectorScore = sectorRiskScores[activityDomain];
        if (sectorScore == 0) sectorScore = 500;
        score = score * 75 / 100 + (sectorScore / 100) * 25 / 100;
        
        // Facteur montant (20%)
        if (amount > 500000 * 10**18) {
            score = score + 2; // Gros montant = risque +2
        } else if (amount < 10000 * 10**18) {
            score = score - 1; // Petit montant = risque -1
        }
        
        // Facteur durée (15%)
        if (duration > 180 days) {
            score = score + 1; // Longue durée = risque +1
        }
        
        // Bonus écologique (-10%)
        if (isEcological) {
            score = score - 1;
        }
        
        // Score de crédit emprunteur (10%)
        uint256 creditScore = _getCreditScore(borrower);
        if (creditScore < 400) {
            score = score + 2;
        } else if (creditScore > 700) {
            score = score - 1;
        }
        
        // Limites 1-10
        if (score < 1) score = 1;
        if (score > 10) score = 10;
        
        emit RiskScoreCalculated(borrower, score);
        return score;
    }
    
    /**
     * @notice Valide un pool de prêt
     */
    function validatePool(uint256 poolId) external view returns (bool) {
        // Pour l'instant, validation simple
        // À étendre avec des règles métier complexes
        return true;
    }
    
    /**
     * @notice Ajuste le taux selon les conditions de marché
     */
    function adjustRateForMarketConditions(
        uint256 poolId,
        uint256 currentRate
    ) external view returns (uint256) {
        // Récupération des conditions de marché
        MarketConditions memory conditions = sectorConditions["global"];
        
        // Ajustement selon la demande
        if (conditions.overallDemand > 80) {
            // Forte demande = réduction de taux
            return currentRate * 90 / 100; // -10%
        } else if (conditions.overallDemand < 30) {
            // Faible demande = augmentation de taux
            return currentRate * 115 / 100; // +15%
        }
        
        return currentRate;
    }
    
    // ============ FONCTIONS INTERNES ============
    
    function _calculateProjectRisk(
        uint256 amount,
        uint256 duration,
        bool isEcological,
        string memory activityDomain
    ) internal view returns (uint256) {
        uint256 risk = BASIS_POINTS; // 1.0x de base
        
        // Risque montant (échelle logarithmique)
        if (amount > 1000000 * 10**18) risk = risk * 120 / 100;
        else if (amount > 100000 * 10**18) risk = risk * 110 / 100;
        
        // Risque durée
        if (duration > 365 days) risk = risk * 115 / 100;
        else if (duration > 180 days) risk = risk * 105 / 100;
        
        // Risque secteur
        uint256 sectorRisk = sectorRiskScores[activityDomain];
        if (sectorRisk > 0) {
            risk = risk * sectorRisk / BASIS_POINTS;
        }
        
        // Réduction risque écologique
        if (isEcological) {
            risk = risk * 90 / 100; // -10%
        }
        
        return risk;
    }
    
    function _getCreditScore(address borrower) internal returns (uint256) {
        // D'abord, vérifier si on a un profil local
        if (borrowerProfiles[borrower].creditScore > 0) {
            return borrowerProfiles[borrower].creditScore;
        }
        
        // Sinon, requête à l'oracle Chainlink
        try creditScoreOracle.latestRoundData() returns (
            uint80 /* roundId */,
            int256 score,
            uint256 /* startedAt */,
            uint256 /* updatedAt */,
            uint80 /* answeredInRound */
        ) {
            uint256 oracleScore = uint256(score);
            if (oracleScore > 0 && oracleScore <= 1000) {
                borrowerProfiles[borrower].creditScore = oracleScore;
                return oracleScore;
            }
        } catch {
            // Fallback: score par défaut
        }
        
        return 500; // Score moyen par défaut
    }
    
    function _adjustForMarketConditions(uint256 rate, string memory sector) internal view returns (uint256) {
        MarketConditions memory conditions = sectorConditions[sector];
        if (conditions.overallDemand == 0) {
            conditions = sectorConditions["global"];
        }
        
        if (conditions.overallDemand > 80) {
            return rate * 90 / 100; // -10% si forte demande
        } else if (conditions.overallDemand < 30) {
            return rate * 115 / 100; // +15% si faible demande
        }
        
        return rate;
    }
    
    // ============ FONCTIONS ADMIN ============
    
    function updateRiskParameters(
        uint256 baseRateMultiplier,
        uint256 ecologicalBonus,
        uint256 regionRiskModifier,
        uint256 sectorRiskModifier,
        uint256 amountRiskModifier,
        uint256 durationRiskModifier
    ) external onlyOwner {
        riskParams = RiskParameters({
            baseRateMultiplier: baseRateMultiplier,
            ecologicalBonus: ecologicalBonus,
            regionRiskModifier: regionRiskModifier,
            sectorRiskModifier: sectorRiskModifier,
            amountRiskModifier: amountRiskModifier,
            durationRiskModifier: durationRiskModifier
        });
    }
    
    function updateRegionRisk(string calldata region, uint256 score) external onlyOwner {
        require(score > 0 && score <= 1000, "Invalid score");
        regionRiskScores[region] = score;
    }
    
    function updateSectorRisk(string calldata sector, uint256 score) external onlyOwner {
        require(score > 0 && score <= 1000, "Invalid score");
        sectorRiskScores[sector] = score;
    }
    
    function updateMarketConditions(
        string calldata sector,
        uint256 overallDemand,
        uint256 sectorDemand,
        uint256 defaultRate
    ) external onlyOwner {
        sectorConditions[sector] = MarketConditions({
            overallDemand: overallDemand,
            sectorDemand: sectorDemand,
            defaultRate: defaultRate,
            lastUpdate: block.timestamp
        });
        
        emit MarketConditionsUpdated(block.timestamp);
    }
    
    function setCreditOracle(address oracle) external onlyOwner {
        creditScoreOracle = AggregatorV3Interface(oracle);
    }
    
    function setMarketOracle(address oracle) external onlyOwner {
        marketDataOracle = AggregatorV3Interface(oracle);
    }
}