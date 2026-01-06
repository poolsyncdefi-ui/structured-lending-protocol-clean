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
    
    // CatÃ©gories de propositions
    enum ProposalCategory {
        PARAMETER_CHANGE,     // Changement de paramÃ¨tres
        TREASURY_MANAGEMENT,  // Gestion de trÃ©sorerie
        CONTRACT_UPGRADE,     // Mise Ã  jour de contrat
        EMERGENCY_ACTION,     // Action d'urgence
        COMMUNITY_GRANT,      // Subvention communautaire
        RISK_MANAGEMENT,      // Gestion des risques
        INSURANCE_POLICY,     // Politique d'assurance
        FEE_STRUCTURE         // Structure de frais
    }
    
    // Statuts Ã©tendus
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
    
    // Structures de dÃ©lÃ©gation
    struct Delegation {
        address delegatee;
        uint256 amount;
        uint256 timestamp;
    }
    
    // Variables d'Ã©tat
    mapping(uint256 => EnhancedProposal) public enhancedProposals;
    mapping(address => Delegation[]) public delegationHistory;
    mapping(address => uint256) public reputationScores;
    
    uint256 public proposalCount;
    uint256 public minimumReputation = 100;
    uint256 public proposalDeposit = 100 * 1e18; // 100 tokens
    
    // Token de rÃ©putation
    ReputationToken public reputationToken;
    
    // Ã‰vÃ©nements
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
    
    // CrÃ©ation de proposition amÃ©liorÃ©e
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
        
        // DÃ©pÃ´t de garantie
        IERC20 governanceToken = IERC20(address(token()));
        require(
            governanceToken.transferFrom(msg.sender, address(this), proposalDeposit),
            "Deposit failed"
        );
        
        // CrÃ©ation de la proposition
        uint256 proposalId = propose(targets, values, calldatas, description);
        
        // Enregistrement des mÃ©tadonnÃ©es enrichies
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
        
        // Attribution de rÃ©putation pour la crÃ©ation de proposition
        reputationToken.mint(msg.sender, 10); // 10 points de rÃ©putation
        
        emit ProposalCreated(proposalId, msg.sender, title, category, block.timestamp);
        emit ReputationAwarded(msg.sender, 10, "Proposal creation", block.timestamp);
        
        return proposalId;
    }
    
    // Vote avec poids de rÃ©putation
    function castVoteWithReasonAndReputation(
        uint256 proposalId,
        uint8 support,
        string memory reason
    ) public returns (uint256) {
        // VÃ©rifier que la proposition est active
        require(state(proposalId) == ProposalState.Active, "Voting not active");
        
        // Calcul du poids du vote (tokens + rÃ©putation)
        uint256 tokenWeight = getVotes(msg.sender, proposalId);
        uint256 reputationWeight = reputationToken.balanceOf(msg.sender);
        uint256 totalWeight = tokenWeight + (reputationWeight / 10); // RÃ©putation compte pour 1/10
        
        // Enregistrement du vote
        _castVote(proposalId, msg.sender, support, reason);
        
        // Mise Ã  jour des compteurs dans enhancedProposals
        EnhancedProposal storage proposal = enhancedProposals[proposalId];
        if (support == 0) {
            proposal.againstVotes += totalWeight;
        } else if (support == 1) {
            proposal.forVotes += totalWeight;
        } else if (support == 2) {
            proposal.abstainVotes += totalWeight;
        }
        
        // Attribution de rÃ©putation pour la participation
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
    
    // ExÃ©cution de proposition
    function executeEnhanced(
        address[] memory targets,
        uint256[] memory values,
        bytes[] memory calldatas,
        bytes32 descriptionHash
    ) public payable returns (uint256) {
        uint256 proposalId = hashProposal(targets, values, calldatas, descriptionHash);
        
        // VÃ©rifier que la proposition a rÃ©ussie
        require(state(proposalId) == ProposalState.Succeeded, "Proposal not succeeded");
        
        // ExÃ©cution
        _execute(proposalId, targets, values, calldatas, descriptionHash);
        
        // Mise Ã  jour du statut
        EnhancedProposal storage proposal = enhancedProposals[proposalId];
        proposal.status = ProposalStatus.EXECUTED;
        proposal.executionTime = block.timestamp;
        
        // Remboursement du dÃ©pÃ´t au proposant
        IERC20 governanceToken = IERC20(address(token()));
        governanceToken.transfer(proposal.proposer, proposalDeposit);
        
        // Attribution de rÃ©putation supplÃ©mentaire pour l'exÃ©cution rÃ©ussie
        reputationToken.mint(proposal.proposer, 50);
        
        emit ProposalExecuted(proposalId, msg.sender, block.timestamp);
        emit ReputationAwarded(proposal.proposer, 50, "Successful proposal execution", block.timestamp);
        
        return proposalId;
    }
    
    // DÃ©lÃ©gation de votes avec historique
    function delegateWithRecord(address delegatee) public {
        uint256 currentVotes = getVotes(msg.sender, block.number);
        
        // DÃ©lÃ©gation standard
        reputationToken.delegate(delegatee);
        
        // Enregistrement historique
        delegationHistory[msg.sender].push(Delegation({
            delegatee: delegatee,
            amount: currentVotes,
            timestamp: block.timestamp
        }));
        
        // Attribution de rÃ©putation pour la dÃ©lÃ©gation
        reputationToken.mint(msg.sender, 2);
        emit ReputationAwarded(msg.sender, 2, "Vote delegation", block.timestamp);
    }
    
    // CrÃ©ation de proposition rapide pour les paramÃ¨tres
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
        targets[0] = address(token()); // TrÃ©sorerie en tokens de gouvernance
        
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
    
    // Configuration des paramÃ¨tres
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
    
    // Overrides nÃ©cessaires
    function votingDelay() public view override(Governor, GovernorSettings) returns (uint256) {
        return super.votingDelay();
    }
    
    function votingPeriod() public view override(Governor, GovernorSettings) returns (uint256) {
        return super.votingPeriod();
    }
    
    function quorum(uint256 blockNumber) 
        public 
        view 
        override(Governor, GovernorVotesQuorumFraction) 
        returns (uint256) 
    {
        return super.quorum(blockNumber);
    }
    
    function state(uint256 proposalId) 
        public 
        view 
        override(Governor, GovernorTimelockControl) 
        returns (ProposalState) 
    {
        return super.state(proposalId);
    }
    
    function proposalThreshold() 
        public 
        view 
        override(Governor, GovernorSettings) 
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
    ) internal override(Governor, GovernorTimelockControl) {
        super._executeOperations(proposalId, targets, values, calldatas, descriptionHash);
    }
    
    function _cancel(
        address[] memory targets,
        uint256[] memory values,
        bytes[] memory calldatas,
        bytes32 descriptionHash
    ) internal override(Governor, GovernorTimelockControl) returns (uint256) {
        return super._cancel(targets, values, calldatas, descriptionHash);
    }
    
    function _executor() internal view override(Governor, GovernorTimelockControl) returns (address) {
        return super._executor();
    }
    
    function supportsInterface(bytes4 interfaceId)
        public
        view
        override(Governor, AccessControl)
        returns (bool)
    {
        return super.supportsInterface(interfaceId);
    }
	function _executeOperations(uint256 proposalId, address[] memory targets, uint256[] memory values, bytes[] memory calldatas, bytes32 descriptionHash) 
		internal override(Governor, GovernorTimelockControl) {
		super._executeOperations(proposalId, targets, values, calldatas, descriptionHash);
	}

	function _queueOperations(uint256 proposalId, address[] memory targets, uint256[] memory values, bytes[] memory calldatas, bytes32 descriptionHash) 
		internal override(Governor, GovernorTimelockControl) returns (uint48) {
		return super._queueOperations(proposalId, targets, values, calldatas, descriptionHash);
	}

	function proposalNeedsQueuing(uint256 proposalId) public view override returns (bool) {
		return super.proposalNeedsQueuing(proposalId);
	}
}
