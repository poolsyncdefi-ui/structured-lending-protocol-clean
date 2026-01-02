// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

// Imports nécessaires
import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import "@openzeppelin/contracts/access/Ownable.sol";
import "@openzeppelin/contracts/utils/ReentrancyGuard.sol";
import "@openzeppelin/contracts/utils/structs/EnumerableSet.sol";

// Interfaces du protocole
import "../interfaces/IRiskEngine.sol";
import "../interfaces/ICriteriaFilter.sol";
import "../interfaces/ISpecialOfferManager.sol";
import "../interfaces/IInsuranceModule.sol";

/**
 * @title LoanPool - Contrat principal du protocole de prêt participatif
 * @notice Gère le cycle de vie complet d'un pool de prêt avec fonctionnalités avancées
 * @dev Implémente les mécanismes de taux dynamique, filtrage et intégration assurance
 */
contract LoanPool is ERC20, Ownable, ReentrancyGuard {
    using SafeERC20 for IERC20;
    using EnumerableSet for EnumerableSet.AddressSet;

    // ============ STRUCTURES ET ÉNUMÉRATIONS ============

    /**
     * @notice État du pool de prêt
     */
    enum PoolStatus {
        CREATION,      // En configuration par l'emprunteur
        ACTIVE,        // Ouvert aux investissements
        FUNDED,        // Montant cible atteint, fonds transférés
        ONGOING,       // Prêt en cours de remboursement
        COMPLETED,     // Remboursement intégral effectué
        DEFAULTED,     // Défaut de paiement
        LIQUIDATED,    // Pool liquidé après défaut
        CANCELLED      // Annulé avant financement
    }

    /**
     * @notice Structure principale d'un pool de prêt
     */
    struct PoolData {
        // Identifiants
        uint256 poolId;
        address borrower;
        string projectName;
        string projectDescription;
        string projectIpfsHash; // Documents légaux sur IPFS
        
        // Paramètres financiers
        uint256 targetAmount;
        uint256 collectedAmount;
        uint256 baseInterestRate;     // en points de base (ex: 500 = 5%)
        uint256 dynamicInterestRate;  // taux actuel après ajustements
        uint256 repaymentAmount;      // montant total à rembourser
        uint256 amountRepaid;         // montant déjà remboursé
        uint256 duration;             // durée en jours
        uint256 fundingDeadline;      // date limite de financement
        uint256 startDate;            // date de début du prêt
        uint256 completionDate;       // date de fin du prêt
        
        // Critères du projet
        string region;
        bool isEcological;
        string activityDomain;
        uint256 riskScore;            // 1-10 (calculé par RiskEngine)
        
        // Gestion des jetons
        uint256 tokenPrice;           // prix par jeton (en stablecoin)
        uint256 totalTokens;          // nombre total de jetons
        uint256 soldTokens;           // jetons déjà vendus
        
        // Assurance
        uint256 insuranceCoverage;    // montant couvert par assurance
        uint256 insurancePoolId;      // ID du pool d'assurance
        address insuranceModule;      // adresse du module d'assurance
        
        // Offres spéciales
        bool hasSpecialOffer;
        uint256 specialOfferId;
        uint256 specialOfferEndTime;
        uint256 specialOfferBonus;    // bonus de taux en points de base
        
        // Statut
        PoolStatus status;
        uint256 createdAt;
        uint256 lastRateUpdate;
    }

    /**
     * @notice Structure pour les investisseurs
     */
    struct Investor {
        address investorAddress;
        uint256 tokenAmount;
        uint256 investmentAmount;
        uint256 claimedReturns;
        uint256 investmentTime;
    }

    // ============ ÉVÉNEMENTS ============

    event PoolCreated(
        uint256 indexed poolId,
        address indexed borrower,
        uint256 targetAmount,
        uint256 baseInterestRate
    );
    
    event InvestmentMade(
        uint256 indexed poolId,
        address indexed investor,
        uint256 amount,
        uint256 tokensReceived,
        uint256 dynamicRate
    );
    
    event PoolFunded(
        uint256 indexed poolId,
        uint256 totalCollected,
        uint256 fundedDate
    );
    
    event RepaymentMade(
        uint256 indexed poolId,
        uint256 amount,
        uint256 remainingBalance
    );
    
    event PoolCompleted(
        uint256 indexed poolId,
        uint256 totalReturnsDistributed
    );
    
    event DefaultTriggered(
        uint256 indexed poolId,
        uint256 defaultAmount,
        address triggeredBy
    );
    
    event DynamicRateUpdated(
        uint256 indexed poolId,
        uint256 oldRate,
        uint256 newRate
    );

    // ============ ÉTAT DU CONTRAT ============

    // Stablecoin utilisé (USDC, DAI, etc.)
    IERC20 public immutable stablecoin;
    
    // Modules externes
    IRiskEngine public riskEngine;
    ICriteriaFilter public criteriaFilter;
    ISpecialOfferManager public specialOfferManager;
    
    // Données des pools
    mapping(uint256 => PoolData) public pools;
    mapping(uint256 => Investor[]) public poolInvestors;
    mapping(uint256 => mapping(address => uint256)) public investorIndex;
    
    // Compteurs
    uint256 public nextPoolId;
    uint256 public totalPoolsCreated;
    uint256 public totalVolume;
    
    // Paramètres du protocole
    uint256 public protocolFee = 50; // 0.5% en points de base
    address public feeCollector;
    uint256 public minInvestment = 100 * 10**18; // 100 stablecoins
    uint256 public maxInvestment = 100000 * 10**18; // 100,000 stablecoins
    
    // Sécurité
    bool public emergencyPause;
    mapping(address => bool) public authorizedCreators;

    // ============ MODIFICATEURS ============

    modifier onlyBorrower(uint256 poolId) {
        require(pools[poolId].borrower == msg.sender, "Not the borrower");
        _;
    }

    modifier onlyActive(uint256 poolId) {
        require(pools[poolId].status == PoolStatus.ACTIVE, "Pool not active");
        _;
    }

    modifier onlyFunded(uint256 poolId) {
        require(pools[poolId].status == PoolStatus.FUNDED, "Pool not funded");
        _;
    }

    modifier onlyOngoing(uint256 poolId) {
        require(pools[poolId].status == PoolStatus.ONGOING, "Pool not ongoing");
        _;
    }

    modifier notPaused() {
        require(!emergencyPause, "Protocol paused");
        _;
    }

    // ============ CONSTRUCTEUR ============

    /**
     * @notice Initialise le contrat LoanPool
     * @param _stablecoin Adresse du token stable utilisé (USDC, DAI)
     * @param _riskEngine Adresse du RiskEngine
     * @param _feeCollector Adresse qui reçoit les frais du protocole
     */
    constructor(
		address _stablecoin,
		address _riskEngine,
		address _feeCollector
	) 
		ERC20("PoolSync Loan Token", "PSLT") 
		Ownable(msg.sender)
	{
		require(_stablecoin != address(0), "Invalid stablecoin address");
		require(_riskEngine != address(0), "Invalid risk engine address");
		require(_feeCollector != address(0), "Invalid fee collector");
    
		stablecoin = IERC20(_stablecoin);
		riskEngine = IRiskEngine(_riskEngine);
		feeCollector = _feeCollector;
    
		// Le déployeur est autorisé à créer des pools initialement
		authorizedCreators[msg.sender] = true;
	}

    // ============ FONCTIONS PUBLIQUES - CYCLE DE VIE ============

    /**
     * @notice Crée un nouveau pool de prêt
     * @dev Seuls les créateurs autorisés peuvent créer des pools
     */
    function createPool(
        string memory _projectName,
        string memory _projectDescription,
        uint256 _targetAmount,
        uint256 _duration,
        string memory _region,
        bool _isEcological,
        string memory _activityDomain,
        string memory _ipfsHash
    ) external notPaused returns (uint256) {
        require(authorizedCreators[msg.sender], "Not authorized to create pools");
        require(_targetAmount >= 1000 * 10**18, "Target amount too low");
        require(_targetAmount <= 1000000 * 10**18, "Target amount too high");
        require(_duration >= 30 days && _duration <= 365 days, "Invalid duration");
        
        uint256 poolId = nextPoolId++;
        
        // Calcul du taux de base par le RiskEngine
        uint256 baseRate = riskEngine.calculateBaseRate(
            msg.sender,
            _targetAmount,
            _duration,
            _isEcological,
            _activityDomain
        );
        
        // Calcul du score de risque
        uint256 riskScore = riskEngine.calculateRiskScore(
            msg.sender,
            _targetAmount,
            _duration,
            _region,
            _isEcological,
            _activityDomain
        );
        
        // Initialisation des données du pool
        pools[poolId] = PoolData({
            poolId: poolId,
            borrower: msg.sender,
            projectName: _projectName,
            projectDescription: _projectDescription,
            projectIpfsHash: _ipfsHash,
            targetAmount: _targetAmount,
            collectedAmount: 0,
            baseInterestRate: baseRate,
            dynamicInterestRate: baseRate,
            repaymentAmount: _targetAmount + (_targetAmount * baseRate / 10000),
            amountRepaid: 0,
            duration: _duration,
            fundingDeadline: block.timestamp + 30 days, // 30 jours pour lever les fonds
            startDate: 0,
            completionDate: 0,
            region: _region,
            isEcological: _isEcological,
            activityDomain: _activityDomain,
            riskScore: riskScore,
            tokenPrice: _targetAmount / 10000, // 10,000 tokens par défaut
            totalTokens: 10000,
            soldTokens: 0,
            insuranceCoverage: 0,
            insurancePoolId: 0,
            insuranceModule: address(0),
            hasSpecialOffer: false,
            specialOfferId: 0,
            specialOfferEndTime: 0,
            specialOfferBonus: 0,
            status: PoolStatus.CREATION,
            createdAt: block.timestamp,
            lastRateUpdate: block.timestamp
        });
        
        totalPoolsCreated++;
        
        emit PoolCreated(poolId, msg.sender, _targetAmount, baseRate);
        
        return poolId;
    }

    /**
     * @notice Active un pool pour le financement
     * @dev Doit être appelé par l'emprunteur après validation
     */
    function activatePool(uint256 poolId) external onlyBorrower(poolId) {
        PoolData storage pool = pools[poolId];
        require(pool.status == PoolStatus.CREATION, "Pool not in creation");
        require(block.timestamp <= pool.createdAt + 7 days, "Activation period expired");
        
        // Vérification finale par le RiskEngine
        require(riskEngine.validatePool(poolId), "Pool validation failed");
        
        pool.status = PoolStatus.ACTIVE;
        pool.lastRateUpdate = block.timestamp;
        
        // Vérification des offres spéciales actives
        _checkSpecialOffers(poolId);
    }

    /**
     * @notice Investit dans un pool actif
     * @dev Le taux d'intérêt est mis à jour dynamiquement avant l'investissement
     */
    function invest(uint256 poolId, uint256 amount) external nonReentrant notPaused onlyActive(poolId) {
        PoolData storage pool = pools[poolId];
        
        require(amount >= minInvestment, "Investment below minimum");
        require(amount <= maxInvestment, "Investment above maximum");
        require(block.timestamp <= pool.fundingDeadline, "Funding period ended");
        require(pool.collectedAmount + amount <= pool.targetAmount, "Exceeds target amount");
        
        // Mise à jour du taux dynamique
        _updateDynamicRate(poolId);
        
        // Calcul des tokens à allouer
        uint256 tokensToMint = (amount * 10**18) / pool.tokenPrice;
        require(tokensToMint > 0, "Token amount too small");
        
        // Transfert des fonds
        stablecoin.safeTransferFrom(msg.sender, address(this), amount);
        
        // Mise à jour des compteurs
        pool.collectedAmount += amount;
        pool.soldTokens += tokensToMint;
        
        // Enregistrement de l'investisseur
        uint256 investorIndexId = poolInvestors[poolId].length;
        poolInvestors[poolId].push(Investor({
            investorAddress: msg.sender,
            tokenAmount: tokensToMint,
            investmentAmount: amount,
            claimedReturns: 0,
            investmentTime: block.timestamp
        }));
        investorIndex[poolId][msg.sender] = investorIndexId;
        
        // Mint des tokens de pool
        _mint(msg.sender, tokensToMint);
        
        // Application des frais de protocole
        uint256 fee = amount * protocolFee / 10000;
        if (fee > 0) {
            stablecoin.safeTransfer(feeCollector, fee);
        }
        
        emit InvestmentMade(poolId, msg.sender, amount, tokensToMint, pool.dynamicInterestRate);
        
        // Vérification si le pool est entièrement financé
        if (pool.collectedAmount >= pool.targetAmount) {
            _finalizeFunding(poolId);
        }
    }

    /**
     * @notice Finalise le financement et transfère les fonds à l'emprunteur
     * @dev Appelé automatiquement lorsque le montant cible est atteint
     */
    function _finalizeFunding(uint256 poolId) internal {
        PoolData storage pool = pools[poolId];
        
        pool.status = PoolStatus.FUNDED;
        pool.startDate = block.timestamp;
        
        // Calcul du montant net après frais
        uint256 totalFees = pool.collectedAmount * protocolFee / 10000;
        uint256 netAmount = pool.collectedAmount - totalFees;
        
        // Transfert à l'emprunteur
        stablecoin.safeTransfer(pool.borrower, netAmount);
        
        // Démarrage de la période de remboursement
        pool.status = PoolStatus.ONGOING;
        
        totalVolume += pool.collectedAmount;
        
        emit PoolFunded(poolId, pool.collectedAmount, block.timestamp);
    }

    /**
     * @notice Permet à l'emprunteur d'effectuer un remboursement
     */
    function repay(uint256 poolId, uint256 amount) external nonReentrant onlyBorrower(poolId) onlyOngoing(poolId) {
        PoolData storage pool = pools[poolId];
        
        require(amount > 0, "Repayment amount must be positive");
        require(pool.amountRepaid + amount <= pool.repaymentAmount, "Overpayment");
        
        // Transfert des fonds de remboursement
        stablecoin.safeTransferFrom(msg.sender, address(this), amount);
        
        pool.amountRepaid += amount;
        
        // Distribution des intérêts aux investisseurs
        _distributeReturns(poolId, amount);
        
        emit RepaymentMade(poolId, amount, pool.repaymentAmount - pool.amountRepaid);
        
        // Vérification si le prêt est entièrement remboursé
        if (pool.amountRepaid >= pool.repaymentAmount) {
            _completePool(poolId);
        }
    }

    /**
     * @notice Distribution des rendements aux investisseurs
     */
    function _distributeReturns(uint256 poolId, uint256 repaymentAmount) internal {
        PoolData storage pool = pools[poolId];
        Investor[] storage investors = poolInvestors[poolId];
        
        // Calcul de la part des intérêts dans ce remboursement
        uint256 principalPortion = repaymentAmount * pool.targetAmount / pool.repaymentAmount;
        uint256 interestPortion = repaymentAmount - principalPortion;
        
        if (interestPortion == 0) return;
        
        // Distribution proportionnelle aux tokens détenus
        for (uint256 i = 0; i < investors.length; i++) {
            Investor storage investor = investors[i];
            
            // Calcul de la part de l'investisseur dans les intérêts
            uint256 investorShare = interestPortion * investor.tokenAmount / pool.soldTokens;
            
            if (investorShare > 0) {
                investor.claimedReturns += investorShare;
                
                // Transfert des intérêts à l'investisseur
                stablecoin.safeTransfer(investor.investorAddress, investorShare);
            }
        }
    }

    /**
     * @notice Marque le pool comme complété
     */
    function _completePool(uint256 poolId) internal {
        PoolData storage pool = pools[poolId];
        
        pool.status = PoolStatus.COMPLETED;
        pool.completionDate = block.timestamp;
        
        // Brûlage des tokens restants
        _burn(address(this), balanceOf(address(this)));
        
        emit PoolCompleted(poolId, pool.amountRepaid - pool.targetAmount);
    }

    /**
     * @notice Déclenche un défaut de paiement
     * @dev Peut être appelé après expiration de la période de grâce
     */
    function triggerDefault(uint256 poolId) external onlyOngoing(poolId) {
        PoolData storage pool = pools[poolId];
        
        require(block.timestamp > pool.startDate + pool.duration + 30 days, "Grace period not expired");
        require(pool.amountRepaid < pool.repaymentAmount, "Loan already repaid");
        
        pool.status = PoolStatus.DEFAULTED;
        
        // Déclenchement de la procédure d'assurance si existante
        if (pool.insuranceModule != address(0)) {
            IInsuranceModule(pool.insuranceModule).fileClaim(poolId, pool.repaymentAmount - pool.amountRepaid);
        }
        
        emit DefaultTriggered(poolId, pool.repaymentAmount - pool.amountRepaid, msg.sender);
    }

    // ============ FONCTIONS DE TAUX DYNAMIQUE ============

    /**
     * @notice Met à jour le taux d'intérêt dynamique du pool
     */
    function _updateDynamicRate(uint256 poolId) internal {
        PoolData storage pool = pools[poolId];
        
        // Vérification de la fréquence de mise à jour (max 1 fois par heure)
        if (block.timestamp < pool.lastRateUpdate + 1 hours) {
            return;
        }
        
        uint256 oldRate = pool.dynamicInterestRate;
        uint256 newRate = _calculateDynamicRate(poolId);
        
        if (newRate != oldRate) {
            pool.dynamicInterestRate = newRate;
            pool.lastRateUpdate = block.timestamp;
            
            emit DynamicRateUpdated(poolId, oldRate, newRate);
        }
    }

    /**
     * @notice Calcule le taux d'intérêt dynamique
     */
    function _calculateDynamicRate(uint256 poolId) internal view returns (uint256) {
        PoolData storage pool = pools[poolId];
        
        uint256 rate = pool.baseInterestRate;
        
        // 1. Facteur d'attrait (taux de remplissage)
        uint256 fillRate = (pool.soldTokens * 10000) / pool.totalTokens; // en points de base
        
        if (fillRate > 8000) { // > 80%
            // Très populaire - réduction de taux
            rate = rate * 80 / 100; // -20%
        } else if (fillRate < 3000) { // < 30%
            // Peu populaire - augmentation de taux
            rate = rate * 130 / 100; // +30%
        }
        
        // 2. Facteur temporel
        uint256 timeElapsed = block.timestamp - pool.createdAt;
        uint256 fundingPeriod = pool.fundingDeadline - pool.createdAt;
        
        if (timeElapsed > fundingPeriod / 2) {
            // Après la moitié de la période de financement
            rate = rate * 110 / 100; // +10%
        }
        
        // 3. Facteur offre spéciale
        if (pool.hasSpecialOffer && block.timestamp <= pool.specialOfferEndTime) {
            rate = rate + pool.specialOfferBonus;
        }
        
        // 4. Ajustement par le RiskEngine
        rate = riskEngine.adjustRateForMarketConditions(poolId, rate);
        
        // 5. Limites de sécurité
        uint256 minRate = pool.baseInterestRate * 50 / 100; // -50% minimum
        uint256 maxRate = pool.baseInterestRate * 200 / 100; // +100% maximum
        
        if (rate < minRate) rate = minRate;
        if (rate > maxRate) rate = maxRate;
        
        return rate;
    }

    /**
     * @notice Récupère le taux dynamique actuel (vue)
     */
    function getDynamicRate(uint256 poolId) external view returns (uint256) {
        require(pools[poolId].status != PoolStatus.CREATION, "Pool not active");
        return _calculateDynamicRate(poolId);
    }

    // ============ FONCTIONS D'OFFRES SPÉCIALES ============

    /**
     * @notice Vérifie et applique les offres spéciales disponibles
     */
    function _checkSpecialOffers(uint256 poolId) internal {
        if (address(specialOfferManager) != address(0)) {
            (bool hasOffer, uint256 offerId, uint256 bonus, uint256 endTime) = 
                specialOfferManager.getActiveOfferForPool(poolId);
            
            if (hasOffer) {
                PoolData storage pool = pools[poolId];
                pool.hasSpecialOffer = true;
                pool.specialOfferId = offerId;
                pool.specialOfferBonus = bonus;
                pool.specialOfferEndTime = endTime;
                
                // Mise à jour immédiate du taux
                _updateDynamicRate(poolId);
            }
        }
    }

    /**
     * @notice Applique une offre spéciale manuellement
     */
    function applySpecialOffer(uint256 poolId, uint256 offerId) external onlyActive(poolId) {
        require(address(specialOfferManager) != address(0), "Special offer manager not set");
        require(msg.sender == address(specialOfferManager) || msg.sender == owner(), "Not authorized");
        
        PoolData storage pool = pools[poolId];
        
        pool.hasSpecialOffer = true;
        pool.specialOfferId = offerId;
        (pool.specialOfferBonus, pool.specialOfferEndTime) = specialOfferManager.getOfferDetails(offerId);
        
        _updateDynamicRate(poolId);
    }

    // ============ FONCTIONS D'ASSURANCE ============

    /**
     * @notice Souscrit une assurance pour le pool
     */
    function subscribeInsurance(
        uint256 poolId,
        address insuranceModule,
        uint256 coverageAmount,
        uint256 insurancePoolId
    ) external onlyBorrower(poolId) onlyActive(poolId) {
        require(insuranceModule != address(0), "Invalid insurance module");
        require(coverageAmount <= pools[poolId].targetAmount, "Coverage exceeds loan amount");
        
        PoolData storage pool = pools[poolId];
        pool.insuranceModule = insuranceModule;
        pool.insuranceCoverage = coverageAmount;
        pool.insurancePoolId = insurancePoolId;
        
        // Appel au module d'assurance pour souscrire
        IInsuranceModule(insuranceModule).subscribeCoverage(
            poolId,
            coverageAmount,
            insurancePoolId
        );
    }

    // ============ FONCTIONS ADMINISTRATIVES ============

    /**
     * @notice Configure les modules externes
     */
    function setExternalModules(
        address _riskEngine,
        address _criteriaFilter,
        address _specialOfferManager
    ) external onlyOwner {
        if (_riskEngine != address(0)) {
            riskEngine = IRiskEngine(_riskEngine);
        }
        if (_criteriaFilter != address(0)) {
            criteriaFilter = ICriteriaFilter(_criteriaFilter);
        }
        if (_specialOfferManager != address(0)) {
            specialOfferManager = ISpecialOfferManager(_specialOfferManager);
        }
    }

    /**
     * @notice Active/désactive le mode pause d'urgence
     */
    function setEmergencyPause(bool paused) external onlyOwner {
        emergencyPause = paused;
    }

    /**
     * @notice Autorise un nouveau créateur de pools
     */
    function authorizeCreator(address creator, bool authorized) external onlyOwner {
        authorizedCreators[creator] = authorized;
    }

    /**
     * @notice Met à jour les paramètres du protocole
     */
    function updateProtocolParameters(
        uint256 _protocolFee,
        uint256 _minInvestment,
        uint256 _maxInvestment,
        address _feeCollector
    ) external onlyOwner {
        require(_protocolFee <= 200, "Protocol fee too high"); // Max 2%
        require(_minInvestment > 0, "Min investment must be positive");
        require(_minInvestment < _maxInvestment, "Min must be less than max");
        require(_feeCollector != address(0), "Invalid fee collector");
        
        protocolFee = _protocolFee;
        minInvestment = _minInvestment;
        maxInvestment = _maxInvestment;
        feeCollector = _feeCollector;
    }

    // ============ FONCTIONS DE REQUÊTE ============

    /**
     * @notice Récupère les détails complets d'un pool
     */
    function getPoolDetails(uint256 poolId) external view returns (PoolData memory) {
        return pools[poolId];
    }

    /**
     * @notice Récupère la liste des investisseurs d'un pool
     */
    function getPoolInvestors(uint256 poolId) external view returns (Investor[] memory) {
        return poolInvestors[poolId];
    }

    /**
     * @notice Récupère les pools correspondant aux critères
     */
    function getFilteredPools(
        string[] memory regions,
        bool ecologicalOnly,
        string[] memory domains,
        uint256 minRate,
        uint256 maxRisk
    ) external view returns (uint256[] memory) {
        require(address(criteriaFilter) != address(0), "Criteria filter not set");
        
        return criteriaFilter.filterPools(
            regions,
            ecologicalOnly,
            domains,
            minRate,
            maxRisk
        );
    }

    /**
     * @notice Calcule les rendements potentiels pour un investissement
     */
    function calculatePotentialReturns(
        uint256 poolId,
        uint256 investmentAmount
    ) external view returns (uint256 estimatedReturns, uint256 tokensToReceive) {
        PoolData storage pool = pools[poolId];
        require(pool.status == PoolStatus.ACTIVE, "Pool not active");
        
        tokensToReceive = (investmentAmount * 10**18) / pool.tokenPrice;
        uint256 poolShare = (tokensToReceive * 10000) / pool.totalTokens;
        
        // Estimation basée sur le taux dynamique actuel
        uint256 totalInterest = pool.targetAmount * pool.dynamicInterestRate / 10000;
        estimatedReturns = totalInterest * poolShare / 10000;
        
        return (estimatedReturns, tokensToReceive);
    }

    // ============ FONCTIONS DE SECOURS ============

    /**
     * @notice Permet aux investisseurs de récupérer leurs fonds si le pool est annulé
     */
    function withdrawIfCancelled(uint256 poolId) external nonReentrant {
        PoolData storage pool = pools[poolId];
        require(pool.status == PoolStatus.CANCELLED, "Pool not cancelled");
        
        uint256 index = investorIndex[poolId][msg.sender];
        require(index < poolInvestors[poolId].length, "Not an investor");
        
        Investor storage investor = poolInvestors[poolId][index];
        require(investor.investmentAmount > 0, "Already withdrawn");
        
        // Transfert du capital investi
        uint256 refundAmount = investor.investmentAmount;
        investor.investmentAmount = 0;
        
        // Brûlage des tokens
        _burn(msg.sender, investor.tokenAmount);
        
        stablecoin.safeTransfer(msg.sender, refundAmount);
    }
}