// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import "@openzeppelin/contracts/token/ERC721/IERC721.sol";
import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/utils/ReentrancyGuard.sol";
import "./LoanNFT.sol";

contract SecondaryMarketV2 is ReentrancyGuard {
    // Structures
    struct Listing {
        uint256 tokenId;
        address seller;
        uint256 askingPrice;
        uint256 reservePrice;
        uint256 startTime;
        uint256 endTime;
        bool isAuction;
        bool isActive;
        address highestBidder;
        uint256 highestBid;
    }
    
    struct Bid {
        address bidder;
        uint256 amount;
        uint256 timestamp;
    }
    
    // Données du marché
    mapping(uint256 => Listing) public listings;
    mapping(uint256 => Bid[]) public listingBids;
    mapping(address => uint256[]) public userListings;
    
    // Paramètres
    uint256 public platformFee = 25; // 0.25%
    address public feeRecipient;
    IERC20 public paymentToken;
    LoanNFT public loanNFT;
    
    // Événements
    event Listed(
        uint256 indexed tokenId,
        address indexed seller,
        uint256 askingPrice,
        bool isAuction,
        uint256 timestamp
    );
    
    event Purchased(
        uint256 indexed tokenId,
        address indexed seller,
        address indexed buyer,
        uint256 price,
        uint256 fee,
        uint256 timestamp
    );
    
    event BidPlaced(
        uint256 indexed tokenId,
        address indexed bidder,
        uint256 amount,
        uint256 timestamp
    );
    
    event AuctionEnded(
        uint256 indexed tokenId,
        address indexed winner,
        uint256 winningBid,
        uint256 timestamp
    );
    
    constructor(
        address _loanNFT,
        address _paymentToken,
        address _feeRecipient
    ) {
        loanNFT = LoanNFT(_loanNFT);
        paymentToken = IERC20(_paymentToken);
        feeRecipient = _feeRecipient;
    }
    
    // Liste un NFT à prix fixe
    function listFixedPrice(
        uint256 tokenId,
        uint256 price,
        uint256 durationDays
    ) external nonReentrant {
        require(loanNFT.ownerOf(tokenId) == msg.sender, "Not owner");
        require(price > 0, "Price must be > 0");
        require(durationDays <= 90, "Duration too long");
        
        // Vérifier que le prêt est éligible
        require(_isLoanEligible(tokenId), "Loan not eligible");
        
        // Créer la liste
        listings[tokenId] = Listing({
            tokenId: tokenId,
            seller: msg.sender,
            askingPrice: price,
            reservePrice: price * 80 / 100, // 80% du prix
            startTime: block.timestamp,
            endTime: block.timestamp + (durationDays * 1 days),
            isAuction: false,
            isActive: true,
            highestBidder: address(0),
            highestBid: 0
        });
        
        userListings[msg.sender].push(tokenId);
        
        // Transfert du NFT au contrat
        loanNFT.transferFrom(msg.sender, address(this), tokenId);
        
        emit Listed(tokenId, msg.sender, price, false, block.timestamp);
    }
    
    // Liste en enchère
    function listAuction(
        uint256 tokenId,
        uint256 reservePrice,
        uint256 durationDays
    ) external nonReentrant {
        require(loanNFT.ownerOf(tokenId) == msg.sender, "Not owner");
        require(reservePrice > 0, "Reserve must be > 0");
        require(durationDays <= 30, "Auction too long");
        
        require(_isLoanEligible(tokenId), "Loan not eligible");
        
        listings[tokenId] = Listing({
            tokenId: tokenId,
            seller: msg.sender,
            askingPrice: 0,
            reservePrice: reservePrice,
            startTime: block.timestamp,
            endTime: block.timestamp + (durationDays * 1 days),
            isAuction: true,
            isActive: true,
            highestBidder: address(0),
            highestBid: 0
        });
        
        userListings[msg.sender].push(tokenId);
        
        loanNFT.transferFrom(msg.sender, address(this), tokenId);
        
        emit Listed(tokenId, msg.sender, reservePrice, true, block.timestamp);
    }
    
    // Acheter à prix fixe
    function purchase(uint256 tokenId) external nonReentrant {
        Listing storage listing = listings[tokenId];
        
        require(listing.isActive, "Not active");
        require(!listing.isAuction, "Is auction");
        require(block.timestamp <= listing.endTime, "Listing expired");
        
        uint256 price = listing.askingPrice;
        uint256 fee = (price * platformFee) / 10000;
        uint256 sellerProceeds = price - fee;
        
        // Transfert du paiement
        require(
            paymentToken.transferFrom(msg.sender, address(this), price),
            "Transfer failed"
        );
        
        // Distribution
        paymentToken.transfer(listing.seller, sellerProceeds);
        paymentToken.transfer(feeRecipient, fee);
        
        // Transfert du NFT
        loanNFT.transferFrom(address(this), msg.sender, tokenId);
        
        // Mise à jour
        listing.isActive = false;
        
        emit Purchased(
            tokenId,
            listing.seller,
            msg.sender,
            price,
            fee,
            block.timestamp
        );
    }
    
    // Placer une enchère
    function placeBid(uint256 tokenId, uint256 amount) external nonReentrant {
        Listing storage listing = listings[tokenId];
        
        require(listing.isActive, "Not active");
        require(listing.isAuction, "Not auction");
        require(block.timestamp <= listing.endTime, "Auction ended");
        require(amount > listing.highestBid, "Bid too low");
        require(amount >= listing.reservePrice, "Below reserve");
        
        // Rembourser l'ancien encherisseur
        if (listing.highestBidder != address(0)) {
            paymentToken.transfer(listing.highestBidder, listing.highestBid);
        }
        
        // Recevoir la nouvelle enchère
        require(
            paymentToken.transferFrom(msg.sender, address(this), amount),
            "Transfer failed"
        );
        
        // Mise à jour
        listing.highestBidder = msg.sender;
        listing.highestBid = amount;
        
        // Enregistrer l'enchère
        listingBids[tokenId].push(Bid({
            bidder: msg.sender,
            amount: amount,
            timestamp: block.timestamp
        }));
        
        emit BidPlaced(tokenId, msg.sender, amount, block.timestamp);
    }
    
    // Finaliser une enchère
    function finalizeAuction(uint256 tokenId) external nonReentrant {
        Listing storage listing = listings[tokenId];
        
        require(listing.isActive, "Not active");
        require(listing.isAuction, "Not auction");
        require(block.timestamp > listing.endTime, "Auction not ended");
        require(listing.highestBidder != address(0), "No bids");
        
        uint256 winningBid = listing.highestBid;
        uint256 fee = (winningBid * platformFee) / 10000;
        uint256 sellerProceeds = winningBid - fee;
        
        // Distribution
        paymentToken.transfer(listing.seller, sellerProceeds);
        paymentToken.transfer(feeRecipient, fee);
        
        // Transfert du NFT
        loanNFT.transferFrom(address(this), listing.highestBidder, tokenId);
        
        // Mise à jour
        listing.isActive = false;
        
        emit AuctionEnded(
            tokenId,
            listing.highestBidder,
            winningBid,
            block.timestamp
        );
    }
    
    // Retirer une liste
    function cancelListing(uint256 tokenId) external nonReentrant {
        Listing storage listing = listings[tokenId];
        
        require(listing.seller == msg.sender, "Not seller");
        require(listing.isActive, "Not active");
        
        // Pour les enchères, vérifier qu'il n'y a pas d'enchères
        if (listing.isAuction) {
            require(listing.highestBidder == address(0), "Bids exist");
        }
        
        // Rembourser le NFT
        loanNFT.transferFrom(address(this), msg.sender, tokenId);
        
        listing.isActive = false;
    }
    
    // Vérifier l'éligibilité d'un prêt
    function _isLoanEligible(uint256 tokenId) private view returns (bool) {
        // Récupérer les détails du prêt
        (,, uint256 loanAmount, uint256 interestRate, uint256 duration,,,) = 
            loanNFT.getLoanDetails(tokenId);
        
        // Vérifications de base
        if (loanAmount == 0) return false;
        if (duration < 30 days) return false;
        
        // Vérifier le statut (doit être actif)
        // À implémenter: intégration avec LoanPool
        
        return true;
    }
    
    // Getters
    function getListingBids(uint256 tokenId) external view returns (Bid[] memory) {
        return listingBids[tokenId];
    }
    
    function getUserListings(address user) external view returns (uint256[] memory) {
        return userListings[user];
    }
    
    function getMarketStats() external view returns (
        uint256 totalListings,
        uint256 activeListings,
        uint256 totalVolume,
        uint256 averagePrice
    ) {
        // À implémenter: statistiques du marché
        return (0, 0, 0, 0);
    }
}