// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/token/ERC20/extensions/ERC20Votes.sol";
import "@openzeppelin/contracts/access/AccessControl.sol";
import "@openzeppelin/contracts/governance/Governor.sol";
import "@openzeppelin/contracts/governance/extensions/GovernorSettings.sol";
import "@openzeppelin/contracts/governance/extensions/GovernorCountingSimple.sol";
import "@openzeppelin/contracts/governance/extensions/GovernorVotes.sol";
import "@openzeppelin/contracts/governance/extensions/GovernorVotesQuorumFraction.sol";
import "@openzeppelin/contracts/governance/extensions/GovernorTimelockControl.sol";
import "./ReputationToken.sol";

contract GovernanceDAO is 
    Governor, 
    GovernorSettings,
    GovernorCountingSimple,
    GovernorVotes,
    GovernorVotesQuorumFraction,
    GovernorTimelockControl,
    AccessControl
{
    // Structure de proposition enrichie
    struct EnhancedProposal {
        uint256 proposalId;
        address proposer;
        string title;
        string description;
        ProposalCategory category;
        uint256 createdTime;
        uint256 votingEndTime;
        ProposalStatus status;
        bytes[] calldatas;
        address[] targets;
        uint256 forVotes;
        uint256 againstVotes;
        uint256 abstainVotes;
        uint256 executionTime;
        string ipfsMetadata;
    }
    
    // Catégories de propositions
    enum ProposalCategory {
        PARAMETER_CHANGE,     // Changement de paramètres
        TREASURY_MANAGEMENT,  // Gestion de trésorerie
        CONTRACT_UPGRADE,     // Mise à jour de contrat
        EMERGENCY_ACTION,     // Action d'urgence
        COMMUNITY_GRANT,      // Subvention communautaire
        RISK_MANAGEMENT,      // Gestion des risques
        INSURANCE_POLICY,     // Politique d'assurance
        FEE_STRUCTURE         // Structure de frais
    }
    
    // Statuts étendus
    enum ProposalStatus {
        PENDING,
        ACTIVE,
        CANCELED,
        DEFEATED,
        SUCCEEDED,
        QUEUED,
        EXECUTED,
        EXPIRED
    }
    
    // Structures de délégation
    struct Delegation {
        address delegatee;
        uint256 amount;
        uint256 timestamp;
    }
    
    // Variables d'état
    mapping(uint256 => EnhancedProposal) public enhancedProposals;
    mapping(address => Delegation[]) public delegationHistory;
    mapping(address => uint256) public reputationScores;
    
    uint256 public proposalCount;
    uint256 public minimumReputation = 100;
    uint256 public proposalDeposit = 100 * 1e18; // 100 tokens
    
    // Token de réputation
    ReputationToken public reputationToken;
    
    // Événements
    event ProposalCreated(
        uint256 indexed proposalId,
        address indexed proposer,
        string title,
        ProposalCategory category,
        uint256 timestamp
    );
    
    event VoteCast(
        uint256 indexed proposalId,
        address indexed voter,
        uint256 votes,
        uint256 reputationWeight,
        string support,
        uint256 timestamp
    );
    
    event ProposalExecuted(
        uint256 indexed proposalId,
        address indexed executor,
        uint256 timestamp
    );
    
    event ReputationAwarded(
        address indexed user,
        uint256 amount,
        string reason,
        uint256 timestamp
    );
    
    constructor(
        ERC20Votes _token,
        TimelockController _timelock,
        address _reputationToken
    )
        Governor("StructuredLendingGovernor")
        GovernorSettings(1, 50400, 0) // 1 block voting delay, 1 week voting period, 0 proposal threshold
        GovernorVotes(_token)
        GovernorVotesQuorumFraction(4) // 4% quorum
        GovernorTimelockControl(_timelock)
    {
        reputationToken = ReputationToken(_reputationToken);
        _grantRole(DEFAULT_ADMIN_ROLE, msg.sender);
    }
    
    // Création de proposition améliorée
    function proposeEnhanced(
        address[] memory targets,
        uint256[] memory values,
        bytes[] memory calldatas,
        string memory description,
        string memory title,
        ProposalCategory category,
        string memory ipfsMetadata	
    ) public returns (uint256) {
        require(
            reputationToken.balanceOf(msg.sender) >= minimumReputation,
            "Insufficient reputation"
        );
        
        // Dépôt de garantie
        IERC20 governanceToken = IERC20(address(token()));
        require(
            governanceToken.transferFrom(msg.sender, address(this), proposalDeposit),
            "Deposit failed"
        );
        
        // Création de la proposition
        uint256 proposalId = propose(targets, values, calldatas, description);
        
        // Enregistrement des métadonnées enrichies
        enhancedProposals[proposalId] = EnhancedProposal({
            proposalId: proposalId,
            proposer: msg.sender,
            title: title,
            description: description,
            category: category,
            createdTime: block.timestamp,
            votingEndTime: block.timestamp + votingPeriod(),
            status: ProposalStatus.ACTIVE,
            calldatas: calldatas,
            targets: targets,
            forVotes: 0,
            againstVotes: 0,
            abstainVotes: 0,
            executionTime: 0,
            ipfsMetadata: ipfsMetadata
        });
        
        proposalCount++;
        
        // Attribution de réputation pour la création de proposition
        reputationToken.mint(msg.sender, 10); // 10 points de réputation
        
        emit ProposalCreated(proposalId, msg.sender, title, category, block.timestamp);
        emit ReputationAwarded(msg.sender, 10, "Proposal creation", block.timestamp);
        
        return proposalId;
    }
    
    // Vote avec poids de réputation
    function castVoteWithReasonAndReputation(
        uint256 proposalId,
        uint8 support,
        string memory reason
    ) public returns (uint256) {
        // Vérifier que la proposition est active
        require(state(proposalId) == ProposalState.Active, "Voting not active");
        
        // Calcul du poids du vote (tokens + réputation)
        uint256 tokenWeight = getVotes(msg.sender, proposalId);
        uint256 reputationWeight = reputationToken.balanceOf(msg.sender);
        uint256 totalWeight = tokenWeight + (reputationWeight / 10); // Réputation compte pour 1/10
        
        // Enregistrement du vote
        _castVote(proposalId, msg.sender, support, reason);
        
        // Mise à jour des compteurs dans enhancedProposals
        EnhancedProposal storage proposal = enhancedProposals[proposalId];
        if (support == 0) {
            proposal.againstVotes += totalWeight;
        } else if (support == 1) {
            proposal.forVotes += totalWeight;
        } else if (support == 2) {
            proposal.abstainVotes += totalWeight;
        }
        
        // Attribution de réputation pour la participation
        reputationToken.mint(msg.sender, 1);
        
        emit VoteCast(
            proposalId,
            msg.sender,
            totalWeight,
            reputationWeight,
            support == 1 ? "FOR" : support == 0 ? "AGAINST" : "ABSTAIN",
            block.timestamp
        );
        
        emit ReputationAwarded(msg.sender, 1, "Voting participation", block.timestamp);
        
        return totalWeight;
    }
    
    // Exécution de proposition
    function executeEnhanced(
        address[] memory targets,
        uint256[] memory values,
        bytes[] memory calldatas,
        bytes32 descriptionHash
    ) public payable returns (uint256) {
        uint256 proposalId = hashProposal(targets, values, calldatas, descriptionHash);
        
        // Vérifier que la proposition a réussie
        require(state(proposalId) == ProposalState.Succeeded, "Proposal not succeeded");
        
        // Exécution
        _execute(proposalId, targets, values, calldatas, descriptionHash);
        
        // Mise à jour du statut
        EnhancedProposal storage proposal = enhancedProposals[proposalId];
        proposal.status = ProposalStatus.EXECUTED;
        proposal.executionTime = block.timestamp;
        
        // Remboursement du dépôt au proposant
        IERC20 governanceToken = IERC20(address(token()));
        governanceToken.transfer(proposal.proposer, proposalDeposit);
        
        // Attribution de réputation supplémentaire pour l'exécution réussie
        reputationToken.mint(proposal.proposer, 50);
        
        emit ProposalExecuted(proposalId, msg.sender, block.timestamp);
        emit ReputationAwarded(proposal.proposer, 50, "Successful proposal execution", block.timestamp);
        
        return proposalId;
    }
    
    // Délégation de votes avec historique
    function delegateWithRecord(address delegatee) public {
        uint256 currentVotes = getVotes(msg.sender, block.number);
        
        // Délégation standard
        reputationToken.delegate(delegatee);
        
        // Enregistrement historique
        delegationHistory[msg.sender].push(Delegation({
            delegatee: delegatee,
            amount: currentVotes,
            timestamp: block.timestamp
        }));
        
        // Attribution de réputation pour la délégation
        reputationToken.mint(msg.sender, 2);
        emit ReputationAwarded(msg.sender, 2, "Vote delegation", block.timestamp);
    }
    
    // Création de proposition rapide pour les paramètres
    function proposeParameterChange(
        address targetContract,
        string memory functionSignature,
        bytes memory newValue,
        string memory title,
        string memory description
    ) external returns (uint256) {
        bytes[] memory calldatas = new bytes[](1);
        calldatas[0] = abi.encodePacked(
            bytes4(keccak256(bytes(functionSignature))),
            newValue
        );
        
        address[] memory targets = new address[](1);
        targets[0] = targetContract;
        
        uint256[] memory values = new uint256[](1);
        values[0] = 0;
        
        return proposeEnhanced(
            targets,
            values,
            calldatas,
            description,
            title,
            ProposalCategory.PARAMETER_CHANGE,
            ""
        );
    }
    
    // Proposition de subvention communautaire
    function proposeCommunityGrant(
        address recipient,
        uint256 amount,
        string memory title,
        string memory description,
        string memory justification
    ) external returns (uint256) {
        bytes[] memory calldatas = new bytes[](1);
        calldatas[0] = abi.encodeWithSignature(
            "transfer(address,uint256)",
            recipient,
            amount
        );
        
        address[] memory targets = new address[](1);
        targets[0] = address(token()); // Trésorerie en tokens de gouvernance
        
        uint256[] memory values = new uint256[](1);
        values[0] = 0;
        
        string memory ipfsMetadata = string(abi.encodePacked(
            "{\"recipient\":\"",
            _addressToString(recipient),
            "\",\"amount\":",
            _toString(amount),
            ",\"justification\":\"",
            justification,
            "\"}"
        ));
        
        return proposeEnhanced(
            targets,
            values,
            calldatas,
            description,
            title,
            ProposalCategory.COMMUNITY_GRANT,
            ipfsMetadata
        );
    }
    
    // Proposition d'action d'urgence
    function proposeEmergencyAction(
        address targetContract,
        bytes memory emergencyCalldata,
        string memory title,
        string memory emergencyDescription
    ) external onlyRole(DEFAULT_ADMIN_ROLE) returns (uint256) {
        bytes[] memory calldatas = new bytes[](1);
        calldatas[0] = emergencyCalldata;
        
        address[] memory targets = new address[](1);
        targets[0] = targetContract;
        
        uint256[] memory values = new uint256[](1);
        values[0] = 0;
        
        return proposeEnhanced(
            targets,
            values,
            emergencyDescription,
            title,
            ProposalCategory.EMERGENCY_ACTION,
            "{\"emergency\":true}"
        );
    }
    
    // Getters pour les propositions enrichies
    function getEnhancedProposal(uint256 proposalId) external view returns (
        address proposer,
        string memory title,
        ProposalCategory category,
        ProposalStatus status,
        uint256 forVotes,
        uint256 againstVotes,
        uint256 abstainVotes,
        uint256 createdTime,
        uint256 votingEndTime
    ) {
        EnhancedProposal memory proposal = enhancedProposals[proposalId];
        return (
            proposal.proposer,
            proposal.title,
            proposal.category,
            proposal.status,
            proposal.forVotes,
            proposal.againstVotes,
            proposal.abstainVotes,
            proposal.createdTime,
            proposal.votingEndTime
        );
    }
    
    function getProposalsByCategory(ProposalCategory category) external view returns (uint256[] memory) {
        uint256[] memory result = new uint256[](proposalCount);
        uint256 count = 0;
        
        for (uint256 i = 0; i < proposalCount; i++) {
            if (enhancedProposals[i].category == category) {
                result[count] = i;
                count++;
            }
        }
        
        // Redimensionner le tableau
        uint256[] memory finalResult = new uint256[](count);
        for (uint256 j = 0; j < count; j++) {
            finalResult[j] = result[j];
        }
        
        return finalResult;
    }
    
    function getVotingPowerWithReputation(address account) external view returns (uint256) {
        uint256 tokenPower = getVotes(account, block.number);
        uint256 reputationPower = reputationToken.balanceOf(account) / 10;
        return tokenPower + reputationPower;
    }
    
    // Configuration des paramètres
    function setMinimumReputation(uint256 newMinimum) external onlyRole(DEFAULT_ADMIN_ROLE) {
        minimumReputation = newMinimum;
    }
    
    function setProposalDeposit(uint256 newDeposit) external onlyRole(DEFAULT_ADMIN_ROLE) {
        proposalDeposit = newDeposit;
    }
    
    // Fonctions utilitaires
    function _toString(uint256 value) internal pure returns (string memory) {
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
    
    function _addressToString(address addr) internal pure returns (string memory) {
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
    
    // Overrides nécessaires
    function votingDelay() public view override(GovernorSettings) returns (uint256) {
        return super.votingDelay();
    }
    
    function votingPeriod() public view override(GovernorSettings) returns (uint256) {
        return super.votingPeriod();
    }
    
    function quorum(uint256 blockNumber) 
        public 
        view 
        override(GovernorVotesQuorumFraction) 
        returns (uint256) 
    {
        return super.quorum(blockNumber);
    }
    
    function state(uint256 proposalId) 
        public 
        view 
        override(GovernorTimelockControl) 
        returns (ProposalState) 
    {
        return super.state(proposalId);
    }
    
    function proposalThreshold() 
        public 
        view 
        override(GovernorSettings) 
        returns (uint256) 
    {
        return super.proposalThreshold();
    }
    
    function _execute(
        uint256 proposalId,
        address[] memory targets,
        uint256[] memory values,
        bytes[] memory calldatas,
        bytes32 descriptionHash
    ) internal override(GovernorTimelockControl) {
        super._executeOperations(proposalId, targets, values, calldatas, descriptionHash);
    }
    
    function _cancel(
        address[] memory targets,
        uint256[] memory values,
        bytes[] memory calldatas,
        bytes32 descriptionHash
    ) internal override(GovernorTimelockControl) returns (uint256) {
        return super._cancel(targets, values, calldatas, descriptionHash);
    }
    
    function _executor() internal view override(GovernorTimelockControl) returns (address) {
        return super._executor();
    }
    
    function supportsInterface(bytes4 interfaceId)
        public
        view
        override(AccessControl)
        returns (bool)
    {
        return super.supportsInterface(interfaceId);
    }
	function _executeOperations(uint256 proposalId, address[] memory targets, uint256[] memory values, bytes[] memory calldatas, bytes32 descriptionHash) 
		internal override(GovernorTimelockControl) {
		super._executeOperations(proposalId, targets, values, calldatas, descriptionHash);
	}

	function _queueOperations(uint256 proposalId, address[] memory targets, uint256[] memory values, bytes[] memory calldatas, bytes32 descriptionHash) 
		internal override(GovernorTimelockControl) returns (uint48) {
		return super._queueOperations(proposalId, targets, values, calldatas, descriptionHash);
	}

	function proposalNeedsQueuing(uint256 proposalId) public view override returns (bool) {
		return super.proposalNeedsQueuing(proposalId);
	}
}