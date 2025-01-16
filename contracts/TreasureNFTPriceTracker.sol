// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import {OwnableUpgradeable} from "@openzeppelin/contracts-upgradeable/access/OwnableUpgradeable.sol";
import {PRBMathUD60x18} from "@prb/math/contracts/PRBMathUD60x18.sol";
import {UUPSUpgradeable} from "@openzeppelin/contracts-upgradeable/proxy/utils/UUPSUpgradeable.sol";
import {Initializable} from "@openzeppelin/contracts-upgradeable/proxy/utils/Initializable.sol";
import {AccessControlEnumerableUpgradeable} from
    "@openzeppelin/contracts-upgradeable/access/extensions/AccessControlEnumerableUpgradeable.sol";

import {ITreasureNFTPriceTracker, FloorType} from "./interfaces/ITreasureNFTPriceTracker.sol";
import {ILegionMetadataStore, LegionGeneration, LegionRarity} from "./interfaces/ILegionMetadataStore.sol";

/// @title  Treasure NFT Price Tracker
/// @notice This contract tracks and calculates average floor prices for NFT collections.
///         This contract uses the UUPS upgrade pattern. Only accounts with PRICE_TRACKER_ADMIN_ROLE can upgrade
///         the implementation.
/// @dev    Implements UUPS upgradeability and role-based access control
contract TreasureNFTPriceTracker is
    Initializable,
    UUPSUpgradeable,
    AccessControlEnumerableUpgradeable,
    ITreasureNFTPriceTracker
{
    using PRBMathUD60x18 for uint256;

    /// @notice Role that can upgrade the implementation and manage the contract
    bytes32 public constant PRICE_TRACKER_ADMIN_ROLE = keccak256("PRICE_TRACKER_ADMIN_ROLE");

    address public treasureMarketplaceContract;
    address public legionContract;
    address public legionMetadata;

    mapping(address => mapping(FloorType => uint256)) internal collectionToFloorTypeToPriceAvg;

    /// @custom:oz-upgrades-unsafe-allow constructor
    constructor() {
        _disableInitializers();
    }

    /// @notice Perform initial contract setup
    /// @dev    The initializer modifier ensures this is only called once, the owner should confirm this was properly
    ///         performed before publishing this contract address.
    /// @param  _treasureMarketplaceContract address of treasure marketplace
    /// @param  _legionContract address of the legion collection
    function initialize(address _treasureMarketplaceContract, address _legionContract, address _legionMetadata)
        external
        initializer
    {
        require(address(_treasureMarketplaceContract) != address(0), "TreasureNFTPricing: cannot set address(0)");
        require(address(_legionContract) != address(0), "TreasureNFTPricing: cannot set address(0)");

        __UUPSUpgradeable_init();
        __AccessControl_init();

        _setRoleAdmin(PRICE_TRACKER_ADMIN_ROLE, PRICE_TRACKER_ADMIN_ROLE);
        _grantRole(PRICE_TRACKER_ADMIN_ROLE, msg.sender);

        treasureMarketplaceContract = _treasureMarketplaceContract;
        legionContract = _legionContract;
        legionMetadata = _legionMetadata;
    }

    /// @notice Record sale price and update floor pricing averages
    /// @dev    If an average does not yet exist, the new average will be _salePrice
    ///         avg will be stored as FloorType.FLOOR unless special sub-floor criteria is met
    /// @param _collection Address of the collection that had a token sale
    /// @param _tokenId The token sold
    /// @param _salePrice The amount the sale was for
    function recordSale(address _collection, uint256 _tokenId, uint256 _salePrice) external {
        require(msg.sender == treasureMarketplaceContract, "Invalid caller");
        if (_collection != legionContract) {
            return;
        }
        (LegionGeneration gen, LegionRarity rarity) =
            ILegionMetadataStore(legionMetadata).genAndRarityForLegion(_tokenId);
        if (gen != LegionGeneration.GENESIS) {
            return;
        }
        FloorType floorType;
        if (rarity == LegionRarity.COMMON) {
            floorType = FloorType.SUBFLOOR1;
        } else if (rarity == LegionRarity.UNCOMMON) {
            floorType = FloorType.SUBFLOOR2;
        } else if (rarity == LegionRarity.RARE) {
            floorType = FloorType.SUBFLOOR3;
        } else {
            return;
        }
        uint256 oldAverage = collectionToFloorTypeToPriceAvg[legionContract][floorType];
        uint256 newAverage;
        if (oldAverage == 0) {
            newAverage = _salePrice;
        } else {
            newAverage = PRBMathUD60x18.avg(oldAverage, _salePrice);
        }
        collectionToFloorTypeToPriceAvg[legionContract][floorType] = newAverage;

        emit AveragePriceUpdated(legionContract, floorType, oldAverage, _salePrice, newAverage);
    }

    /// @notice Return the current floor average for a given collection
    /// @dev    Provide a floor type to receive a recorded sub-floor average
    ///         Collections not containing subfloor records should be queried with FloorType.FLOOR
    /// @param  _collection address of collection to get floor price average of
    /// @param  _floorType the sub-floor average of the given collection
    function getAveragePriceForCollection(address _collection, FloorType _floorType) external view returns (uint256) {
        return collectionToFloorTypeToPriceAvg[_collection][_floorType];
    }

    /// @dev    This function is called by the proxy contract when a new implementation is set.
    /// @param  newImplementation address of the new implementation
    function _authorizeUpgrade(address newImplementation) internal override onlyRole(PRICE_TRACKER_ADMIN_ROLE) {}
}
