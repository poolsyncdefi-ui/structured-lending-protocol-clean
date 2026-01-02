// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import "@openzeppelin/contracts/access/AccessControl.sol";
import "@openzeppelin/contracts/utils/cryptography/ECDSA.sol";
import "./AccessController.sol";

contract KYCRegistry is AccessControl {
    using ECDSA for bytes32;
    
    // Structures de données
    struct KYCData {
        address user;
        string userId; // ID unique du système KYC
        uint256 level; // Niveau de vérification: 1=Basic, 2=Advanced, 3=Enhanced
        uint256 verifiedAt;
        uint256 expiresAt;
        address verifiedBy;
        string ipfsHash; // Hash des documents KYC sur IPFS
        bool isActive;
        uint256 lastUpdate;
        string countryCode;
        uint256 riskScore; // Score de risque AML (0-1000)
    }
    
    struct KYCAuditLog {
        address user;
        string action;
        address performedBy;
        uint256 timestamp;
        bytes data;
    }
    
    struct SanctionCheck {
        address user;
        string sanctionList;
        bool isSanctioned;
        uint256 checkedAt;
        string details;
    }
    
    // Niveaux de vérification
    enum VerificationLevel {
        UNVERIFIED,
        BASIC,      // Email + Phone
        ADVANCED,   // Identity document
        ENHANCED,   // Face recognition + source of funds
        INSTITUTIONAL // Corporate verification
    }
    
    // Variables d'état
    mapping(address => KYCData) public kycData;
    mapping(string => address) public userIdToAddress;
    mapping(address => KYCAuditLog[]) public auditLogs;
    mapping(address => SanctionCheck[]) public sanctionChecks;
    
    mapping(string => bool) public blacklistedCountries;
    mapping(address => bool) public pepDatabase; // Politically Exposed Persons
    
    AccessController public accessController;
    
    uint256 public kycExpiryPeriod = 365 days;
    uint256 public pepCheckThreshold = 10000 * 1e18; // 10,000 tokens
    uint256 public sanctionCheckInterval = 30 days;
    
    // Rôles
    bytes32 public constant KYC_VERIFIER = keccak256("KYC_VERIFIER");
    bytes32 public constant KYC_AUDITOR = keccak256("KYC_AUDITOR");
    bytes32 public constant SANCTION_MANAGER = keccak256("SANCTION_MANAGER");
    
    // Événements
    event KYCVerified(
        address indexed user,
        uint256 level,
        string userId,
        address indexed verifier,
        uint256 expiresAt
    );
    
    event KYCRevoked(
        address indexed user,
        address indexed revoker,
        string reason,
        uint256 timestamp
    );
    
    event KYCUpdated(
        address indexed user,
        uint256 newLevel,
        uint256 newExpiry,
        address indexed updater
    );
    
    event SanctionChecked(
        address indexed user,
        string sanctionList,
        bool isSanctioned,
        uint256 timestamp
    );
    
    event PEPFlagged(
        address indexed user,
        bool isPEP,
        string details,
        uint256 timestamp
    );
    
    constructor(address _accessController) {
        accessController = AccessController(_accessController);
        
        _grantRole(DEFAULT_ADMIN_ROLE, msg.sender);
        _grantRole(KYC_VERIFIER, msg.sender);
        _grantRole(KYC_AUDITOR, msg.sender);
        _grantRole(SANCTION_MANAGER, msg.sender);
        
        // Initialisation des pays blacklistés
        _initializeBlacklistedCountries();
    }
    
    // Vérification KYC de base
    function verifyBasicKYC(
        address user,
        string memory userId,
        string memory ipfsHash,
        string memory countryCode,
        bytes memory signature
    ) external onlyRole(KYC_VERIFIER) {
        require(user != address(0), "Invalid user address");
        require(bytes(userId).length > 0, "User ID required");
        require(!_isBlacklistedCountry(countryCode), "Country blacklisted");
        
        // Vérifier la signature pour l'authentification
        _validateSignature(user, userId, ipfsHash, countryCode, signature);
        
        // Vérifier que l'ID n'est pas déjà utilisé
        require(userIdToAddress[userId] == address(0), "User ID already exists");
        
        // Vérifications PEP pour les montants élevés
        bool isPEP = _checkPEPDatabase(user, countryCode);
        uint256 riskScore = _calculateRiskScore(user, countryCode, isPEP);
        
        // Créer l'enregistrement KYC
        kycData[user] = KYCData({
            user: user,
            userId: userId,
            level: uint256(VerificationLevel.BASIC),
            verifiedAt: block.timestamp,
            expiresAt: block.timestamp + kycExpiryPeriod,
            verifiedBy: msg.sender,
            ipfsHash: ipfsHash,
            isActive: true,
            lastUpdate: block.timestamp,
            countryCode: countryCode,
            riskScore: riskScore
        });
        
        userIdToAddress[userId] = user;
        
        // Vérification des sanctions
        _performSanctionCheck(user, countryCode);
        
        // Journal d'audit
        _logAudit(user, "BASIC_KYC_VERIFICATION", abi.encode(ipfsHash, countryCode));
        
        emit KYCVerified(
            user,
            uint256(VerificationLevel.BASIC),
            userId,
            msg.sender,
            block.timestamp + kycExpiryPeriod
        );
        
        if (isPEP) {
            emit PEPFlagged(user, true, "PEP detected during KYC", block.timestamp);
        }
    }
    
    // Mise à niveau de la vérification
    function upgradeVerificationLevel(
        address user,
        uint256 newLevel,
        string memory additionalDataIpfs,
        bytes memory signature
    ) external onlyRole(KYC_VERIFIER) {
        require(kycData[user].isActive, "User not KYC verified");
        require(newLevel > kycData[user].level, "New level must be higher");
        require(newLevel <= uint256(VerificationLevel.INSTITUTIONAL), "Invalid level");
        
        // Vérifier la signature
        _validateUpgradeSignature(user, newLevel, additionalDataIpfs, signature);
        
        // Mise à jour des données
        kycData[user].level = newLevel;
        kycData[user].ipfsHash = string(abi.encodePacked(
            kycData[user].ipfsHash,
            ";",
            additionalDataIpfs
        ));
        kycData[user].lastUpdate = block.timestamp;
        kycData[user].expiresAt = block.timestamp + kycExpiryPeriod;
        
        // Recalcul du score de risque
        kycData[user].riskScore = _calculateRiskScore(
            user,
            kycData[user].countryCode,
            pepDatabase[user]
        );
        
        // Journal d'audit
        _logAudit(user, "KYC_UPGRADE", abi.encode(newLevel, additionalDataIpfs));
        
        emit KYCUpdated(
            user,
            newLevel,
            block.timestamp + kycExpiryPeriod,
            msg.sender
        );
    }
    
    // Vérification périodique (à appeler régulièrement)
    function performPeriodicCheck(address user) external onlyRole(KYC_AUDITOR) {
        require(kycData[user].isActive, "User not KYC verified");
        
        // Vérifier l'expiration
        if (block.timestamp > kycData[user].expiresAt) {
            _revokeKYC(user, "KYC expired");
            return;
        }
        
        // Vérification des sanctions mise à jour
        if (block.timestamp > _lastSanctionCheck(user) + sanctionCheckInterval) {
            _performSanctionCheck(user, kycData[user].countryCode);
        }
        
        // Vérification PEP mise à jour
        _updatePEPStatus(user, kycData[user].countryCode);
        
        // Recalcul du score de risque
        kycData[user].riskScore = _calculateRiskScore(
            user,
            kycData[user].countryCode,
            pepDatabase[user]
        );
        
        kycData[user].lastUpdate = block.timestamp;
        
        _logAudit(user, "PERIODIC_CHECK", "");
    }
    
    // Vérification de l'éligibilité pour une action
    function checkEligibility(
        address user,
        uint256 amount,
        string memory actionType
    ) external view returns (bool eligible, string memory reason) {
        if (!kycData[user].isActive) {
            return (false, "KYC not verified");
        }
        
        if (block.timestamp > kycData[user].expiresAt) {
            return (false, "KYC expired");
        }
        
        // Vérification des sanctions
        if (_isCurrentlySanctioned(user)) {
            return (false, "User is sanctioned");
        }
        
        // Vérification PEP pour les montants élevés
        if (pepDatabase[user] && amount > pepCheckThreshold) {
            return (false, "PEP requires enhanced due diligence");
        }
        
        // Vérification du niveau KYC requis
        uint256 requiredLevel = _getRequiredKYCLevel(amount, actionType);
        if (kycData[user].level < requiredLevel) {
            return (false, "Insufficient KYC level");
        }
        
        // Vérification du score de risque
        if (kycData[user].riskScore > 800) { // Haut risque
            return (false, "High risk profile");
        }
        
        return (true, "Eligible");
    }
    
    // Ajout manuel d'un PEP
    function flagAsPEP(
        address user,
        string memory details,
        bytes memory evidenceIpfs
    ) external onlyRole(SANCTION_MANAGER) {
        pepDatabase[user] = true;
        
        // Mise à jour du score de risque
        if (kycData[user].isActive) {
            kycData[user].riskScore = _calculateRiskScore(
                user,
                kycData[user].countryCode,
                true
            );
        }
        
        _logAudit(user, "PEP_FLAGGED", abi.encode(details, evidenceIpfs));
        
        emit PEPFlagged(user, true, details, block.timestamp);
    }
    
    // Ajout d'une sanction
    function addSanction(
        address user,
        string memory sanctionList,
        string memory details,
        bytes memory evidence
    ) external onlyRole(SANCTION_MANAGER) {
        sanctionChecks[user].push(SanctionCheck({
            user: user,
            sanctionList: sanctionList,
            isSanctioned: true,
            checkedAt: block.timestamp,
            details: details
        }));
        
        // Si KYC actif, le révoquer
        if (kycData[user].isActive) {
            _revokeKYC(user, string(abi.encodePacked("Sanctioned: ", sanctionList)));
        }
        
        _logAudit(user, "SANCTION_ADDED", abi.encode(sanctionList, details, evidence));
        
        emit SanctionChecked(user, sanctionList, true, block.timestamp);
    }
    
    // Révocation de KYC
    function revokeKYC(
        address user,
        string memory reason
    ) external onlyRole(KYC_VERIFIER) {
        _revokeKYC(user, reason);
    }
    
    // Fonctions internes
    function _validateSignature(
        address user,
        string memory userId,
        string memory ipfsHash,
        string memory countryCode,
        bytes memory signature
    ) private pure {
        bytes32 messageHash = keccak256(abi.encodePacked(
            user,
            userId,
            ipfsHash,
            countryCode,
            "KYC_VERIFICATION"
        ));
        
        bytes32 ethSignedMessageHash = messageHash.toEthSignedMessageHash();
        address recovered = ethSignedMessageHash.recover(signature);
        
        require(recovered == user, "Invalid signature");
    }
    
    function _validateUpgradeSignature(
        address user,
        uint256 newLevel,
        string memory ipfsHash,
        bytes memory signature
    ) private pure {
        bytes32 messageHash = keccak256(abi.encodePacked(
            user,
            newLevel,
            ipfsHash,
            "KYC_UPGRADE"
        ));
        
        bytes32 ethSignedMessageHash = messageHash.toEthSignedMessageHash();
        address recovered = ethSignedMessageHash.recover(signature);
        
        require(recovered == user, "Invalid upgrade signature");
    }
    
    function _initializeBlacklistedCountries() private {
        // Liste des pays à haut risque (exemples)
        blacklistedCountries["KP"] = true; // Corée du Nord
        blacklistedCountries["IR"] = true; // Iran
        blacklistedCountries["SY"] = true; // Syrie
        blacklistedCountries["CU"] = true; // Cuba
        // À compléter selon les régulations
    }
    
    function _isBlacklistedCountry(string memory countryCode) private view returns (bool) {
        return blacklistedCountries[countryCode];
    }
    
    function _checkPEPDatabase(address user, string memory countryCode) private returns (bool) {
        // En production, intégrer avec une base de données PEP externe
        // Pour l'instant, simulation basée sur des règles simples
        
        // Règle: certains pays ont plus de risques PEP
        bool highRiskCountry = keccak256(bytes(countryCode)) == keccak256(bytes("RU")) ||
                              keccak256(bytes(countryCode)) == keccak256(bytes("CN")) ||
                              keccak256(bytes(countryCode)) == keccak256(bytes("AE"));
        
        // Simulation: 5% de chance d'être PEP dans les pays à risque
        if (highRiskCountry) {
            uint256 random = uint256(keccak256(abi.encodePacked(
                block.timestamp,
                user
            ))) % 100;
            
            if (random < 5) { // 5%
                pepDatabase[user] = true;
                return true;
            }
        }
        
        return false;
    }
    
    function _updatePEPStatus(address user, string memory countryCode) private {
        // Mise à jour périodique du statut PEP
        // À intégrer avec un service externe en production
    }
    
    function _calculateRiskScore(
        address user,
        string memory countryCode,
        bool isPEP
    ) private pure returns (uint256) {
        uint256 score = 0;
        
        // Facteur pays
        if (keccak256(bytes(countryCode)) == keccak256(bytes("US")) ||
            keccak256(bytes(countryCode)) == keccak256(bytes("UK")) ||
            keccak256(bytes(countryCode)) == keccak256(bytes("DE"))) {
            score += 100; // Pays à faible risque
        } else if (keccak256(bytes(countryCode)) == keccak256(bytes("RU")) ||
                  keccak256(bytes(countryCode)) == keccak256(bytes("CN"))) {
            score += 400; // Pays à risque moyen
        } else {
            score += 200; // Autres pays
        }
        
        // Facteur PEP
        if (isPEP) {
            score += 300;
        }
        
        // Facteur adresse (nouveau vs ancien)
        uint256 addressAge = (block.timestamp - 1609459200) / 1 days; // Depuis 2021
        if (addressAge < 365) {
            score += 100; // Adresse récente
        }
        
        return score > 1000 ? 1000 : score;
    }
    
    function _performSanctionCheck(address user, string memory countryCode) private {
        // En production, intégrer avec des APIs de sanctions
        // Pour l'instant, simulation
        
        bool isSanctioned = false;
        string memory sanctionList = "INTERNAL";
        
        // Simulation: vérification basée sur le pays
        if (keccak256(bytes(countryCode)) == keccak256(bytes("KP")) ||
            keccak256(bytes(countryCode)) == keccak256(bytes("IR"))) {
            isSanctioned = true;
            sanctionList = "OFAC";
        }
        
        sanctionChecks[user].push(SanctionCheck({
            user: user,
            sanctionList: sanctionList,
            isSanctioned: isSanctioned,
            checkedAt: block.timestamp,
            details: isSanctioned ? "Country-based sanction" : "Clear"
        }));
        
        emit SanctionChecked(user, sanctionList, isSanctioned, block.timestamp);
        
        if (isSanctioned && kycData[user].isActive) {
            _revokeKYC(user, "Sanctioned country");
        }
    }
    
    function _lastSanctionCheck(address user) private view returns (uint256) {
        SanctionCheck[] storage checks = sanctionChecks[user];
        if (checks.length == 0) {
            return 0;
        }
        return checks[checks.length - 1].checkedAt;
    }
    
    function _isCurrentlySanctioned(address user) private view returns (bool) {
        SanctionCheck[] storage checks = sanctionChecks[user];
        if (checks.length == 0) {
            return false;
        }
        
        // Vérifier la dernière entrée
        SanctionCheck memory lastCheck = checks[checks.length - 1];
        return lastCheck.isSanctioned;
    }
    
    function _getRequiredKYCLevel(
        uint256 amount,
        string memory actionType
    ) private pure returns (uint256) {
        if (amount == 0) {
            return uint256(VerificationLevel.BASIC);
        }
        
        if (amount <= 1000 * 1e18) {
            return uint256(VerificationLevel.BASIC);
        } else if (amount <= 10000 * 1e18) {
            return uint256(VerificationLevel.ADVANCED);
        } else if (amount <= 100000 * 1e18) {
            return uint256(VerificationLevel.ENHANCED);
        } else {
            return uint256(VerificationLevel.INSTITUTIONAL);
        }
    }
    
    function _revokeKYC(address user, string memory reason) private {
        require(kycData[user].isActive, "KYC already inactive");
        
        kycData[user].isActive = false;
        kycData[user].lastUpdate = block.timestamp;
        
        _logAudit(user, "KYC_REVOKED", abi.encode(reason));
        
        emit KYCRevoked(user, msg.sender, reason, block.timestamp);
    }
    
    function _logAudit(
        address user,
        string memory action,
        bytes memory data
    ) private {
        auditLogs[user].push(KYCAuditLog({
            user: user,
            action: action,
            performedBy: msg.sender,
            timestamp: block.timestamp,
            data: data
        }));
    }
    
    // Getters
    function isVerified(address user) external view returns (bool) {
        return kycData[user].isActive && block.timestamp <= kycData[user].expiresAt;
    }
    
    function getVerificationLevel(address user) external view returns (uint256) {
        if (!kycData[user].isActive || block.timestamp > kycData[user].expiresAt) {
            return uint256(VerificationLevel.UNVERIFIED);
        }
        return kycData[user].level;
    }
    
    function getKYCData(address user) external view returns (KYCData memory) {
        return kycData[user];
    }
    
    function getAuditLogs(
        address user,
        uint256 limit
    ) external view onlyRole(KYC_AUDITOR) returns (KYCAuditLog[] memory) {
        KYCAuditLog[] storage logs = auditLogs[user];
        
        if (limit == 0 || limit > logs.length) {
            limit = logs.length;
        }
        
        KYCAuditLog[] memory result = new KYCAuditLog[](limit);
        
        for (uint256 i = 0; i < limit; i++) {
            result[i] = logs[logs.length - 1 - i];
        }
        
        return result;
    }
    
    function getSanctionHistory(
        address user
    ) external view onlyRole(SANCTION_MANAGER) returns (SanctionCheck[] memory) {
        return sanctionChecks[user];
    }
    
    function calculateComplianceScore(address user) external view returns (uint256 score) {
        if (!kycData[user].isActive) {
            return 0;
        }
        
        // Score basé sur le niveau KYC, l'âge, et les vérifications
        score = kycData[user].level * 250; // 250 points par niveau
        
        // Bonus pour ancienneté
        uint256 ageDays = (block.timestamp - kycData[user].verifiedAt) / 1 days;
        if (ageDays > 180) {
            score += 100;
        }
        
        // Malus pour risque
        score = score > kycData[user].riskScore ? score - kycData[user].riskScore : 0;
        
        return score > 1000 ? 1000 : score;
    }
    
    // Configuration
    function setKYCExpiryPeriod(uint256 newPeriod) external onlyRole(DEFAULT_ADMIN_ROLE) {
        require(newPeriod >= 90 days && newPeriod <= 730 days, "Invalid expiry period");
        kycExpiryPeriod = newPeriod;
    }
    
    function setPEPCheckThreshold(uint256 newThreshold) external onlyRole(DEFAULT_ADMIN_ROLE) {
        pepCheckThreshold = newThreshold;
    }
    
    function addBlacklistedCountry(string memory countryCode) external onlyRole(SANCTION_MANAGER) {
        blacklistedCountries[countryCode] = true;
    }
    
    function removeBlacklistedCountry(string memory countryCode) external onlyRole(SANCTION_MANAGER) {
        blacklistedCountries[countryCode] = false;
    }
}