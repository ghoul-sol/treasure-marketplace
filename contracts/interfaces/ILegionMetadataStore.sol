// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

interface ILegionMetadataStore {
    // Returns the generation and rarity for the given legion.
    function genAndRarityForLegion(uint256 _tokenId) external view returns(LegionGeneration, LegionRarity);
}

enum LegionRarity {
    LEGENDARY,
    RARE,
    SPECIAL,
    UNCOMMON,
    COMMON,
    RECRUIT
}

enum LegionGeneration {
    GENESIS,
    AUXILIARY,
    RECRUIT
}