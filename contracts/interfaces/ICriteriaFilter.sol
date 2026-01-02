// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

interface ICriteriaFilter {
    function filterPools(
        string[] memory regions,
        bool ecologicalOnly,
        string[] memory domains,
        uint256 minRate,
        uint256 maxRisk
    ) external view returns (uint256[] memory);
}