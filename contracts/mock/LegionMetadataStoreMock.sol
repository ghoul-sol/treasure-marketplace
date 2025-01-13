// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import {ILegionMetadataStore, LegionGeneration, LegionRarity} from "../interfaces/ILegionMetadataStore.sol";

contract LegionMetadataStoreMock is ILegionMetadataStore {

    LegionGeneration internal gen;
    LegionRarity internal rarity;

    constructor(LegionGeneration _gen, LegionRarity _rarity) {
        gen = _gen;
        rarity = _rarity;
    }

    function genAndRarityForLegion(uint256) external view returns(LegionGeneration gen_, LegionRarity rarity_) {
        gen_ = gen;
        rarity_ = rarity;
    }
}
