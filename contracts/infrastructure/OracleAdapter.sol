// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import "@chainlink/contracts/src/v0.8/shared/interfaces/AggregatorV3Interface.sol";

contract OracleAdapter {
    // Sources d'oracle
    struct OracleSource {
        address aggregator;
        uint256 weight;
        bool isActive;
    }
    
    // Données des oracles
    mapping(address => OracleSource[]) public priceOracles;
    mapping(string => address) public oracleFeeds;
    
    // Paramètres
    uint256 public minimumSources = 2;
    uint256 public deviationThreshold = 5; // 5%
    
    // Événements
    event PriceUpdated(
        address indexed token,
        uint256 price,
        uint256 timestamp,
        uint256 sourceCount
    );
    
    event OracleAdded(
        address indexed token,
        address aggregator,
        uint256 weight
    );
    
    constructor() {
        // Initialisation avec des sources par défaut
        _initializeDefaultOracles();
    }
    
    // Initialisation des oracles par défaut
    function _initializeDefaultOracles() private {
        // ETH/USD
        _addOracleSource(
            address(0), // Native token
            0x5f4eC3Df9cbd43714FE2740f5E3616155c5b8419, // Chainlink ETH/USD
            1000
        );
        
        // BTC/USD
        _addOracleSource(
            0x2260FAC5E5542a773Aa44fBCfeDf7C193bc2C599, // WBTC
            0xF4030086522a5bEEa4988F8cA5B36dbC97BeE88c, // Chainlink BTC/USD
            1000
        );
        
        // USDC/USD
        _addOracleSource(
            0xA0b86991c6218b36c1d19D4a2e9Eb0cE3606eB48, // USDC
            0x8fFfFfd4AfB6115b954Bd326cbe7B4BA576818f6, // Chainlink USDC/USD
            1000
        );
    }
    
    // Ajouter une source d'oracle
    function addOracleSource(
        address token,
        address aggregator,
        uint256 weight
    ) external {
        require(weight > 0 && weight <= 1000, "Invalid weight");
        
        _addOracleSource(token, aggregator, weight);
        
        emit OracleAdded(token, aggregator, weight);
    }
    
    function _addOracleSource(
        address token,
        address aggregator,
        uint256 weight
    ) private {
        priceOracles[token].push(OracleSource({
            aggregator: aggregator,
            weight: weight,
            isActive: true
        }));
        
        // Mapper le nom du feed
        string memory feedName = _getFeedName(token, aggregator);
        oracleFeeds[feedName] = aggregator;
    }
    
    // Obtenir le prix d'un token
    function getPrice(address token) public view returns (uint256) {
        OracleSource[] storage sources = priceOracles[token];
        require(sources.length >= minimumSources, "Insufficient sources");
        
        uint256[] memory prices = new uint256[](sources.length);
        uint256[] memory timestamps = new uint256[](sources.length);
        uint256 totalWeight = 0;
        uint256 activeCount = 0;
        
        // Collecter les prix de toutes les sources actives
        for (uint256 i = 0; i < sources.length; i++) {
            if (!sources[i].isActive) continue;
            
            try AggregatorV3Interface(sources[i].aggregator).latestRoundData()
                returns (uint80, int256 price, uint256, uint256 timestamp, uint80)
            {
                if (price <= 0) continue;
                
                prices[activeCount] = uint256(price);
                timestamps[activeCount] = timestamp;
                totalWeight += sources[i].weight;
                activeCount++;
            } catch {
                continue;
            }
        }
        
        require(activeCount >= minimumSources, "Not enough valid sources");
        
        // Vérifier les déviations
        _checkDeviations(prices, activeCount);
        
        // Calculer le prix médian pondéré
        return _calculateWeightedMedian(prices, sources, activeCount, totalWeight);
    }
    
    // Obtenir la valeur en USD
    function getValueInUSD(address token, uint256 amount) external view returns (uint256) {
        if (token == address(0)) {
            // Token natif (ETH)
            uint256 price = getPrice(address(0));
            return (amount * price) / 1e18;
        } else {
            uint256 price = getPrice(token);
            // Supposer 18 décimales pour les tokens ERC20
            return (amount * price) / 1e18;
        }
    }
    
    // Obtenir l'indice de volatilité
    function getVolatilityIndex() external view returns (uint256) {
        // Simuler un indice de volatilité
        // En production, intégrer avec des oracles de volatilité
        return 4500; // 45% en base 10000
    }
    
    // Obtenir l'indice de liquidité
    function getLiquidityIndex() external view returns (uint256) {
        // Simuler un indice de liquidité
        return 7500; // 75%
    }
    
    // Obtenir le taux de défaut
    function getDefaultRate() external view returns (uint256) {
        // Simuler un taux de défaut
        return 250; // 2.5%
    }
    
    // Obtenir le taux d'intérêt
    function getInterestRate() external view returns (uint256) {
        // Simuler le taux d'intérêt
        return 350; // 3.5%
    }
    
    // Vérifier les déviations entre les sources
    function _checkDeviations(uint256[] memory prices, uint256 count) private pure {
        if (count < 2) return;
        
        uint256 sum = 0;
        for (uint256 i = 0; i < count; i++) {
            sum += prices[i];
        }
        uint256 average = sum / count;
        
        for (uint256 i = 0; i < count; i++) {
            uint256 deviation = (prices[i] > average ? 
                prices[i] - average : average - prices[i]) * 10000 / average;
            
            require(deviation <= 500, "Excessive deviation"); // 5%
        }
    }
    
    // Calculer la médiane pondérée
    function _calculateWeightedMedian(
        uint256[] memory prices,
        OracleSource[] storage sources,
        uint256 count,
        uint256 totalWeight
    ) private view returns (uint256) {
        // Tri des prix (algorithme de tri à bulles simple)
        for (uint256 i = 0; i < count - 1; i++) {
            for (uint256 j = 0; j < count - i - 1; j++) {
                if (prices[j] > prices[j + 1]) {
                    (prices[j], prices[j + 1]) = (prices[j + 1], prices[j]);
                }
            }
        }
        
        // Trouver la médiane pondérée
        uint256 halfWeight = totalWeight / 2;
        uint256 cumulativeWeight = 0;
        
        for (uint256 i = 0; i < count; i++) {
            cumulativeWeight += _getWeightForPrice(sources, prices[i]);
            
            if (cumulativeWeight >= halfWeight) {
                return prices[i];
            }
        }
        
        return prices[count - 1];
    }
    
    // Obtenir le poids pour un prix donné
    function _getWeightForPrice(
        OracleSource[] storage sources,
        uint256 price
    ) private view returns (uint256) {
        // Pour simplifier, retourner un poids moyen
        // En production, mapper le prix à la source appropriée
        uint256 totalWeight = 0;
        uint256 count = 0;
        
        for (uint256 i = 0; i < sources.length; i++) {
            if (sources[i].isActive) {
                totalWeight += sources[i].weight;
                count++;
            }
        }
        
        return count > 0 ? totalWeight / count : 1000;
    }
    
    // Générer un nom de feed
    function _getFeedName(address token, address aggregator) private pure returns (string memory) {
        return string(abi.encodePacked(
            _addressToString(token),
            "-",
            _addressToString(aggregator)
        ));
    }
    
    // Convertir une adresse en string
    function _addressToString(address addr) private pure returns (string memory) {
        bytes32 value = bytes32(uint256(uint160(addr)));
        bytes memory alphabet = "0123456789abcdef";
        bytes memory str = new bytes(42);
        str[0] = '0';
        str[1] = 'x';
        
        for (uint256 i = 0; i < 20; i++) {
            str[2 + i * 2] = alphabet[uint8(value[i + 12] >> 4)];
            str[3 + i * 2] = alphabet[uint8(value[i + 12] & 0x0f)];
        }
        
        return string(str);
    }
    
    // Getters
    function getOracleCount(address token) external view returns (uint256) {
        return priceOracles[token].length;
    }
    
    function getOracleDetails(address token, uint256 index) external view returns (
        address aggregator,
        uint256 weight,
        bool isActive
    ) {
        require(index < priceOracles[token].length, "Invalid index");
        
        OracleSource memory source = priceOracles[token][index];
        return (source.aggregator, source.weight, source.isActive);
    }
}