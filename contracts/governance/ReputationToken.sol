// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import "@openzeppelin/contracts/token/ERC20/extensions/ERC20Votes.sol";
import "@openzeppelin/contracts/token/ERC20/extensions/ERC20Permit.sol";
import "@openzeppelin/contracts/access/AccessControl.sol";

contract ReputationToken is ERC20Votes, AccessControl {
    // Structure de réputation
    struct ReputationScore {
        uint256 totalScore;
        uint256 lastUpdate;
        uint256[] categoryScores;
        uint256 decayRate;
    }
    
    // Catégories de réputation
    enum ReputationCategory {
        LOAN_REPAYMENT,
        GOVERNANCE_PARTICIPATION,
        INSURANCE_PERFORMANCE,
        COMMUNITY_CONTRIBUTION,
        SYSTEM_SECURITY
    }
    
    // Événements de réputation
    struct ReputationEvent {
        address user;
        ReputationCategory category;
        uint256 points;
        string reason;
        uint256 timestamp;
    }
    
    // Variables d'état
    mapping(address => ReputationScore) public reputationScores;
    mapping(address => ReputationEvent[]) public reputationHistory;
    mapping(address => uint256) public lastActivity;
    
    uint256 public baseDecayRate = 100; // 1% par mois
    uint256 public maxReputationPerUser = 10000 * 1e18;
    uint256 public minReputationForBenefits = 100 * 1e18;
    
    // Contrats autorisés à accorder de la réputation
    mapping(address => bool) public reputationGranters;
    
    // Événements
    event ReputationMinted(
        address indexed user,
        ReputationCategory category,
        uint256 amount,
        string reason,
        uint256 timestamp
    );
    
    event ReputationBurned(
        address indexed user,
        uint256 amount,
        string reason,
        uint256 timestamp
    );
    
    event ReputationTransferred(
        address indexed from,
        address indexed to,
        uint256 amount,
        uint256 timestamp
    );
    
    // Rôles
    bytes32 public constant REPUTATION_MINTER = keccak256("REPUTATION_MINTER");
    bytes32 public constant REPUTATION_BURNER = keccak256("REPUTATION_BURNER");
    
    constructor()
		ERC20("StructuredLendingReputation", "SLR")
		ERC20Permit("StructuredLendingReputation")
		ERC20Votes()
	{
		_grantRole(DEFAULT_ADMIN_ROLE, msg.sender);
        _grantRole(REPUTATION_MINTER, msg.sender);
        _grantRole(REPUTATION_BURNER, msg.sender);
    }
    
    // Attribution de réputation
    function mintReputation(
        address to,
        uint256 amount,
        ReputationCategory category,
        string memory reason
    ) external onlyRole(REPUTATION_MINTER) {
        require(to != address(0), "Invalid address");
        require(amount > 0, "Amount must be > 0");
        
        // Vérifier la limite par utilisateur
        uint256 newTotal = balanceOf(to) + amount;
        require(newTotal <= maxReputationPerUser, "Exceeds max reputation");
        
        // Mint des tokens
        _mint(to, amount);
        
        // Mise à jour du score de réputation
        _updateReputationScore(to, category, amount);
        
        // Enregistrement dans l'historique
        reputationHistory[to].push(ReputationEvent({
            user: to,
            category: category,
            points: amount,
            reason: reason,
            timestamp: block.timestamp
        }));
        
        // Mise à jour de la dernière activité
        lastActivity[to] = block.timestamp;
        
        emit ReputationMinted(to, category, amount, reason, block.timestamp);
    }
    
    // Retrait de réputation (pour pénalités)
    function burnReputation(
        address from,
        uint256 amount,
        string memory reason
    ) external onlyRole(REPUTATION_BURNER) {
        require(balanceOf(from) >= amount, "Insufficient reputation");
        
        // Burn des tokens
        _burn(from, amount);
        
        // Mise à jour du score (diminution générale)
        ReputationScore storage score = reputationScores[from];
        score.totalScore = score.totalScore > amount ? score.totalScore - amount : 0;
        score.lastUpdate = block.timestamp;
        
        emit ReputationBurned(from, amount, reason, block.timestamp);
    }
    
    // Transfert de réputation avec restrictions
    function transferReputation(
        address to,
        uint256 amount
    ) external returns (bool) {
        require(to != address(0), "Invalid recipient");
        require(amount > 0, "Amount must be > 0");
        require(balanceOf(msg.sender) >= amount, "Insufficient reputation");
        
        // Vérifier que le destinataire ne dépasse pas la limite
        uint256 recipientBalance = balanceOf(to);
        require(recipientBalance + amount <= maxReputationPerUser, "Recipient exceeds max");
        
        // Vérifier que l'expéditeur garde un minimum
        uint256 senderNewBalance = balanceOf(msg.sender) - amount;
        require(senderNewBalance >= minReputationForBenefits, "Below minimum for benefits");
        
        // Transfert standard
        bool success = transfer(to, amount);
        
        if (success) {
            // Mise à jour des scores
            _updateTransferReputation(msg.sender, to, amount);
            
            emit ReputationTransferred(msg.sender, to, amount, block.timestamp);
        }
        
        return success;
    }
    
    // Application de la dégradation (décay) de la réputation
    function applyDecay(address user) external {
        ReputationScore storage score = reputationScores[user];
        
        uint256 timeSinceUpdate = block.timestamp - score.lastUpdate;
        if (timeSinceUpdate < 30 days) {
            return; // Pas encore de dégradation
        }
        
        // Calcul de la dégradation
        uint256 monthsPassed = timeSinceUpdate / 30 days;
        uint256 decayAmount = (score.totalScore * baseDecayRate * monthsPassed) / 10000;
        
        if (decayAmount > 0) {
            // Ajuster le score
            score.totalScore = score.totalScore > decayAmount ? 
                score.totalScore - decayAmount : 0;
            
            // Ajuster le solde du token
            uint256 tokenBalance = balanceOf(user);
            if (tokenBalance > decayAmount) {
                _burn(user, decayAmount);
            } else if (tokenBalance > 0) {
                _burn(user, tokenBalance);
            }
            
            // Enregistrement de l'événement
            reputationHistory[user].push(ReputationEvent({
                user: user,
                category: ReputationCategory.SYSTEM_SECURITY,
                points: decayAmount,
                reason: "Monthly reputation decay",
                timestamp: block.timestamp
            }));
        }
        
        score.lastUpdate = block.timestamp;
    }
    
    // Calcul du score de réputation pondéré
    function calculateWeightedScore(address user) public view returns (uint256) {
        ReputationScore memory score = reputationScores[user];
        
        if (score.totalScore == 0) {
            return 0;
        }
        
        // Appliquer la dégradation dans le calcul
        uint256 timeSinceUpdate = block.timestamp - score.lastUpdate;
        uint256 monthsPassed = timeSinceUpdate / 30 days;
        
        if (monthsPassed > 0) {
            uint256 decayAmount = (score.totalScore * baseDecayRate * monthsPassed) / 10000;
            if (decayAmount < score.totalScore) {
                return score.totalScore - decayAmount;
            }
        }
        
        return score.totalScore;
    }
    
    // Vérification des avantages basés sur la réputation
    function hasGovernanceVotingRights(address user) public view returns (bool) {
        return calculateWeightedScore(user) >= minReputationForBenefits;
    }
    
    function hasPremiumFeaturesAccess(address user) public view returns (bool) {
        return calculateWeightedScore(user) >= minReputationForBenefits * 2;
    }
    
    function hasEarlyAccessFeatures(address user) public view returns (bool) {
        return calculateWeightedScore(user) >= minReputationForBenefits * 5;
    }
    
    // Récupération de l'historique de réputation
    function getReputationHistory(address user, uint256 limit) 
        public 
        view 
        returns (ReputationEvent[] memory) 
    {
        ReputationEvent[] storage history = reputationHistory[user];
        
        if (limit == 0 || limit > history.length) {
            limit = history.length;
        }
        
        ReputationEvent[] memory result = new ReputationEvent[](limit);
        
        for (uint256 i = 0; i < limit; i++) {
            result[i] = history[history.length - 1 - i]; // Inverser pour avoir les plus récents en premier
        }
        
        return result;
    }
    
    // Statistiques de réputation
    function getReputationStats(address user) public view returns (
        uint256 totalScore,
        uint256 weightedScore,
        uint256 lastUpdate,
        uint256 categoryCount,
        bool hasVotingRights,
        bool hasPremiumAccess,
        bool hasEarlyAccess
    ) {
        ReputationScore memory score = reputationScores[user];
        
        return (
            score.totalScore,
            calculateWeightedScore(user),
            score.lastUpdate,
            score.categoryScores.length,
            hasGovernanceVotingRights(user),
            hasPremiumFeaturesAccess(user),
            hasEarlyAccessFeatures(user)
        );
    }
    
    // Fonctions internes
    function _updateReputationScore(
        address user,
        ReputationCategory category,
        uint256 amount
    ) private {
        ReputationScore storage score = reputationScores[user];
        
        // Initialiser si nécessaire
        if (score.categoryScores.length == 0) {
            score.categoryScores = new uint256[](5); // 5 catégories
            score.decayRate = baseDecayRate;
        }
        
        // Mettre à jour le score total
        score.totalScore += amount;
        
        // Mettre à jour la catégorie spécifique
        if (uint256(category) < score.categoryScores.length) {
            score.categoryScores[uint256(category)] += amount;
        }
        
        score.lastUpdate = block.timestamp;
        
        // Ajuster le taux de dégradation basé sur l'activité
        if (amount > 100 * 1e18) { // Grande attribution
            score.decayRate = score.decayRate * 90 / 100; // Réduire la dégradation de 10%
        }
    }
    
    function _updateTransferReputation(
        address from,
        address to,
        uint256 amount
    ) private {
        // L'expéditeur perd proportionnellement de chaque catégorie
        ReputationScore storage fromScore = reputationScores[from];
        ReputationScore storage toScore = reputationScores[to];
        
        if (fromScore.totalScore > 0) {
            // Calculer la proportion à transférer de chaque catégorie
            uint256 transferRatio = (amount * 1e18) / fromScore.totalScore;
            
            for (uint256 i = 0; i < fromScore.categoryScores.length; i++) {
                uint256 categoryTransfer = (fromScore.categoryScores[i] * transferRatio) / 1e18;
                
                fromScore.categoryScores[i] -= categoryTransfer;
                
                // Initialiser la catégorie du destinataire si nécessaire
                if (toScore.categoryScores.length == 0) {
                    toScore.categoryScores = new uint256[](5);
                }
                toScore.categoryScores[i] += categoryTransfer;
            }
            
            fromScore.totalScore -= amount;
            toScore.totalScore += amount;
            
            fromScore.lastUpdate = block.timestamp;
            toScore.lastUpdate = block.timestamp;
        } else {
            // Si l'expéditeur n'a pas de score détaillé, simplement ajouter au destinataire
            toScore.totalScore += amount;
            toScore.lastUpdate = block.timestamp;
        }
    }
    
    // Configuration
    function setBaseDecayRate(uint256 newRate) external onlyRole(DEFAULT_ADMIN_ROLE) {
        require(newRate <= 1000, "Rate too high"); // Max 10%
        baseDecayRate = newRate;
    }
    
    function setMaxReputationPerUser(uint256 newMax) external onlyRole(DEFAULT_ADMIN_ROLE) {
        maxReputationPerUser = newMax;
    }
    
    function setMinReputationForBenefits(uint256 newMin) external onlyRole(DEFAULT_ADMIN_ROLE) {
        minReputationForBenefits = newMin;
    }
    
    // Autoriser un contrat à accorder de la réputation
    function addReputationGranter(address granter) external onlyRole(DEFAULT_ADMIN_ROLE) {
        reputationGranters[granter] = true;
        _grantRole(REPUTATION_MINTER, granter);
    }
    
    // Override des fonctions de transfert standard pour ajouter des restrictions
    function transfer(address to, uint256 amount) public override returns (bool) {
        require(balanceOf(msg.sender) - amount >= minReputationForBenefits, 
            "Transfer would go below minimum");
        
        return super.transfer(to, amount);
    }
    
    function transferFrom(
        address from,
        address to,
        uint256 amount
    ) public override returns (bool) {
        require(balanceOf(from) - amount >= minReputationForBenefits,
            "Transfer would leave sender below minimum");
        
        return super.transferFrom(from, to, amount);
    }
    
    // Getters
    function getCategoryScore(address user, ReputationCategory category) 
        external 
        view 
        returns (uint256) 
    {
        ReputationScore memory score = reputationScores[user];
        
        if (uint256(category) < score.categoryScores.length) {
            return score.categoryScores[uint256(category)];
        }
        
        return 0;
    }
    
    function getReputationLevel(address user) external view returns (string memory) {
        uint256 score = calculateWeightedScore(user);
        
        if (score >= 5000 * 1e18) return "Legendary";
        if (score >= 2000 * 1e18) return "Expert";
        if (score >= 1000 * 1e18) return "Advanced";
        if (score >= 500 * 1e18) return "Intermediate";
        if (score >= 100 * 1e18) return "Beginner";
        
        return "Newcomer";
    }
	
	function mint(address to, uint256 amount) external onlyRole(DEFAULT_ADMIN_ROLE) {
		_mint(to, amount);
	}
}