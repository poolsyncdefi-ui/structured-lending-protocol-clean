// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import "@openzeppelin/contracts/access/Ownable.sol";
import "@openzeppelin/contracts/utils/Strings.sol";

/**
 * @title DynamicTranche - Gestion dynamique des tranches de risque
 * @notice Crée et gère des tranches avec différents niveaux de risque/rendement
 */
contract DynamicTranche is ERC20, Ownable {
        
    enum TrancheType {
        SENIOR,     // Risque faible, rendement faible
        MEZZANINE,  // Risque moyen, rendement moyen
        JUNIOR      // Risque élevé, rendement élevé
    }
    
    struct Tranche {
        TrancheType trancheType;
        string name;
        uint256 targetAllocation;   // Allocation cible en %
        uint256 currentAllocation;  // Allocation actuelle
        uint256 minRiskScore;       // Score risque minimum
        uint256 maxRiskScore;       // Score risque maximum
        uint256 yieldMultiplier;    // Multiplicateur de rendement
        uint256 lossAbsorption;     // % d'absorption des pertes
        address trancheToken;       // Token de la tranche
        bool isActive;
    }
    
    // Tranches disponibles
    mapping(uint256 => Tranche) public tranches;
    uint256 public trancheCount;
    
    // Pool associé
    uint256 public poolId;
    address public loanPool;
    
    // Événements
    event TrancheCreated(uint256 indexed trancheId, TrancheType trancheType, string name);
    event InvestmentAllocated(uint256 indexed trancheId, uint256 amount);
    event ReturnsDistributed(uint256 indexed trancheId, uint256 amount);
    event LossesAbsorbed(uint256 indexed trancheId, uint256 amount);
    
	constructor(
		uint256 _poolId,
		address _loanPool,
		string memory name,
		string memory symbol
	) 
		ERC20(name, symbol) 
		Ownable(msg.sender) 
	{
		poolId = _poolId;
		loanPool = _loanPool;
		_createDefaultTranches();
	}
    
    /**
     * @notice Crée les tranches par défaut
     */
    function _createDefaultTranches() internal {
        // Tranche Senior (60%)
        _createTranche(
            TrancheType.SENIOR,
            "Senior Tranche",
            6000,   // 60%
            1,      // Risque 1-3
            3,
            80,     // 0.8x rendement
            10      // 10% absorption pertes
        );
        
        // Tranche Mezzanine (30%)
        _createTranche(
            TrancheType.MEZZANINE,
            "Mezzanine Tranche",
            3000,   // 30%
            4,      // Risque 4-6
            6,
            120,    // 1.2x rendement
            30      // 30% absorption pertes
        );
        
        // Tranche Junior (10%)
        _createTranche(
            TrancheType.JUNIOR,
            "Junior Tranche",
            1000,   // 10%
            7,      // Risque 7-10
            10,
            200,    // 2.0x rendement
            60      // 60% absorption pertes
        );
    }
    
    /**
     * @notice Crée une nouvelle tranche
     */
    function _createTranche(
        TrancheType trancheType,
        string memory name,
        uint256 targetAllocation,
        uint256 minRiskScore,
        uint256 maxRiskScore,
        uint256 yieldMultiplier,
        uint256 lossAbsorption
    ) internal {
        uint256 trancheId = trancheCount++;
        
        // Création du token de tranche
        string memory tokenSymbol = string(abi.encodePacked("TRANCHE", Strings.toString(trancheId)));
        address trancheToken = address(new TrancheToken(name, tokenSymbol));
        
        tranches[trancheId] = Tranche({
            trancheType: trancheType,
            name: name,
            targetAllocation: targetAllocation,
            currentAllocation: 0,
            minRiskScore: minRiskScore,
            maxRiskScore: maxRiskScore,
            yieldMultiplier: yieldMultiplier,
            lossAbsorption: lossAbsorption,
            trancheToken: trancheToken,
            isActive: true
        });
        
        emit TrancheCreated(trancheId, trancheType, name);
    }
    
    /**
     * @notice Alloue un investissement aux tranches
     */
    function allocateInvestment(uint256 amount, uint256 riskScore) external onlyOwner returns (uint256[] memory) {
        require(amount > 0, "Amount must be positive");
        
        uint256[] memory allocations = new uint256[](trancheCount);
        uint256 remaining = amount;
        
        // Allocation basée sur les allocations cibles et le risque
        for (uint256 i = 0; i < trancheCount; i++) {
            if (!tranches[i].isActive) continue;
            
            // Vérifier si la tranche accepte ce niveau de risque
            if (riskScore >= tranches[i].minRiskScore && riskScore <= tranches[i].maxRiskScore) {
                uint256 allocation = amount * tranches[i].targetAllocation / 10000;
                
                // Ajustement dynamique basé sur l'allocation actuelle
                if (tranches[i].currentAllocation > tranches[i].targetAllocation * 110 / 100) {
                    // Sur-allocation, réduire
                    allocation = allocation * 80 / 100;
                }
                
                allocations[i] = allocation;
                tranches[i].currentAllocation += allocation;
                remaining -= allocation;
                
                emit InvestmentAllocated(i, allocation);
            }
        }
        
        // Redistribuer le reste
        if (remaining > 0) {
            for (uint256 i = 0; i < trancheCount && remaining > 0; i++) {
                if (allocations[i] > 0) {
                    uint256 extra = remaining * allocations[i] / amount;
                    allocations[i] += extra;
                    tranches[i].currentAllocation += extra;
                    remaining -= extra;
                }
            }
        }
        
        return allocations;
    }
    
    /**
     * @notice Distribue les rendements aux tranches
     */
    function distributeReturns(uint256 totalReturns) external onlyOwner {
        require(totalReturns > 0, "No returns to distribute");
        
        for (uint256 i = 0; i < trancheCount; i++) {
            if (!tranches[i].isActive || tranches[i].currentAllocation == 0) continue;
            
            // Calcul de la part de la tranche
            uint256 trancheShare = totalReturns * tranches[i].currentAllocation / 10000;
            
            // Application du multiplicateur de rendement
            uint256 adjustedReturns = trancheShare * tranches[i].yieldMultiplier / 100;
            
            // Distribution aux détenteurs de tokens
            IERC20(tranches[i].trancheToken).transfer(msg.sender, adjustedReturns);
            
            emit ReturnsDistributed(i, adjustedReturns);
        }
    }
    
    /**
     * @notice Absorbe les pertes selon l'ordre des tranches
     */
    function absorbLosses(uint256 totalLosses) external onlyOwner returns (uint256 absorbed) {
        require(totalLosses > 0, "No losses to absorb");
        
        uint256 remainingLosses = totalLosses;
        
        // Absorption dans l'ordre inverse (Junior d'abord)
        for (uint256 i = trancheCount; i > 0; i--) {
            uint256 trancheId = i - 1;
            Tranche storage tranche = tranches[trancheId];
            
            if (!tranche.isActive || tranche.currentAllocation == 0) continue;
            
            // Calcul de la capacité d'absorption
            uint256 absorptionCapacity = tranche.currentAllocation * tranche.lossAbsorption / 100;
            uint256 toAbsorb = remainingLosses < absorptionCapacity ? remainingLosses : absorptionCapacity;
            
            if (toAbsorb > 0) {
                tranche.currentAllocation -= toAbsorb;
                remainingLosses -= toAbsorb;
                absorbed += toAbsorb;
                
                // Burn des tokens proportionnellement
                uint256 burnAmount = toAbsorb * IERC20(tranche.trancheToken).totalSupply() / tranche.currentAllocation;
                IERC20(tranche.trancheToken).transferFrom(msg.sender, address(this), burnAmount);
                
                emit LossesAbsorbed(trancheId, toAbsorb);
            }
            
            if (remainingLosses == 0) break;
        }
        
        return absorbed;
    }
    
    /**
     * @notice Récupère les détails de toutes les tranches
     */
    function getAllTranches() external view returns (Tranche[] memory) {
        Tranche[] memory result = new Tranche[](trancheCount);
        
        for (uint256 i = 0; i < trancheCount; i++) {
            result[i] = tranches[i];
        }
        
        return result;
    }
    
    /**
     * @notice Vérifie si un score de risque est éligible pour une tranche
     */
    function isRiskEligible(uint256 trancheId, uint256 riskScore) external view returns (bool) {
        Tranche storage tranche = tranches[trancheId];
        return riskScore >= tranche.minRiskScore && riskScore <= tranche.maxRiskScore;
    }
}

// Token pour tranche individuelle
contract TrancheToken is ERC20 {
    constructor(string memory name, string memory symbol) ERC20(name, symbol) {
        // Mint initial de 1 million de tokens
        _mint(msg.sender, 1000000 * 10**18);
    }
}