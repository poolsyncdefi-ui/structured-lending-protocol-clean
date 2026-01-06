// SPDX-License-Identifier: MIT
pragma solidity ^0.8.19;

import "@openzeppelin/contracts/access/AccessControl.sol";
import "@openzeppelin/contracts/security/Pausable.sol";
import "@openzeppelin/contracts/utils/math/SafeMath.sol";
import "./AccessControllerV2.sol";

contract EmergencyExecutorV2 is AccessControl, Pausable {
    
    
    // Structures de données
    struct EmergencyAction {
        uint256 actionId;
        string actionType;
        address targetContract;
        bytes calldata;
        address proposedBy;
        uint256 proposedAt;
        uint256 approvedAt;
        uint256 executedAt;
        address executedBy;
        EmergencyStatus status;
        string description;
        string emergencyReason;
        uint256 requiredApprovals;
        uint256 currentApprovals;
        address[] approvers;
        bytes[] signatures;
    }
    
    struct EmergencyConfig {
        string actionType;
        uint256 requiredApprovals;
        uint256 executionDelay;
        uint256 validityPeriod;
        bool requiresMultisig;
        uint256 maxUsagePerPeriod;
        uint256 usedInPeriod;
        uint256 periodStart;
    }
    
    // Statuts
    enum EmergencyStatus {
        PROPOSED,
        APPROVED,
        EXECUTED,
        REJECTED,
        EXPIRED,
        CANCELLED
    }
    
    // Types d'actions d'urgence
    enum EmergencyActionType {
        PAUSE_SYSTEM,
        UNPAUSE_SYSTEM,
        WITHDRAW_FUNDS,
        FREEZE_USER,
        UNFREEZE_USER,
        ADJUST_PARAMETERS,
        UPGRADE_CONTRACT,
        MIGRATE_DATA,
        ACTIVATE_BACKUP,
        DECLARE_DISASTER
    }
    
    // Variables d'état
    mapping(uint256 => EmergencyAction) public emergencyActions;
    mapping(string => EmergencyConfig) public emergencyConfigs;
    mapping(address => uint256) public lastEmergencyAction;
    mapping(address => bool) public frozenAccounts;
    mapping(address => uint256) public freezeExpiry;
    
    AccessControllerV2 public accessController;
    
    uint256 public actionCounter;
    uint256 public emergencyCooldown = 1 hours;
    uint256 public maxActionsPerDay = 10;
    uint256 public actionsToday;
    uint256 public dayStart;
    
    // Garde-fous
    uint256 public maxWithdrawalPercentage = 10; // 10% maximum par action
    uint256 public minApprovalDelay = 15 minutes;
    uint256 public maxFreezeDuration = 30 days;
    
    // Rôles
    bytes32 public constant EMERGENCY_PROPOSER = keccak256("EMERGENCY_PROPOSER");
    bytes32 public constant EMERGENCY_APPROVER = keccak256("EMERGENCY_APPROVER");
    bytes32 public constant EMERGENCY_EXECUTOR = keccak256("EMERGENCY_EXECUTOR");
    
    // Événements
    event EmergencyActionProposed(
        uint256 indexed actionId,
        string actionType,
        address indexed targetContract,
        address indexed proposer,
        string emergencyReason,
        uint256 timestamp
    );
    
    event EmergencyActionApproved(
        uint256 indexed actionId,
        address indexed approver,
        uint256 approvalCount,
        uint256 timestamp
    );
    
    event EmergencyActionExecuted(
        uint256 indexed actionId,
        address indexed executor,
        bytes result,
        uint256 timestamp
    );
    
    event EmergencyActionRejected(
        uint256 indexed actionId,
        address indexed rejector,
        string reason,
        uint256 timestamp
    );
    
    event SystemPaused(
        address indexed pauser,
        string reason,
        uint256 duration,
        uint256 timestamp
    );
    
    event SystemUnpaused(
        address indexed unpauser,
        uint256 timestamp
    );
    
    event AccountFrozen(
        address indexed account,
        address indexed freezer,
        uint256 duration,
        string reason,
        uint256 timestamp
    );
    
    event AccountUnfrozen(
        address indexed account,
        address indexed unfreezer,
        uint256 timestamp
    );
    
    constructor(address _accessController) {
        accessController = AccessControllerV2(_accessController);
        
        _grantRole(DEFAULT_ADMIN_ROLE, msg.sender);
        _grantRole(EMERGENCY_PROPOSER, msg.sender);
        _grantRole(EMERGENCY_APPROVER, msg.sender);
        _grantRole(EMERGENCY_EXECUTOR, msg.sender);
        
        // Initialisation des configurations
        _initializeEmergencyConfigs();
        
        dayStart = block.timestamp;
    }
    
    // Initialisation des configurations d'urgence
    function _initializeEmergencyConfigs() private {
        // Configuration PAUSE_SYSTEM
        emergencyConfigs["PAUSE_SYSTEM"] = EmergencyConfig({
            actionType: "PAUSE_SYSTEM",
            requiredApprovals: 2,
            executionDelay: 5 minutes,
            validityPeriod: 24 hours,
            requiresMultisig: true,
            maxUsagePerPeriod: 3,
            usedInPeriod: 0,
            periodStart: block.timestamp
        });
        
        // Configuration UNPAUSE_SYSTEM
        emergencyConfigs["UNPAUSE_SYSTEM"] = EmergencyConfig({
            actionType: "UNPAUSE_SYSTEM",
            requiredApprovals: 2,
            executionDelay: 0,
            validityPeriod: 24 hours,
            requiresMultisig: true,
            maxUsagePerPeriod: 3,
            usedInPeriod: 0,
            periodStart: block.timestamp
        });
        
        // Configuration WITHDRAW_FUNDS
        emergencyConfigs["WITHDRAW_FUNDS"] = EmergencyConfig({
            actionType: "WITHDRAW_FUNDS",
            requiredApprovals: 3,
            executionDelay: 30 minutes,
            validityPeriod: 48 hours,
            requiresMultisig: true,
            maxUsagePerPeriod: 1,
            usedInPeriod: 0,
            periodStart: block.timestamp
        });
        
        // Configuration FREEZE_USER
        emergencyConfigs["FREEZE_USER"] = EmergencyConfig({
            actionType: "FREEZE_USER",
            requiredApprovals: 2,
            executionDelay: 10 minutes,
            validityPeriod: 12 hours,
            requiresMultisig: true,
            maxUsagePerPeriod: 10,
            usedInPeriod: 0,
            periodStart: block.timestamp
        });
        
        // Configuration UNFREEZE_USER
        emergencyConfigs["UNFREEZE_USER"] = EmergencyConfig({
            actionType: "UNFREEZE_USER",
            requiredApprovals: 1,
            executionDelay: 0,
            validityPeriod: 12 hours,
            requiresMultisig: false,
            maxUsagePerPeriod: 20,
            usedInPeriod: 0,
            periodStart: block.timestamp
        });
        
        // Configuration ADJUST_PARAMETERS
        emergencyConfigs["ADJUST_PARAMETERS"] = EmergencyConfig({
            actionType: "ADJUST_PARAMETERS",
            requiredApprovals: 2,
            executionDelay: 15 minutes,
            validityPeriod: 24 hours,
            requiresMultisig: true,
            maxUsagePerPeriod: 5,
            usedInPeriod: 0,
            periodStart: block.timestamp
        });
        
        // Configuration UPGRADE_CONTRACT
        emergencyConfigs["UPGRADE_CONTRACT"] = EmergencyConfig({
            actionType: "UPGRADE_CONTRACT",
            requiredApprovals: 3,
            executionDelay: 1 hours,
            validityPeriod: 72 hours,
            requiresMultisig: true,
            maxUsagePerPeriod: 1,
            usedInPeriod: 0,
            periodStart: block.timestamp
        });
        
        // Configuration DECLARE_DISASTER
        emergencyConfigs["DECLARE_DISASTER"] = EmergencyConfig({
            actionType: "DECLARE_DISASTER",
            requiredApprovals: 4,
            executionDelay: 0,
            validityPeriod: 168 hours, // 7 jours
            requiresMultisig: true,
            maxUsagePerPeriod: 1,
            usedInPeriod: 0,
            periodStart: block.timestamp
        });
    }
    
    // Proposition d'une action d'urgence
    function proposeEmergencyAction(
        string memory actionType,
        address targetContract,
        bytes memory calldataPayload,
        string memory description,
        string memory emergencyReason,
        bytes memory signature
    ) external onlyRole(EMERGENCY_PROPOSER) returns (uint256) {
        // Vérifier le cooldown
        require(
            block.timestamp >= lastEmergencyAction[msg.sender] + emergencyCooldown,
            "Emergency action cooldown active"
        );
        
        // Vérifier la limite quotidienne
        _checkDailyLimit();
        
        // Vérifier la configuration
        EmergencyConfig memory config = emergencyConfigs[actionType];
        require(bytes(config.actionType).length > 0, "Invalid action type");
        
        // Vérifier la limite d'utilisation
        require(
            config.usedInPeriod < config.maxUsagePerPeriod,
            "Max usage for this action type reached"
        );
        
        // Vérifier la signature pour les actions sensibles
        if (config.requiresMultisig) {
            _validateProposalSignature(
                actionType,
                targetContract,
                calldataPayload,
                emergencyReason,
                signature
            );
        }
        
        // Créer l'action
        uint256 actionId = ++actionCounter;
        
        emergencyActions[actionId] = EmergencyAction({
            actionId: actionId,
            actionType: actionType,
            targetContract: targetContract,
            calldata: calldataPayload,
            proposedBy: msg.sender,
            proposedAt: block.timestamp,
            approvedAt: 0,
            executedAt: 0,
            executedBy: address(0),
            status: EmergencyStatus.PROPOSED,
            description: description,
            emergencyReason: emergencyReason,
            requiredApprovals: config.requiredApprovals,
            currentApprovals: 0,
            approvers: new address[](0),
            signatures: new bytes[](0)
        });
        
        // Mettre à jour l'utilisation
        config.usedInPeriod++;
        emergencyConfigs[actionType] = config;
        
        // Mettre à jour le timestamp de dernière action
        lastEmergencyAction[msg.sender] = block.timestamp;
        actionsToday++;
        
        emit EmergencyActionProposed(
            actionId,
            actionType,
            targetContract,
            msg.sender,
            emergencyReason,
            block.timestamp
        );
        
        return actionId;
    }
    
    // Approbation d'une action d'urgence
    function approveEmergencyAction(
        uint256 actionId,
        bytes memory signature
    ) external onlyRole(EMERGENCY_APPROVER) {
        EmergencyAction storage action = emergencyActions[actionId];
        
        require(action.status == EmergencyStatus.PROPOSED, "Action not in proposed state");
        require(action.currentApprovals < action.requiredApprovals, "Already approved");
        
        // Vérifier que l'approbateur n'a pas déjà approuvé
        for (uint256 i = 0; i < action.approvers.length; i++) {
            require(action.approvers[i] != msg.sender, "Already approved this action");
        }
        
        // Vérifier la signature
        _validateApprovalSignature(actionId, signature);
        
        // Vérifier la validité
        EmergencyConfig memory config = emergencyConfigs[action.actionType];
        require(
            block.timestamp <= action.proposedAt + config.validityPeriod,
            "Action proposal expired"
        );
        
        // Ajouter l'approbation
        action.currentApprovals++;
        action.approvers.push(msg.sender);
        action.signatures.push(signature);
        
        // Si les approbations requises sont atteintes
        if (action.currentApprovals >= action.requiredApprovals) {
            action.status = EmergencyStatus.APPROVED;
            action.approvedAt = block.timestamp;
        }
        
        emit EmergencyActionApproved(
            actionId,
            msg.sender,
            action.currentApprovals,
            block.timestamp
        );
    }
    
    // Exécution d'une action d'urgence
    function executeEmergencyAction(
        uint256 actionId
    ) external onlyRole(EMERGENCY_EXECUTOR) returns (bytes memory) {
        EmergencyAction storage action = emergencyActions[actionId];
        
        require(action.status == EmergencyStatus.APPROVED, "Action not approved");
        
        EmergencyConfig memory config = emergencyConfigs[action.actionType];
        
        // Vérifier le délai d'exécution
        require(
            block.timestamp >= action.approvedAt + config.executionDelay,
            "Execution delay not passed"
        );
        
        // Vérifier que l'action n'a pas expiré
        require(
            block.timestamp <= action.proposedAt + config.validityPeriod,
            "Action expired"
        );
        
        // Exécuter l'action
        bytes memory result;
        bool success;
        
        if (keccak256(bytes(action.actionType)) == keccak256(bytes("PAUSE_SYSTEM"))) {
            _pauseSystem(action.emergencyReason);
            result = abi.encode("System paused");
        } else if (keccak256(bytes(action.actionType)) == keccak256(bytes("UNPAUSE_SYSTEM"))) {
            _unpauseSystem();
            result = abi.encode("System unpaused");
        } else if (keccak256(bytes(action.actionType)) == keccak256(bytes("FREEZE_USER"))) {
            (address user, uint256 duration, string memory reason) = 
                abi.decode(action.calldata, (address, uint256, string));
            _freezeAccount(user, duration, reason);
            result = abi.encode("Account frozen");
        } else if (keccak256(bytes(action.actionType)) == keccak256(bytes("UNFREEZE_USER"))) {
            address user = abi.decode(action.calldata, (address));
            _unfreezeAccount(user);
            result = abi.encode("Account unfrozen");
        } else {
            // Action contractuelle générique
            (success, result) = action.targetContract.call(action.calldata);
            require(success, "Emergency action execution failed");
        }
        
        // Mettre à jour l'action
        action.status = EmergencyStatus.EXECUTED;
        action.executedAt = block.timestamp;
        action.executedBy = msg.sender;
        
        emit EmergencyActionExecuted(actionId, msg.sender, result, block.timestamp);
        
        return result;
    }
    
    // Rejet d'une action d'urgence
    function rejectEmergencyAction(
        uint256 actionId,
        string memory reason
    ) external onlyRole(EMERGENCY_APPROVER) {
        EmergencyAction storage action = emergencyActions[actionId];
        
        require(
            action.status == EmergencyStatus.PROPOSED || 
            action.status == EmergencyStatus.APPROVED,
            "Cannot reject in current state"
        );
        
        action.status = EmergencyStatus.REJECTED;
        
        // Libérer l'utilisation dans la configuration
        EmergencyConfig storage config = emergencyConfigs[action.actionType];
        if (config.usedInPeriod > 0) {
            config.usedInPeriod--;
        }
        
        emit EmergencyActionRejected(actionId, msg.sender, reason, block.timestamp);
    }
    
    // Annulation d'une action d'urgence par le proposant
    function cancelEmergencyAction(uint256 actionId) external {
        EmergencyAction storage action = emergencyActions[actionId];
        
        require(
            action.proposedBy == msg.sender ||
            hasRole(DEFAULT_ADMIN_ROLE, msg.sender),
            "Not authorized to cancel"
        );
        
        require(
            action.status == EmergencyStatus.PROPOSED,
            "Cannot cancel in current state"
        );
        
        action.status = EmergencyStatus.CANCELLED;
        
        // Libérer l'utilisation
        EmergencyConfig storage config = emergencyConfigs[action.actionType];
        if (config.usedInPeriod > 0) {
            config.usedInPeriod--;
        }
    }
    
    // Fonction de secours pour geler un compte immédiatement (sans approbation)
    function emergencyFreezeAccount(
        address account,
        uint256 duration,
        string memory reason,
        bytes[] memory signatures
    ) external onlyRole(EMERGENCY_EXECUTOR) {
        require(duration <= maxFreezeDuration, "Freeze duration too long");
        
        // Vérifier les signatures d'urgence
        require(
            _validateEmergencyFreezeSignatures(account, duration, reason, signatures) >= 2,
            "Insufficient emergency signatures"
        );
        
        _freezeAccount(account, duration, reason);
    }
    
    // Fonction de secours pour retirer des fonds immédiatement
    function emergencyWithdraw(
        address token,
        address recipient,
        uint256 amount,
        string memory reason,
        bytes[] memory signatures
    ) external onlyRole(EMERGENCY_EXECUTOR) returns (bool) {
        // Vérifier les signatures
        require(
            _validateEmergencyWithdrawSignatures(token, recipient, amount, reason, signatures) >= 3,
            "Insufficient emergency signatures"
        );
        
        // Limiter le pourcentage de retrait
        // À implémenter: vérification du solde total
        
        // Exécuter le retrait
        (bool success, ) = token.call(
            abi.encodeWithSignature(
                "transfer(address,uint256)",
                recipient,
                amount
            )
        );
        
        require(success, "Emergency withdrawal failed");
        
        return true;
    }
    
    // Fonctions internes
    function _checkDailyLimit() private {
        // Réinitialiser le compteur quotidien si nécessaire
        if (block.timestamp >= dayStart + 1 days) {
            actionsToday = 0;
            dayStart = block.timestamp;
        }
        
        require(actionsToday < maxActionsPerDay, "Daily emergency action limit reached");
    }
    
    function _validateProposalSignature(
        string memory actionType,
        address targetContract,
        bytes memory calldataPayload,
        string memory emergencyReason,
        bytes memory signature
    ) private view {
        bytes32 messageHash = keccak256(abi.encodePacked(
            actionType,
            targetContract,
            calldataPayload,
            emergencyReason,
            block.chainid,
            address(this),
            "EMERGENCY_PROPOSAL"
        ));
        
        bytes32 ethSignedMessageHash = keccak256(
            abi.encodePacked("\x19Ethereum Signed Message:\n32", messageHash)
        );
        
        address recovered = _recoverSigner(ethSignedMessageHash, signature);
        
        require(
            hasRole(EMERGENCY_PROPOSER, recovered) ||
            hasRole(DEFAULT_ADMIN_ROLE, recovered),
            "Invalid proposal signature"
        );
    }
    
    function _validateApprovalSignature(
        uint256 actionId,
        bytes memory signature
    ) private view {
        bytes32 messageHash = keccak256(abi.encodePacked(
            actionId,
            block.chainid,
            address(this),
            "EMERGENCY_APPROVAL"
        ));
        
        bytes32 ethSignedMessageHash = keccak256(
            abi.encodePacked("\x19Ethereum Signed Message:\n32", messageHash)
        );
        
        address recovered = _recoverSigner(ethSignedMessageHash, signature);
        
        require(
            hasRole(EMERGENCY_APPROVER, recovered) ||
            hasRole(DEFAULT_ADMIN_ROLE, recovered),
            "Invalid approval signature"
        );
    }
    
    function _validateEmergencyFreezeSignatures(
        address account,
        uint256 duration,
        string memory reason,
        bytes[] memory signatures
    ) private view returns (uint256) {
        uint256 validSignatures = 0;
        bytes32 messageHash = keccak256(abi.encodePacked(
            account,
            duration,
            reason,
            block.chainid,
            address(this),
            "EMERGENCY_FREEZE"
        ));
        
        bytes32 ethSignedMessageHash = keccak256(
            abi.encodePacked("\x19Ethereum Signed Message:\n32", messageHash)
        );
        
        for (uint256 i = 0; i < signatures.length; i++) {
            address signer = _recoverSigner(ethSignedMessageHash, signatures[i]);
            if (hasRole(EMERGENCY_EXECUTOR, signer) || hasRole(DEFAULT_ADMIN_ROLE, signer)) {
                validSignatures++;
            }
        }
        
        return validSignatures;
    }
    
    function _validateEmergencyWithdrawSignatures(
        address token,
        address recipient,
        uint256 amount,
        string memory reason,
        bytes[] memory signatures
    ) private view returns (uint256) {
        uint256 validSignatures = 0;
        bytes32 messageHash = keccak256(abi.encodePacked(
            token,
            recipient,
            amount,
            reason,
            block.chainid,
            address(this),
            "EMERGENCY_WITHDRAW"
        ));
        
        bytes32 ethSignedMessageHash = keccak256(
            abi.encodePacked("\x19Ethereum Signed Message:\n32", messageHash)
        );
        
        for (uint256 i = 0; i < signatures.length; i++) {
            address signer = _recoverSigner(ethSignedMessageHash, signatures[i]);
            if (hasRole(EMERGENCY_EXECUTOR, signer) || hasRole(DEFAULT_ADMIN_ROLE, signer)) {
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
    
    function _pauseSystem(string memory reason) private whenNotPaused {
        _pause();
        
        emit SystemPaused(
            msg.sender,
            reason,
            emergencyConfigs["PAUSE_SYSTEM"].validityPeriod,
            block.timestamp
        );
    }
    
    function _unpauseSystem() private whenPaused {
        _unpause();
        
        emit SystemUnpaused(msg.sender, block.timestamp);
    }
    
    function _freezeAccount(
        address account,
        uint256 duration,
        string memory reason
    ) private {
        require(account != address(0), "Invalid account");
        require(duration <= maxFreezeDuration, "Duration too long");
        
        frozenAccounts[account] = true;
        freezeExpiry[account] = block.timestamp + duration;
        
        emit AccountFrozen(account, msg.sender, duration, reason, block.timestamp);
    }
    
    function _unfreezeAccount(address account) private {
        require(frozenAccounts[account], "Account not frozen");
        
        frozenAccounts[account] = false;
        freezeExpiry[account] = 0;
        
        emit AccountUnfrozen(account, msg.sender, block.timestamp);
    }
    
    // Getters
    function getEmergencyAction(uint256 actionId) external view returns (EmergencyAction memory) {
        return emergencyActions[actionId];
    }
    
    function getPendingActions() external view returns (uint256[] memory) {
        uint256 pendingCount = 0;
        
        // Compter les actions en attente
        for (uint256 i = 1; i <= actionCounter; i++) {
            if (emergencyActions[i].status == EmergencyStatus.PROPOSED ||
                emergencyActions[i].status == EmergencyStatus.APPROVED) {
                pendingCount++;
            }
        }
        
        // Collecter les IDs
        uint256[] memory pendingIds = new uint256[](pendingCount);
        uint256 index = 0;
        
        for (uint256 i = 1; i <= actionCounter; i++) {
            if (emergencyActions[i].status == EmergencyStatus.PROPOSED ||
                emergencyActions[i].status == EmergencyStatus.APPROVED) {
                pendingIds[index] = i;
                index++;
            }
        }
        
        return pendingIds;
    }
    
    function isAccountFrozen(address account) external view returns (bool) {
        if (!frozenAccounts[account]) {
            return false;
        }
        
        // Vérifier l'expiration
        if (block.timestamp > freezeExpiry[account]) {
            return false;
        }
        
        return true;
    }
    
    function getFreezeExpiry(address account) external view returns (uint256) {
        return freezeExpiry[account];
    }
    
    function getEmergencyConfig(string memory actionType) external view returns (EmergencyConfig memory) {
        return emergencyConfigs[actionType];
    }
    
    function getTodayStats() external view returns (uint256 actions, uint256 remaining) {
        uint256 today = block.timestamp / 1 days;
        uint256 startDay = dayStart / 1 days;
        
        if (today > startDay) {
            return (0, maxActionsPerDay);
        }
        
        return (actionsToday, maxActionsPerDay - actionsToday);
    }
    
    // Configuration
    function setEmergencyCooldown(uint256 newCooldown) external onlyRole(DEFAULT_ADMIN_ROLE) {
        emergencyCooldown = newCooldown;
    }
    
    function setMaxActionsPerDay(uint256 newMax) external onlyRole(DEFAULT_ADMIN_ROLE) {
        maxActionsPerDay = newMax;
    }
    
    function setMaxFreezeDuration(uint256 newDuration) external onlyRole(DEFAULT_ADMIN_ROLE) {
        maxFreezeDuration = newDuration;
    }
    
    function updateEmergencyConfig(
        string memory actionType,
        uint256 requiredApprovals,
        uint256 executionDelay,
        uint256 validityPeriod,
        bool requiresMultisig,
        uint256 maxUsagePerPeriod
    ) external onlyRole(DEFAULT_ADMIN_ROLE) {
        EmergencyConfig storage config = emergencyConfigs[actionType];
        
        config.requiredApprovals = requiredApprovals;
        config.executionDelay = executionDelay;
        config.validityPeriod = validityPeriod;
        config.requiresMultisig = requiresMultisig;
        config.maxUsagePerPeriod = maxUsagePerPeriod;
        
        // Réinitialiser la période si nécessaire
        if (block.timestamp >= config.periodStart + 30 days) {
            config.usedInPeriod = 0;
            config.periodStart = block.timestamp;
        }
    }
    
    // Fonction pour dégeler les comptes expirés
    function cleanupExpiredFreezes() external {
        uint256 cleaned = 0;
        
        // Cette fonction peut être appelée par n'importe qui pour nettoyer les freezes expirés
        for (uint256 i = 0; i < 100; i++) { // Limiter à 100 itérations par transaction
            // Note: Dans une implémentation réelle, nous aurions besoin d'une liste des comptes gelés
            // Pour cette démo, nous utilisons une approche simplifiée
            break;
        }
    }
    
    // Override de la fonction pause pour utiliser notre logique
    function pause() public override onlyRole(EMERGENCY_EXECUTOR) {
        super.pause();
    }
    
    function unpause() public override onlyRole(EMERGENCY_EXECUTOR) {
        super.unpause();
    }
}