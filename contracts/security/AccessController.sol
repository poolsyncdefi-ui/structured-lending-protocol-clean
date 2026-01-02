// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import "@openzeppelin/contracts/access/AccessControl.sol";
import "@openzeppelin/contracts/utils/structs/EnumerableSet.sol";
import "@openzeppelin/contracts/utils/ReentrancyGuard.sol";
import "@openzeppelin/contracts/utils/Pausable.sol";

contract AccessController is AccessControl {
    using EnumerableSet for EnumerableSet.AddressSet;
    
    // Structures de données améliorées
    struct RoleConfig {
        bytes32 role;
        string name;
        string description;
        uint256 maxMembers;
        uint256 minMembers;
        bool isSensitive;
        uint256 approvalThreshold; // Pourcentage requis pour les changements
    }
    
    struct PermissionLog {
        address user;
        bytes32 role;
        bool granted;
        address executor;
        uint256 timestamp;
        string reason;
    }
    
    struct ContractRegistration {
        address contractAddress;
        string name;
        string version;
        uint256 registeredAt;
        address registeredBy;
        bool isActive;
        string ipfsConfig;
    }
    
    // Variables d'état
    mapping(bytes32 => RoleConfig) public roleConfigs;
    mapping(bytes32 => EnumerableSet.AddressSet) private roleMembers;
    mapping(address => bytes32[]) public userRoles;
    mapping(address => PermissionLog[]) public permissionLogs;
    mapping(address => ContractRegistration) public registeredContracts;
    
    EnumerableSet.AddressSet private registeredContractsSet;
    
    uint256 public logRetentionPeriod = 365 days;
    uint256 public maxRolesPerUser = 10;
    uint256 public roleChangeCooldown = 24 hours;
    
    mapping(address => mapping(bytes32 => uint256)) public lastRoleChange;
    
    // Rôles système
    bytes32 public constant SUPER_ADMIN = keccak256("SUPER_ADMIN");
    bytes32 public constant SECURITY_ADMIN = keccak256("SECURITY_ADMIN");
    bytes32 public constant AUDITOR = keccak256("AUDITOR");
    bytes32 public constant UPGRADE_MANAGER = keccak256("UPGRADE_MANAGER");
    
    // Événements
    event RoleConfigured(
        bytes32 indexed role,
        string name,
        string description,
        uint256 maxMembers,
        uint256 minMembers,
        bool isSensitive
    );
    
    event RoleGrantedWithApproval(
        bytes32 indexed role,
        address indexed account,
        address indexed granter,
        uint256 approvalCount,
        uint256 timestamp
    );
    
    event RoleRevokedWithReason(
        bytes32 indexed role,
        address indexed account,
        address indexed revoker,
        string reason,
        uint256 timestamp
    );
    
    event ContractRegistered(
        address indexed contractAddress,
        string name,
        string version,
        address indexed registrant,
        uint256 timestamp
    );
    
    event ContractDeregistered(
        address indexed contractAddress,
        address indexed deregistrant,
        string reason,
        uint256 timestamp
    );
    
    event EmergencyAccessActivated(
        address indexed executor,
        uint256 duration,
        string emergencyReason,
        uint256 timestamp
    );
    
    constructor() {
        _grantRole(DEFAULT_ADMIN_ROLE, msg.sender);
        _grantRole(SUPER_ADMIN, msg.sender);
        _grantRole(SECURITY_ADMIN, msg.sender);
        
        // Initialisation des rôles système
        _initializeSystemRoles();
    }
    
    // Initialisation des rôles système
    function _initializeSystemRoles() private {
        // Configuration du rôle SUPER_ADMIN
        roleConfigs[SUPER_ADMIN] = RoleConfig({
            role: SUPER_ADMIN,
            name: "Super Administrator",
            description: "Full system access, can configure all roles",
            maxMembers: 3,
            minMembers: 1,
            isSensitive: true,
            approvalThreshold: 7500 // 75% d'approbation nécessaire
        });
        
        // Configuration du rôle SECURITY_ADMIN
        roleConfigs[SECURITY_ADMIN] = RoleConfig({
            role: SECURITY_ADMIN,
            name: "Security Administrator",
            description: "Manages security settings and emergency procedures",
            maxMembers: 5,
            minMembers: 2,
            isSensitive: true,
            approvalThreshold: 6600 // 66% d'approbation
        });
        
        // Configuration du rôle AUDITOR
        roleConfigs[AUDITOR] = RoleConfig({
            role: AUDITOR,
            name: "System Auditor",
            description: "Read-only access to all system logs and configurations",
            maxMembers: 10,
            minMembers: 1,
            isSensitive: false,
            approvalThreshold: 5000 // 50% d'approbation
        });
        
        // Configuration du rôle UPGRADE_MANAGER
        roleConfigs[UPGRADE_MANAGER] = RoleConfig({
            role: UPGRADE_MANAGER,
            name: "Upgrade Manager",
            description: "Manages contract upgrades and deployments",
            maxMembers: 5,
            minMembers: 2,
            isSensitive: true,
            approvalThreshold: 7500 // 75% d'approbation
        });
        
        // Rôles standards du système de prêt
        _configureStandardRoles();
    }
    
    function _configureStandardRoles() private {
        // Rôle LOAN_MANAGER
        bytes32 LOAN_MANAGER = keccak256("LOAN_MANAGER");
        roleConfigs[LOAN_MANAGER] = RoleConfig({
            role: LOAN_MANAGER,
            name: "Loan Manager",
            description: "Manages loan creation, approval, and lifecycle",
            maxMembers: 10,
            minMembers: 2,
            isSensitive: true,
            approvalThreshold: 6600
        });
        
        // Rôle RISK_MANAGER
        bytes32 RISK_MANAGER = keccak256("RISK_MANAGER");
        roleConfigs[RISK_MANAGER] = RoleConfig({
            role: RISK_MANAGER,
            name: "Risk Manager",
            description: "Manages risk parameters and default processing",
            maxMembers: 8,
            minMembers: 2,
            isSensitive: true,
            approvalThreshold: 6600
        });
        
        // Rôle INSURANCE_MANAGER
        bytes32 INSURANCE_MANAGER = keccak256("INSURANCE_MANAGER");
        roleConfigs[INSURANCE_MANAGER] = RoleConfig({
            role: INSURANCE_MANAGER,
            name: "Insurance Manager",
            description: "Manages insurance policies and claims",
            maxMembers: 8,
            minMembers: 2,
            isSensitive: true,
            approvalThreshold: 6600
        });
        
        // Rôle FUND_MANAGER
        bytes32 FUND_MANAGER = keccak256("FUND_MANAGER");
        roleConfigs[FUND_MANAGER] = RoleConfig({
            role: FUND_MANAGER,
            name: "Fund Manager",
            description: "Manages guarantee fund and treasury",
            maxMembers: 5,
            minMembers: 2,
            isSensitive: true,
            approvalThreshold: 7500
        });
        
        // Rôle GOVERNANCE_MANAGER
        bytes32 GOVERNANCE_MANAGER = keccak256("GOVERNANCE_MANAGER");
        roleConfigs[GOVERNANCE_MANAGER] = RoleConfig({
            role: GOVERNANCE_MANAGER,
            name: "Governance Manager",
            description: "Manages governance proposals and voting",
            maxMembers: 10,
            minMembers: 3,
            isSensitive: false,
            approvalThreshold: 5000
        });
        
        // Rôle NOTIFICATION_SENDER
        bytes32 NOTIFICATION_SENDER = keccak256("NOTIFICATION_SENDER");
        roleConfigs[NOTIFICATION_SENDER] = RoleConfig({
            role: NOTIFICATION_SENDER,
            name: "Notification Sender",
            description: "Can send system notifications to users",
            maxMembers: 15,
            minMembers: 1,
            isSensitive: false,
            approvalThreshold: 5000
        });
        
        // Rôle FEE_COLLECTOR
        bytes32 FEE_COLLECTOR = keccak256("FEE_COLLECTOR");
        roleConfigs[FEE_COLLECTOR] = RoleConfig({
            role: FEE_COLLECTOR,
            name: "Fee Collector",
            description: "Can collect and distribute system fees",
            maxMembers: 5,
            minMembers: 2,
            isSensitive: true,
            approvalThreshold: 6600
        });
    }
    
    // Configuration d'un nouveau rôle
    function configureRole(
        bytes32 role,
        string memory name,
        string memory description,
        uint256 maxMembers,
        uint256 minMembers,
        bool isSensitive,
        uint256 approvalThreshold
    ) external onlyRole(SUPER_ADMIN) {
        require(maxMembers >= minMembers, "Invalid member limits");
        require(approvalThreshold <= 10000, "Invalid threshold");
        
        roleConfigs[role] = RoleConfig({
            role: role,
            name: name,
            description: description,
            maxMembers: maxMembers,
            minMembers: minMembers,
            isSensitive: isSensitive,
            approvalThreshold: approvalThreshold
        });
        
        emit RoleConfigured(role, name, description, maxMembers, minMembers, isSensitive);
    }
    
    // Attribution de rôle avec approbation multi-sig
    function grantRoleWithApproval(
        bytes32 role,
        address account,
        bytes[] memory signatures
    ) external {
        RoleConfig memory config = roleConfigs[role];
        require(config.role != bytes32(0), "Role not configured");
        
        // Vérifier le cooldown
        require(
            block.timestamp >= lastRoleChange[account][role] + roleChangeCooldown,
            "Cooldown period active"
        );
        
        // Vérifier la limite de membres
        require(
            roleMembers[role].length() < config.maxMembers,
            "Role member limit reached"
        );
        
        // Vérifier la limite de rôles par utilisateur
        require(
            userRoles[account].length < maxRolesPerUser,
            "User role limit reached"
        );
        
        // Pour les rôles sensibles, vérifier les signatures
        if (config.isSensitive) {
            uint256 approvalCount = _validateSignatures(role, account, true, signatures);
            require(
                approvalCount * 10000 >= config.approvalThreshold * roleMembers[role].length(),
                "Insufficient approvals"
            );
        }
        
        // Attribution du rôle
        _grantRole(role, account);
		roleMembers[role].push(account);
        
        // Mettre à jour les rôles de l'utilisateur
        userRoles[account].push(role);
        
        // Enregistrer le log
        permissionLogs[account].push(PermissionLog({
            user: account,
            role: role,
            granted: true,
            executor: msg.sender,
            timestamp: block.timestamp,
            reason: "Multi-sig approval"
        }));
        
        lastRoleChange[account][role] = block.timestamp;
        
        emit RoleGrantedWithApproval(
            role,
            account,
            msg.sender,
            config.isSensitive ? signatures.length : 1,
            block.timestamp
        );
    }
    
    // Révocation de rôle avec raison
    function revokeRoleWithReason(
        bytes32 role,
        address account,
        string memory reason
    ) external onlyRole(getRoleAdmin(role)) {
        require(hasRole(role, account), "Address does not have role");
        
        // Vérifier le minimum de membres
        RoleConfig memory config = roleConfigs[role];
        if (config.minMembers > 0) {
            require(
                roleMembers[role].length() > config.minMembers,
                "Cannot go below minimum members"
            );
        }
        
        _revokeRole(role, account);
        roleMembers[role].remove(account);
        
        // Retirer le rôle de la liste de l'utilisateur
        _removeUserRole(account, role);
        
        // Enregistrer le log
        permissionLogs[account].push(PermissionLog({
            user: account,
            role: role,
            granted: false,
            executor: msg.sender,
            timestamp: block.timestamp,
            reason: reason
        }));
        
        emit RoleRevokedWithReason(role, account, msg.sender, reason, block.timestamp);
    }
    
    // Enregistrement d'un contrat
    function registerContract(
        address contractAddress,
        string memory name,
        string memory version,
        string memory ipfsConfig
    ) external onlyRole(UPGRADE_MANAGER) {
        require(contractAddress != address(0), "Invalid contract address");
        require(!registeredContractsSet.contains(contractAddress), "Contract already registered");
        
        registeredContracts[contractAddress] = ContractRegistration({
            contractAddress: contractAddress,
            name: name,
            version: version,
            registeredAt: block.timestamp,
            registeredBy: msg.sender,
            isActive: true,
            ipfsConfig: ipfsConfig
        });
        
        registeredContractsSet.push(contractAddress);
        
        emit ContractRegistered(contractAddress, name, version, msg.sender, block.timestamp);
    }
    
    // Désactivation d'un contrat
    function deregisterContract(
        address contractAddress,
        string memory reason
    ) external onlyRole(SECURITY_ADMIN) {
        require(registeredContractsSet.contains(contractAddress), "Contract not registered");
        
        registeredContracts[contractAddress].isActive = false;
        
        emit ContractDeregistered(contractAddress, msg.sender, reason, block.timestamp);
    }
    
    // Vérification d'accès avec contexte
    function checkAccess(
        address user,
        bytes32 role,
        bytes memory context
    ) external view returns (bool hasAccess, string memory reason) {
        if (!hasRole(role, user)) {
            return (false, "User does not have required role");
        }
        
        ContractRegistration memory contractInfo = registeredContracts[msg.sender];
        if (!contractInfo.isActive) {
            return (false, "Calling contract is not active");
        }
        
        // Vérifications supplémentaires selon le contexte
        if (context.length > 0) {
            // Exemple: vérification de limites de temps pour certains rôles
            // À étendre selon les besoins spécifiques
        }
        
        return (true, "Access granted");
    }
    
    // Activation d'accès d'urgence
    function activateEmergencyAccess(
        uint256 duration,
        string memory emergencyReason
    ) external onlyRole(SECURITY_ADMIN) {
        // Créer un rôle d'urgence temporaire
        bytes32 emergencyRole = keccak256(abi.encodePacked(
            "EMERGENCY_ACCESS_",
            block.timestamp
        ));
        
        // Configuration temporaire
        roleConfigs[emergencyRole] = RoleConfig({
            role: emergencyRole,
            name: "Emergency Access",
            description: string(abi.encodePacked("Emergency access for: ", emergencyReason)),
            maxMembers: 3,
            minMembers: 1,
            isSensitive: true,
            approvalThreshold: 10000
        });
        
        // Attribution à l'exécuteur
        _grantRole(emergencyRole, msg.sender);
        roleMembers[emergencyRole].push(msg.sender);
        
        // Programmer la révocation automatique
        _scheduleRoleRevocation(emergencyRole, msg.sender, block.timestamp + duration);
        
        emit EmergencyAccessActivated(
            msg.sender,
            duration,
            emergencyReason,
            block.timestamp
        );
    }
    
    // Vérification KYC
    function isKYCCertified(address user) external view returns (bool) {
        // À intégrer avec KYCRegistry
        // Pour l'instant, retourne true pour les tests
        return true;
    }
    
    // Fonctions internes
    function _validateSignatures(
        bytes32 role,
        address account,
        bool grant,
        bytes[] memory signatures
    ) private view returns (uint256) {
        uint256 validSignatures = 0;
        bytes32 messageHash = keccak256(abi.encodePacked(
            role,
            account,
            grant,
            block.chainid,
            address(this)
        ));
        
        bytes32 ethSignedMessageHash = keccak256(
            abi.encodePacked("\x19Ethereum Signed Message:\n32", messageHash)
        );
        
        for (uint256 i = 0; i < signatures.length; i++) {
            address signer = _recoverSigner(ethSignedMessageHash, signatures[i]);
            if (hasRole(getRoleAdmin(role), signer)) {
                validSignatures++;
            }
        }
        
        return validSignatures;
    }
    
    function _recoverSigner(
        bytes32 ethSignedMessageHash,
        bytes memory signature
    ) private pure returns (address) {
        (bytes32 r, bytes32 s, uint8 v) = _splitSignature(signature);
        return ecrecover(ethSignedMessageHash, v, r, s);
    }
    
    function _splitSignature(bytes memory signature) private pure returns (bytes32 r, bytes32 s, uint8 v) {
        require(signature.length == 65, "Invalid signature length");
        
        assembly {
            r := mload(add(signature, 32))
            s := mload(add(signature, 64))
            v := byte(0, mload(add(signature, 96)))
        }
        
        if (v < 27) {
            v += 27;
        }
    }
    
    function _removeUserRole(address user, bytes32 role) private {
        bytes32[] storage roles = userRoles[user];
        for (uint256 i = 0; i < roles.length; i++) {
            if (roles[i] == role) {
                roles[i] = roles[roles.length - 1];
                roles.pop();
                break;
            }
        }
    }
    
    function _scheduleRoleRevocation(
        bytes32 role,
        address account,
        uint256 revocationTime
    ) private {
        // À implémenter: scheduler pour révocation automatique
        // Pourrait utiliser un contrat de timelock ou un scheduler externe
    }
    
    // Getters
    function getRoleMembers(bytes32 role) external view returns (address[] memory) {
        return roleMembers[role].values();
    }
    
    function getRoleMemberCount(bytes32 role) external view returns (uint256) {
        return roleMembers[role].length();
    }
    
    function getUserRoles(address user) external view returns (bytes32[] memory) {
        return userRoles[user];
    }
    
    function getPermissionLogs(
        address user,
        uint256 limit
    ) external view returns (PermissionLog[] memory) {
        PermissionLog[] storage logs = permissionLogs[user];
        
        if (limit == 0 || limit > logs.length) {
            limit = logs.length;
        }
        
        PermissionLog[] memory result = new PermissionLog[](limit);
        
        for (uint256 i = 0; i < limit; i++) {
            result[i] = logs[logs.length - 1 - i];
        }
        
        return result;
    }
    
    function getRegisteredContracts() external view returns (address[] memory) {
        return registeredContractsSet.values();
    }
    
    function getContractInfo(
        address contractAddress
    ) external view returns (ContractRegistration memory) {
        return registeredContracts[contractAddress];
    }
    
    function hasRoleWithContext(
        bytes32 role,
        address account,
        bytes memory context
    ) external view returns (bool) {
        // Vérification de base
        if (!hasRole(role, account)) {
            return false;
        }
        
        // Vérifications contextuelles supplémentaires
        // À implémenter selon les besoins
        return true;
    }
    
    // Override de la fonction standard pour utiliser notre logique
    function grantRole(bytes32 role, address account) public override onlyRole(getRoleAdmin(role)) {
        // Utiliser la fonction avec approbation pour les rôles sensibles
        RoleConfig memory config = roleConfigs[role];
        
        if (config.isSensitive) {
            revert("Use grantRoleWithApproval for sensitive roles");
        }
        
        super.grantRole(role, account);
        roleMembers[role].push(account);
        
        if (!_hasRoleInArray(userRoles[account], role)) {
            userRoles[account].push(role);
        }
    }
    
    function _hasRoleInArray(
        bytes32[] memory roles,
        bytes32 role
    ) private pure returns (bool) {
        for (uint256 i = 0; i < roles.length; i++) {
            if (roles[i] == role) {
                return true;
            }
        }
        return false;
    }
    
    // Fonction pour initialiser tous les rôles standards (appelée une fois)
    function initializeRoles() external onlyRole(DEFAULT_ADMIN_ROLE) {
        // Cette fonction est déjà appelée dans le constructeur
        // Existe pour compatibilité avec les scripts de déploiement
        emit RoleConfigured(SUPER_ADMIN, "Super Administrator", 
            "Full system access", 3, 1, true);
    }
}