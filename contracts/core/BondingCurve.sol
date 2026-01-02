// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import "@openzeppelin/contracts/access/Ownable.sol";
import "@openzeppelin/contracts/utils/ReentrancyGuard.sol";
import "@openzeppelin/contracts/utils/Pausable.sol";

/**
 * @title BondingCurve - Courbe de liaison pour prix dynamique des jetons
 * @notice Implémente une courbe de liaison pour ajuster le prix des jetons de pool
 */
contract BondingCurve is Ownable {
        
    struct CurveParameters {
        uint256 basePrice;           // Prix de base
        uint256 slope;               // Pente de la courbe
        uint256 exponentialFactor;   // Facteur exponentiel
        uint256 maxPriceMultiplier;  // Multiplicateur max
        uint256 liquiditySensitivity; // Sensibilité à la liquidité
    }
    
    // Paramètres par défaut
    CurveParameters public params;
    
    // Données par pool
    struct PoolCurveData {
        uint256 initialPrice;
        uint256 totalSupply;
        uint256 currentPrice;
        uint256 lastUpdate;
        uint256 volume24h;
    }
    
    mapping(uint256 => PoolCurveData) public poolCurves;
    
    // Événements
    event PriceUpdated(uint256 indexed poolId, uint256 oldPrice, uint256 newPrice);
    event CurveParametersUpdated(uint256 timestamp);
    
    constructor() Ownable(msg.sender) {
        // Paramètres par défaut
        params = CurveParameters({
            basePrice: 1 * 10**18,       // 1.0 stablecoin
            slope: 100,                  // 0.01% par token
            exponentialFactor: 2,        // Courbe quadratique
            maxPriceMultiplier: 200,     // 2x max
            liquiditySensitivity: 50     // 0.5% de sensibilité
        });
    }
    
    /**
     * @notice Calcule le prix d'achat pour des tokens
     */
    function calculateBuyPrice(
        uint256 poolId,
        uint256 tokenAmount,
        uint256 currentSupply
    ) external view returns (uint256 totalCost, uint256 averagePrice) {
        PoolCurveData storage curve = poolCurves[poolId];
        
        if (curve.totalSupply == 0) {
            // Premier achat
            totalCost = tokenAmount * params.basePrice;
            averagePrice = params.basePrice;
        } else {
            // Calcul basé sur la courbe
            totalCost = _calculateIntegral(
                curve.totalSupply,
                curve.totalSupply + tokenAmount,
                currentSupply
            );
            averagePrice = totalCost / tokenAmount;
        }
        
        return (totalCost, averagePrice);
    }
    
    /**
     * @notice Calcule le prix de vente pour des tokens
     */
    function calculateSellPrice(
        uint256 poolId,
        uint256 tokenAmount,
        uint256 currentSupply
    ) external view returns (uint256 totalReturn, uint256 averagePrice) {
        require(tokenAmount <= poolCurves[poolId].totalSupply, "Insufficient supply");
        
        totalReturn = _calculateIntegral(
            poolCurves[poolId].totalSupply - tokenAmount,
            poolCurves[poolId].totalSupply,
            currentSupply
        );
        
        averagePrice = totalReturn / tokenAmount;
        return (totalReturn, averagePrice);
    }
    
    /**
     * @notice Met à jour le prix après un achat/vente
     */
    function updatePriceAfterTrade(
        uint256 poolId,
        uint256 tokenAmount,
        bool isBuy,
        uint256 currentSupply
    ) external returns (uint256 newPrice) {
        PoolCurveData storage curve = poolCurves[poolId];
        
        uint256 oldPrice = curve.currentPrice;
        
        if (isBuy) {
            curve.totalSupply += tokenAmount;
        } else {
            curve.totalSupply -= tokenAmount;
        }
        
        // Mise à jour du prix courant
        newPrice = _calculateSpotPrice(curve.totalSupply, currentSupply);
        curve.currentPrice = newPrice;
        curve.lastUpdate = block.timestamp;
        
        // Mise à jour du volume 24h
        curve.volume24h += tokenAmount * newPrice;
        
        emit PriceUpdated(poolId, oldPrice, newPrice);
        
        return newPrice;
    }
    
    /**
     * @notice Initialise la courbe pour un nouveau pool
     */
    function initializePoolCurve(uint256 poolId, uint256 initialSupply) external onlyOwner {
        require(poolCurves[poolId].totalSupply == 0, "Already initialized");
        
        poolCurves[poolId] = PoolCurveData({
            initialPrice: params.basePrice,
            totalSupply: initialSupply,
            currentPrice: params.basePrice,
            lastUpdate: block.timestamp,
            volume24h: 0
        });
    }
    
    /**
     * @notice Réinitialise le volume 24h (à appeler périodiquement)
     */
    function reset24hVolume(uint256 poolId) external onlyOwner {
        poolCurves[poolId].volume24h = 0;
    }
    
    // ============ FONCTIONS INTERNES ============
    
    function _calculateSpotPrice(uint256 supply, uint256 currentSupply) internal view returns (uint256) {
        if (supply == 0) return params.basePrice;
        
        // Formule: price = basePrice * (1 + slope * supply^exponentialFactor)
        uint256 supplyFactor = supply ** params.exponentialFactor;
        uint256 priceIncrease = params.basePrice * params.slope * supplyFactor / (10**18);
        
        // Ajustement par liquidité
        uint256 liquidityAdjustment = 1;
        if (currentSupply > 0) {
            uint256 utilization = supply * 100 / currentSupply;
            if (utilization > 80) {
                liquidityAdjustment = 120; // +20% si utilisation élevée
            } else if (utilization < 20) {
                liquidityAdjustment = 80;  // -20% si utilisation faible
            }
        }
        
        uint256 price = params.basePrice + priceIncrease;
        price = price * liquidityAdjustment / 100;
        
        // Limite maximale
        uint256 maxPrice = params.basePrice * params.maxPriceMultiplier / 100;
        if (price > maxPrice) price = maxPrice;
        
        return price;
    }
    
    function _calculateIntegral(
        uint256 fromSupply,
        uint256 toSupply,
        uint256 currentSupply
    ) internal view returns (uint256) {
        // Intégrale approximative de la fonction de prix
        uint256 total = 0;
        uint256 step = (toSupply - fromSupply) / 100; // 100 steps pour précision
        
        if (step == 0) step = 1;
        
        for (uint256 s = fromSupply; s < toSupply; s += step) {
            uint256 price = _calculateSpotPrice(s, currentSupply);
            total += price * step;
        }
        
        return total;
    }
    
    // ============ FONCTIONS ADMIN ============
    
    function updateCurveParameters(
        uint256 basePrice,
        uint256 slope,
        uint256 exponentialFactor,
        uint256 maxPriceMultiplier,
        uint256 liquiditySensitivity
    ) external onlyOwner {
        require(basePrice > 0, "Base price must be positive");
        require(slope <= 1000, "Slope too high"); // Max 10%
        require(exponentialFactor <= 3, "Exponential factor too high");
        require(maxPriceMultiplier <= 500, "Max multiplier too high"); // Max 5x
        
        params = CurveParameters({
            basePrice: basePrice,
            slope: slope,
            exponentialFactor: exponentialFactor,
            maxPriceMultiplier: maxPriceMultiplier,
            liquiditySensitivity: liquiditySensitivity
        });
        
        emit CurveParametersUpdated(block.timestamp);
    }
    
    function getPoolCurveData(uint256 poolId) external view returns (PoolCurveData memory) {
        return poolCurves[poolId];
    }
}