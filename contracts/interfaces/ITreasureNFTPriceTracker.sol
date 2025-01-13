// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

interface ITreasureNFTPriceTracker {
    event AveragePriceUpdated(
        address indexed _collection,
        FloorType indexed _floorType,
        uint256 _oldAverage,
        uint256 _salePrice,
        uint256 _newAverage
    );

    // Saves the given sale of a token in a collection if it meets the saving criteria.
    function recordSale(address _collection, uint256 _tokenId, uint256 _salePrice) external;
    // Returns the average price for the given collection in the floor type category.
    // Can return 0 if asking for a FloorType that isn't being tracked for that given collection
    function getAveragePriceForCollection(address _collection, FloorType _floorType) external view returns (uint256);
}

// Allows for customization within tracking floor prices
// Ex: Tracking legion genesis commons could be subfloor1, genesis uncommons subfloor2, etc
enum FloorType {
    FLOOR,
    SUBFLOOR1,
    SUBFLOOR2,
    SUBFLOOR3
}
