// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import "@openzeppelin/contracts/access/AccessControl.sol";

contract NotificationManager is AccessControl {
    // Types de notifications
    enum NotificationType {
        LOAN_CREATED,
        LOAN_REPAYMENT_DUE,
        LOAN_DEFAULT,
        INSURANCE_CLAIM,
        GOVERNANCE_PROPOSAL,
        MARKET_LISTING,
        PRICE_ALERT,
        SYSTEM_UPDATE,
        SECURITY_ALERT
    }
    
    // Priorités
    enum Priority {
        LOW,
        MEDIUM,
        HIGH,
        CRITICAL
    }
    
    // Structure de notification
    struct Notification {
        uint256 notificationId;
        address recipient;
        NotificationType notificationType;
        Priority priority;
        string title;
        string message;
        bytes data;
        uint256 timestamp;
        bool isRead;
        bool isArchived;
    }
    
    // Préférences utilisateur
    struct UserPreferences {
        bool emailNotifications;
        bool pushNotifications;
        bool smsNotifications;
        uint256[] subscribedTypes;
        uint256 quietHoursStart;
        uint256 quietHoursEnd;
    }
    
    // Variables d'état
    mapping(address => Notification[]) public userNotifications;
    mapping(address => UserPreferences) public userPreferences;
    mapping(uint256 => address) public notificationSenders;
    
    uint256 public notificationCount;
    uint256 public maxNotificationsPerUser = 1000;
    
    // Contrats autorisés à envoyer des notifications
    mapping(address => bool) public authorizedSenders;
    
    // Événements
    event NotificationSent(
        uint256 indexed notificationId,
        address indexed recipient,
        NotificationType notificationType,
        Priority priority,
        uint256 timestamp
    );
    
    event NotificationRead(
        uint256 indexed notificationId,
        address indexed recipient,
        uint256 readTime
    );
    
    event PreferencesUpdated(
        address indexed user,
        bool emailNotifications,
        bool pushNotifications,
        uint256 timestamp
    );
    
    // Rôles
    bytes32 public constant NOTIFICATION_SENDER = keccak256("NOTIFICATION_SENDER");
    
    constructor() {
        _grantRole(DEFAULT_ADMIN_ROLE, msg.sender);
        _grantRole(NOTIFICATION_SENDER, msg.sender);
    }
    
    // Envoi de notification par un contrat autorisé
    function sendNotification(
        address recipient,
        NotificationType notificationType,
        Priority priority,
        string memory title,
        string memory message,
        bytes memory data
    ) public onlyRole(NOTIFICATION_SENDER) returns (uint256) {
        require(recipient != address(0), "Invalid recipient");
        
        // Vérifier les préférences utilisateur
        UserPreferences memory prefs = userPreferences[recipient];
        if (!_shouldSendNotification(recipient, notificationType, prefs)) {
            return 0;
        }
        
        // Créer la notification
        uint256 notificationId = ++notificationCount;
        
        Notification memory newNotification = Notification({
            notificationId: notificationId,
            recipient: recipient,
            notificationType: notificationType,
            priority: priority,
            title: title,
            message: message,
            data: data,
            timestamp: block.timestamp,
            isRead: false,
            isArchived: false
        });
        
        // Ajouter à la liste de l'utilisateur
        userNotifications[recipient].push(newNotification);
        
        // Gérer la limite de notifications
        _manageNotificationLimit(recipient);
        
        // Enregistrer l'expéditeur
        notificationSenders[notificationId] = msg.sender;
        
        emit NotificationSent(
            notificationId,
            recipient,
            notificationType,
            priority,
            block.timestamp
        );
        
        return notificationId;
    }
    
    // Envoi de notification groupée
    function sendBulkNotification(
        address[] memory recipients,
        NotificationType notificationType,
        Priority priority,
        string memory title,
        string memory message
    ) external onlyRole(NOTIFICATION_SENDER) returns (uint256[] memory) {
        require(recipients.length <= 100, "Too many recipients");
        
        uint256[] memory notificationIds = new uint256[](recipients.length);
        
        for (uint256 i = 0; i < recipients.length; i++) {
            notificationIds[i] = sendNotification(
                recipients[i],
                notificationType,
                priority,
                title,
                message,
                ""
            );
        }
        
        return notificationIds;
    }
    
    // Marquer une notification comme lue
    function markAsRead(uint256 notificationId) external {
        Notification[] storage notifications = userNotifications[msg.sender];
        
        for (uint256 i = 0; i < notifications.length; i++) {
            if (notifications[i].notificationId == notificationId) {
                require(!notifications[i].isRead, "Already read");
                
                notifications[i].isRead = true;
                
                emit NotificationRead(notificationId, msg.sender, block.timestamp);
                return;
            }
        }
        
        revert("Notification not found");
    }
    
    // Marquer toutes les notifications comme lues
    function markAllAsRead() external {
        Notification[] storage notifications = userNotifications[msg.sender];
        uint256 markedCount = 0;
        
        for (uint256 i = 0; i < notifications.length; i++) {
            if (!notifications[i].isRead) {
                notifications[i].isRead = true;
                markedCount++;
                
                emit NotificationRead(
                    notifications[i].notificationId,
                    msg.sender,
                    block.timestamp
                );
            }
        }
    }
    
    // Archiver une notification
    function archiveNotification(uint256 notificationId) external {
        Notification[] storage notifications = userNotifications[msg.sender];
        
        for (uint256 i = 0; i < notifications.length; i++) {
            if (notifications[i].notificationId == notificationId) {
                notifications[i].isArchived = true;
                return;
            }
        }
        
        revert("Notification not found");
    }
    
    // Mettre à jour les préférences
    function updatePreferences(
        bool emailNotifications,
        bool pushNotifications,
        bool smsNotifications,
        uint256[] memory subscribedTypes,
        uint256 quietHoursStart,
        uint256 quietHoursEnd
    ) external {
        userPreferences[msg.sender] = UserPreferences({
            emailNotifications: emailNotifications,
            pushNotifications: pushNotifications,
            smsNotifications: smsNotifications,
            subscribedTypes: subscribedTypes,
            quietHoursStart: quietHoursStart,
            quietHoursEnd: quietHoursEnd
        });
        
        emit PreferencesUpdated(
            msg.sender,
            emailNotifications,
            pushNotifications,
            block.timestamp
        );
    }
    
    // Récupérer les notifications non lues
    function getUnreadNotifications() external view returns (Notification[] memory) {
        Notification[] storage allNotifications = userNotifications[msg.sender];
        uint256 unreadCount = 0;
        
        // Compter les notifications non lues
        for (uint256 i = 0; i < allNotifications.length; i++) {
            if (!allNotifications[i].isRead && !allNotifications[i].isArchived) {
                unreadCount++;
            }
        }
        
        // Collecter les notifications non lues
        Notification[] memory unread = new Notification[](unreadCount);
        uint256 index = 0;
        
        for (uint256 i = 0; i < allNotifications.length; i++) {
            if (!allNotifications[i].isRead && !allNotifications[i].isArchived) {
                unread[index] = allNotifications[i];
                index++;
            }
        }
        
        return unread;
    }
    
    // Récupérer les notifications par type
    function getNotificationsByType(NotificationType notificationType) 
        external 
        view 
        returns (Notification[] memory) 
    {
        Notification[] storage allNotifications = userNotifications[msg.sender];
        uint256 matchingCount = 0;
        
        // Compter les notifications correspondantes
        for (uint256 i = 0; i < allNotifications.length; i++) {
            if (allNotifications[i].notificationType == notificationType && 
                !allNotifications[i].isArchived) {
                matchingCount++;
            }
        }
        
        // Collecter les notifications
        Notification[] memory matching = new Notification[](matchingCount);
        uint256 index = 0;
        
        for (uint256 i = 0; i < allNotifications.length; i++) {
            if (allNotifications[i].notificationType == notificationType && 
                !allNotifications[i].isArchived) {
                matching[index] = allNotifications[i];
                index++;
            }
        }
        
        return matching;
    }
    
    // Récupérer les notifications par priorité
    function getNotificationsByPriority(Priority priority) 
        external 
        view 
        returns (Notification[] memory) 
    {
        Notification[] storage allNotifications = userNotifications[msg.sender];
        uint256 matchingCount = 0;
        
        // Compter les notifications correspondantes
        for (uint256 i = 0; i < allNotifications.length; i++) {
            if (allNotifications[i].priority == priority && 
                !allNotifications[i].isArchived) {
                matchingCount++;
            }
        }
        
        // Collecter les notifications
        Notification[] memory matching = new Notification[](matchingCount);
        uint256 index = 0;
        
        for (uint256 i = 0; i < allNotifications.length; i++) {
            if (allNotifications[i].priority == priority && 
                !allNotifications[i].isArchived) {
                matching[index] = allNotifications[i];
                index++;
            }
        }
        
        return matching;
    }
    
    // Supprimer les notifications archivées
    function cleanupArchived() external {
        Notification[] storage notifications = userNotifications[msg.sender];
        uint256 newLength = 0;
        
        // Déplacer les notifications non archivées au début du tableau
        for (uint256 i = 0; i < notifications.length; i++) {
            if (!notifications[i].isArchived) {
                notifications[newLength] = notifications[i];
                newLength++;
            }
        }
        
        // Réduire la taille du tableau
        while (notifications.length > newLength) {
            notifications.pop();
        }
    }
    
    // Fonctions internes
    function _shouldSendNotification(
        address recipient,
        NotificationType notificationType,
        UserPreferences memory prefs
    ) private view returns (bool) {
        // Vérifier les heures silencieuses
        uint256 currentHour = (block.timestamp / 3600) % 24;
        if (currentHour >= prefs.quietHoursStart && currentHour < prefs.quietHoursEnd) {
            return false;
        }
        
        // Vérifier les types abonnés
        bool isSubscribed = false;
        for (uint256 i = 0; i < prefs.subscribedTypes.length; i++) {
            if (prefs.subscribedTypes[i] == uint256(notificationType)) {
                isSubscribed = true;
                break;
            }
        }
        
        if (prefs.subscribedTypes.length > 0 && !isSubscribed) {
            return false;
        }
        
        return true;
    }
    
    function _manageNotificationLimit(address user) private {
        Notification[] storage notifications = userNotifications[user];
        
        if (notifications.length > maxNotificationsPerUser) {
            // Supprimer les plus anciennes notifications archivées
            uint256 toRemove = notifications.length - maxNotificationsPerUser;
            uint256 removed = 0;
            uint256 i = 0;
            
            while (removed < toRemove && i < notifications.length) {
                if (notifications[i].isArchived) {
                    // Déplacer les éléments suivants
                    for (uint256 j = i; j < notifications.length - 1; j++) {
                        notifications[j] = notifications[j + 1];
                    }
                    notifications.pop();
                    removed++;
                } else {
                    i++;
                }
            }
            
            // Si toujours au-dessus de la limite, supprimer les plus anciennes non archivées
            if (notifications.length > maxNotificationsPerUser) {
                uint256 remainingToRemove = notifications.length - maxNotificationsPerUser;
                for (uint256 k = 0; k < remainingToRemove; k++) {
                    // Déplacer tous les éléments d'une position
                    for (uint256 l = 0; l < notifications.length - 1; l++) {
                        notifications[l] = notifications[l + 1];
                    }
                    notifications.pop();
                }
            }
        }
    }
    
    // Autoriser un contrat à envoyer des notifications
    function authorizeSender(address sender) external onlyRole(DEFAULT_ADMIN_ROLE) {
        authorizedSenders[sender] = true;
        _grantRole(NOTIFICATION_SENDER, sender);
    }
    
    // Révoquer l'autorisation d'un expéditeur
    function revokeSender(address sender) external onlyRole(DEFAULT_ADMIN_ROLE) {
        authorizedSenders[sender] = false;
        _revokeRole(NOTIFICATION_SENDER, sender);
    }
    
    // Getters
    function getNotificationCount(address user) external view returns (uint256) {
        return userNotifications[user].length;
    }
    
    function getUnreadCount(address user) external view returns (uint256) {
        uint256 count = 0;
        Notification[] storage notifications = userNotifications[user];
        
        for (uint256 i = 0; i < notifications.length; i++) {
            if (!notifications[i].isRead && !notifications[i].isArchived) {
                count++;
            }
        }
        
        return count;
    }
    
    function getUserPreferences(address user) external view returns (
        bool emailNotifications,
        bool pushNotifications,
        bool smsNotifications,
        uint256[] memory subscribedTypes
    ) {
        UserPreferences memory prefs = userPreferences[user];
        return (
            prefs.emailNotifications,
            prefs.pushNotifications,
            prefs.smsNotifications,
            prefs.subscribedTypes
        );
    }
    
    // Templates de notifications prédéfinis
    function sendLoanCreatedNotification(
        address borrower,
        uint256 loanId,
        uint256 amount
    ) external onlyRole(NOTIFICATION_SENDER) returns (uint256) {
        string memory title = "Loan Created Successfully";
        string memory message = string(abi.encodePacked(
            "Your loan #",
            _toString(loanId),
            " for ",
            _toString(amount / 1e18),
            " tokens has been created and is now active."
        ));
        
        bytes memory data = abi.encode(loanId, amount);
        
        return sendNotification(
            borrower,
            NotificationType.LOAN_CREATED,
            Priority.MEDIUM,
            title,
            message,
            data
        );
    }
    
    function sendRepaymentDueNotification(
        address borrower,
        uint256 loanId,
        uint256 dueAmount,
        uint256 dueDate
    ) external onlyRole(NOTIFICATION_SENDER) returns (uint256) {
        string memory title = "Loan Repayment Due";
        string memory message = string(abi.encodePacked(
            "Reminder: Payment for loan #",
            _toString(loanId),
            " of ",
            _toString(dueAmount / 1e18),
            " tokens is due on ",
            _timestampToString(dueDate)
        ));
        
        bytes memory data = abi.encode(loanId, dueAmount, dueDate);
        
        return sendNotification(
            borrower,
            NotificationType.LOAN_REPAYMENT_DUE,
            Priority.HIGH,
            title,
            message,
            data
        );
    }
    
    function sendGovernanceProposalNotification(
        address voter,
        uint256 proposalId,
        string memory proposalTitle
    ) external onlyRole(NOTIFICATION_SENDER) returns (uint256) {
        string memory title = "New Governance Proposal";
        string memory message = string(abi.encodePacked(
            "A new proposal #",
            _toString(proposalId),
            ": ",
            proposalTitle,
            " is available for voting."
        ));
        
        bytes memory data = abi.encode(proposalId);
        
        return sendNotification(
            voter,
            NotificationType.GOVERNANCE_PROPOSAL,
            Priority.MEDIUM,
            title,
            message,
            data
        );
    }
    
    // Fonctions utilitaires
    function _toString(uint256 value) private pure returns (string memory) {
        if (value == 0) return "0";
        
        uint256 temp = value;
        uint256 digits;
        while (temp != 0) {
            digits++;
            temp /= 10;
        }
        
        bytes memory buffer = new bytes(digits);
        while (value != 0) {
            digits -= 1;
            buffer[digits] = bytes1(uint8(48 + uint256(value % 10)));
            value /= 10;
        }
        
        return string(buffer);
    }
    
    function _timestampToString(uint256 timestamp) private pure returns (string memory) {
        // Conversion simplifiée de timestamp en date
        // En production, utiliser une bibliothèque plus complète
        return string(abi.encodePacked(
            _toString((timestamp / 86400) % 30 + 1), // Jour
            "/",
            _toString((timestamp / 2592000) % 12 + 1), // Mois
            "/",
            _toString(1970 + timestamp / 31536000) // Année
        ));
    }
}