// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

interface ISpecialOfferManager {
    function getActiveOfferForPool(uint256 poolId) external view returns (
        bool hasOffer,
        uint256 offerId,
        uint256 bonus,
        uint256 endTime
    );
    
    function getOfferDetails(uint256 offerId) external view returns (
        uint256 bonusRate,
        uint256 endTime
    );
}