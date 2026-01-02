// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import "@openzeppelin/contracts/token/ERC721/extensions/ERC721Enumerable.sol";
import "@openzeppelin/contracts/token/ERC721/extensions/ERC721URIStorage.sol";
import "@openzeppelin/contracts/access/AccessControl.sol";

// Début de l'implémentation manuelle de Counters
library Counters {
    struct Counter {
        uint256 _value;
    }
    
    function current(Counter storage counter) internal view returns (uint256) {
        return counter._value;
    }
    
    function increment(Counter storage counter) internal {
        unchecked { counter._value += 1; }
    }
    
    function decrement(Counter storage counter) internal {
        uint256 value = counter._value;
        require(value > 0, "Counter: decrement overflow");
        unchecked { counter._value = value - 1; }
    }
    
    function reset(Counter storage counter) internal {
        counter._value = 0;
    }
}
// --- Fin de l'implémentation manuelle ---


contract LoanNFT is ERC721, ERC721Enumerable, ERC721URIStorage, AccessControl {
    using Counters for Counters.Counter;
    Counters.Counter private _tokenIds;
    
    // Rôles
    bytes32 public constant LOAN_MANAGER = keccak256("LOAN_MANAGER");
    bytes32 public constant MARKET_MANAGER = keccak256("MARKET_MANAGER");
    
    // Structure de métadonnées enrichies
    struct LoanMetadata {
        uint256 loanId;
        uint256 principalAmount;
        uint256 interestRate; // en base 10000 (1% = 100)
        uint256 duration;
        uint256 startTime;
        uint256 riskScore;
        uint256 trancheId;
        address borrower;
        address currency;
        LoanStatus status;
        uint256 remainingBalance;
        uint256 lastPaymentTime;
        uint256 totalRepaid;
        bool isSecuritized;
        string ipfsMetadata;
    }
    
    // Types de prêts
    enum LoanStatus {
        ACTIVE,
        REPAID,
        DEFAULTED,
        INSURED_PAIDOUT,
        SECURITIZED,
        CANCELLED
    }
    
    // Mapping des métadonnées
    mapping(uint256 => LoanMetadata) public loanMetadata;
    mapping(uint256 => uint256) public loanIdToTokenId;
    mapping(uint256 => uint256) public tokenIdToLoanId;
    
    // Événements
    event LoanNFTMinted(
        uint256 indexed tokenId,
        uint256 indexed loanId,
        address indexed borrower,
        uint256 amount,
        uint256 interestRate,
        uint256 duration
    );
    
    event LoanNFTUpdated(
        uint256 indexed tokenId,
        LoanStatus newStatus,
        uint256 remainingBalance,
        uint256 timestamp
    );
    
    event LoanNFTTransferred(
        uint256 indexed tokenId,
        address from,
        address to,
        uint256 salePrice,
        uint256 timestamp
    );
    
    constructor() ERC721("StructuredLoanNFT", "SLNFT") {
        _grantRole(DEFAULT_ADMIN_ROLE, msg.sender);
        _grantRole(LOAN_MANAGER, msg.sender);
        _grantRole(MARKET_MANAGER, msg.sender);
    }
    
	function _update(address to, uint256 tokenId, address auth)
    internal
    override(ERC721Enumerable)
    returns (address)
	{
		return super._update(to, tokenId, auth);
	}

	function _increaseBalance(address account, uint256 value)
		internal
		override(ERC721Enumerable)
	{
		super._increaseBalance(account, value);
	}

	function tokenURI(uint256 tokenId)
    public
		view
		override(ERC721URIStorage)
		returns (string memory)
	{
		return super.tokenURI(tokenId);
	}

	function supportsInterface(bytes4 interfaceId) 
		public 
		view 
		override(ERC721Enumerable, ERC721URIStorage, AccessControl) 
		returns (bool) 
	{
		return super.supportsInterface(interfaceId);
	}
	
    // Mint d'un nouveau NFT pour un prêt
    function mint(
        address borrower,
        uint256 loanId,
        uint256 principalAmount,
        uint256 interestRate,
        uint256 duration,
        uint256 riskScore,
        uint256 trancheId,
        address currency,
        string memory ipfsMetadata
    ) external onlyRole(LOAN_MANAGER) returns (uint256) {
        _tokenIds.increment();
        uint256 newTokenId = _tokenIds.current();
        
        // Mint du NFT
        _safeMint(borrower, newTokenId);
        
        // Enregistrement des métadonnées
        loanMetadata[newTokenId] = LoanMetadata({
            loanId: loanId,
            principalAmount: principalAmount,
            interestRate: interestRate,
            duration: duration,
            startTime: block.timestamp,
            riskScore: riskScore,
            trancheId: trancheId,
            borrower: borrower,
            currency: currency,
            status: LoanStatus.ACTIVE,
            remainingBalance: principalAmount,
            lastPaymentTime: block.timestamp,
            totalRepaid: 0,
            isSecuritized: false,
            ipfsMetadata: ipfsMetadata
        });
        
        // Mapping des IDs
        loanIdToTokenId[loanId] = newTokenId;
        tokenIdToLoanId[newTokenId] = loanId;
        
        // Définition de l'URI
        string memory uriString = string(abi.encodePacked(
            "https://api.loanplatform.com/nft/",
            _toString(newTokenId)
        ));
        _setTokenURI(newTokenId, uriString);
        
        emit LoanNFTMinted(
            newTokenId,
            loanId,
            borrower,
            principalAmount,
            interestRate,
            duration
        );
        
        return newTokenId;
    }
    
    // Mise à jour du statut du prêt
    function updateStatus(
        uint256 loanId,
        LoanStatus newStatus,
        uint256 remainingBalance,
        uint256 totalRepaid
    ) external onlyRole(LOAN_MANAGER) {
        uint256 tokenId = loanIdToTokenId[loanId];
        require(tokenId != 0, "NFT not found");
        
        LoanMetadata storage metadata = loanMetadata[tokenId];
        metadata.status = newStatus;
        metadata.remainingBalance = remainingBalance;
        metadata.totalRepaid = totalRepaid;
        metadata.lastPaymentTime = block.timestamp;
        
        emit LoanNFTUpdated(tokenId, newStatus, remainingBalance, block.timestamp);
    }
    
    // Marquage comme remboursé
    function markAsRepaid(uint256 loanId) external onlyRole(LOAN_MANAGER) {
        uint256 tokenId = loanIdToTokenId[loanId];
        require(tokenId != 0, "NFT not found");
        
        loanMetadata[tokenId].status = LoanStatus.REPAID;
        loanMetadata[tokenId].remainingBalance = 0;
        
        // Mise à jour de l'uriString pour refléter le statut
        _setTokenURI(tokenId, string(abi.encodePacked(
            tokenURI(tokenId),
            "?status=repaid"
        )));
    }
    
    // Marquage comme titrisé
    function markAsSecuritized(uint256 loanId) external onlyRole(MARKET_MANAGER) {
        uint256 tokenId = loanIdToTokenId[loanId];
        require(tokenId != 0, "NFT not found");
        
        loanMetadata[tokenId].isSecuritized = true;
        loanMetadata[tokenId].status = LoanStatus.SECURITIZED;
    }
    
    // Enregistrement d'un paiement
    function recordPayment(
        uint256 loanId,
        uint256 paymentAmount,
        uint256 newBalance
    ) external onlyRole(LOAN_MANAGER) {
        uint256 tokenId = loanIdToTokenId[loanId];
        require(tokenId != 0, "NFT not found");
        
        LoanMetadata storage metadata = loanMetadata[tokenId];
        metadata.totalRepaid += paymentAmount;
        metadata.remainingBalance = newBalance;
        metadata.lastPaymentTime = block.timestamp;
    }
    
    // Calcul de la valeur actuelle du prêt
    function calculateCurrentValue(uint256 tokenId) public view returns (uint256) {
        LoanMetadata memory metadata = loanMetadata[tokenId];
        
        if (metadata.status != LoanStatus.ACTIVE) {
            return metadata.remainingBalance;
        }
        
        uint256 elapsedTime = block.timestamp - metadata.startTime;
        uint256 totalTime = metadata.duration;
        
        // Calcul des intérêts accumulés (intérêts simples)
        uint256 interestAccrued = (metadata.principalAmount * metadata.interestRate * elapsedTime) /
            (365 days * 10000);
        
        return metadata.remainingBalance + interestAccrued;
    }
    
    // Vérification de l'éligibilité au marché secondaire
    function isEligibleForSecondaryMarket(uint256 tokenId) public view returns (bool) {
        LoanMetadata memory metadata = loanMetadata[tokenId];
        
        return metadata.status == LoanStatus.ACTIVE &&
            !metadata.isSecuritized &&
            block.timestamp < metadata.startTime + metadata.duration;
    }
    
    // Récupération des détails du prêt
    function getLoanDetails(uint256 tokenId) public view returns (
        uint256 loanId,
        uint256 principalAmount,
        uint256 interestRate,
        uint256 duration,
        uint256 riskScore,
        uint256 trancheId,
        address borrower,
        LoanStatus status,
        uint256 remainingBalance,
        bool isSecuritized
    ) {
        LoanMetadata memory metadata = loanMetadata[tokenId];
        return (
            metadata.loanId,
            metadata.principalAmount,
            metadata.interestRate,
            metadata.duration,
            metadata.riskScore,
            metadata.trancheId,
            metadata.borrower,
            metadata.status,
            metadata.remainingBalance,
            metadata.isSecuritized
        );
    }
    
    // Récupération des métadonnées complètes
    function getFullMetadata(uint256 tokenId) public view returns (
        LoanMetadata memory metadata,
        uint256 currentValue,
        bool eligibleForMarket
    ) {
        metadata = loanMetadata[tokenId];
        currentValue = calculateCurrentValue(tokenId);
        eligibleForMarket = isEligibleForSecondaryMarket(tokenId);
        
        return (metadata, currentValue, eligibleForMarket);
    }
    
    // Transfert avec enregistrement du prix de vente
    function transferWithRecord(
        address from,
        address to,
        uint256 tokenId,
        uint256 salePrice
    ) external onlyRole(MARKET_MANAGER) {
        address owner = ownerOf(tokenId);
		require(
			from == owner || 
			isApprovedForAll(owner, from) || 
			getApproved(tokenId) == from,
			"Not approved"
		);
        
        _transfer(from, to, tokenId);
        
        emit LoanNFTTransferred(tokenId, from, to, salePrice, block.timestamp);
    }
    
    // Batch mint pour plusieurs prêts
    function batchMint(
        address[] memory borrowers,
        uint256[] memory loanIds,
        uint256[] memory amounts,
        uint256[] memory interestRates,
        uint256[] memory durations
    ) external onlyRole(LOAN_MANAGER) returns (uint256[] memory) {
        require(
            borrowers.length == loanIds.length &&
            loanIds.length == amounts.length &&
            amounts.length == interestRates.length &&
            interestRates.length == durations.length,
            "Array length mismatch"
        );
        
        uint256[] memory tokenIds = new uint256[](borrowers.length);
        
        for (uint256 i = 0; i < borrowers.length; i++) {
            _tokenIds.increment();
            uint256 newTokenId = _tokenIds.current();
            
            _safeMint(borrowers[i], newTokenId);
            
            loanMetadata[newTokenId] = LoanMetadata({
                loanId: loanIds[i],
                principalAmount: amounts[i],
                interestRate: interestRates[i],
                duration: durations[i],
                startTime: block.timestamp,
                riskScore: 500, // Score par défaut
                trancheId: 1, // Tranche par défaut
                borrower: borrowers[i],
                currency: address(0), // ETH par défaut
                status: LoanStatus.ACTIVE,
                remainingBalance: amounts[i],
                lastPaymentTime: block.timestamp,
                totalRepaid: 0,
                isSecuritized: false,
                ipfsMetadata: ""
            });
            
            loanIdToTokenId[loanIds[i]] = newTokenId;
            tokenIdToLoanId[newTokenId] = loanIds[i];
            
            tokenIds[i] = newTokenId;
            
            emit LoanNFTMinted(
                newTokenId,
                loanIds[i],
                borrowers[i],
                amounts[i],
                interestRates[i],
                durations[i]
            );
        }
        
        return tokenIds;
    }
    
    // Override des fonctions nécessaires
    function _beforeTokenTransfer(
        address from,
        address to,
        uint256 tokenId
    ) internal override(ERC721Enumerable) {
        super._beforeTokenTransfer(from, to, tokenId);
    }
    
    function _burn(uint256 tokenId) internal override(ERC721URIStorage) {
        super._burn(tokenId);
    }
    
    function uri(uint256 tokenId)
        public
        view
        override(ERC721URIStorage)
        returns (string memory)
    {
        return super.uri(tokenId);
    }
    
    function supportsInterface(bytes4 interfaceId)
        public
        view
        override(ERC721Enumerable, ERC721URIStorage, AccessControl)
        returns (bool)
    {
        return super.supportsInterface(interfaceId);
    }
    
    // Fonction utilitaire pour convertir uint en string
    function _toString(uint256 value) internal pure returns (string memory) {
        if (value == 0) {
            return "0";
        }
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
    
    // Getters
    function getTokenId(uint256 loanId) external view returns (uint256) {
        return loanIdToTokenId[loanId];
    }
    
    function getLoanId(uint256 tokenId) external view returns (uint256) {
        return tokenIdToLoanId[tokenId];
    }
    
    function getBorrowerTokens(address borrower) external view returns (uint256[] memory) {
        uint256 balance = balanceOf(borrower);
        uint256[] memory tokens = new uint256[](balance);
        
        for (uint256 i = 0; i < balance; i++) {
            tokens[i] = tokenOfOwnerByIndex(borrower, i);
        }
        
        return tokens;
    }
    
    function getTokenIdsByStatus(LoanStatus status) external view returns (uint256[] memory) {
        uint256 total = _tokenIds.current();
        uint256 count = 0;
        
        // Compter les tokens avec le statut donné
        for (uint256 i = 1; i <= total; i++) {
            if (loanMetadata[i].status == status) {
                count++;
            }
        }
        
        // Collecter les tokenIds
        uint256[] memory result = new uint256[](count);
        uint256 index = 0;
        
        for (uint256 i = 1; i <= total; i++) {
            if (loanMetadata[i].status == status) {
                result[index] = i;
                index++;
            }
        }
        
        return result;
    }
	
	function _increaseBalance(address account, uint128 value) 
		internal 
		override(ERC721, ERC721Enumerable) 
	{
		super._increaseBalance(account, value);
	}
}