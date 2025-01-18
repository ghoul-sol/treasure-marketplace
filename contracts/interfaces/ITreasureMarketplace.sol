// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";

interface ITreasureMarketplace {
    struct CreateOrUpdateListingParams {
        address nftAddress;
        uint256 tokenId;
        uint64 quantity;
        uint128 pricePerItem;
        uint64 expirationTime;
        address paymentToken;
    }

    struct BuyItemParams {
        address nftAddress;
        uint256 tokenId;
        address owner;
        uint64 quantity;
        uint128 maxPricePerItem;
        address paymentToken;
        bool usingMagic;
    }

    struct CollectionOwnerFee {
        uint32 fee;
        address recipient;
    }

    struct CancelBidParams {
        BidType bidType;
        address nftAddress;
        uint256 tokenId;
    }

    enum TokenApprovalStatus {
        NOT_APPROVED,
        ERC_721_APPROVED,
        ERC_1155_APPROVED
    }

    enum BidType {
        TOKEN,
        COLLECTION
    }

    /// @notice The fee portion was updated
    /// @param  fee new fee amount (in units of basis points)
    event UpdateFee(uint256 fee);

    /// @notice The fee portion was updated for collections that have a collection owner.
    /// @param  fee new fee amount (in units of basis points)
    event UpdateFeeWithCollectionOwner(uint256 fee);

    /// @notice A collection's fees have changed
    /// @param  _collection  The collection
    /// @param  _recipient   The recipient of the fees. If the address is 0, the collection fees for this collection have been removed.
    /// @param  _fee         The fee amount (in units of basis points)
    event UpdateCollectionOwnerFee(address _collection, address _recipient, uint256 _fee);

    /// @notice The fee recipient was updated
    /// @param  feeRecipient the new recipient to get fees
    event UpdateFeeRecipient(address feeRecipient);

    /// @notice The approval status for a token was updated
    /// @param  nft    which token contract was updated
    /// @param  status the new status
    /// @param  paymentToken the token that will be used for payments for this collection
    event TokenApprovalStatusUpdated(address nft, TokenApprovalStatus status, address paymentToken);

    event TokenBidCreatedOrUpdated(
        address bidder,
        address nftAddress,
        uint256 tokenId,
        uint64 quantity,
        uint128 pricePerItem,
        uint64 expirationTime,
        address paymentToken
    );

    event CollectionBidCreatedOrUpdated(
        address bidder,
        address nftAddress,
        uint64 quantity,
        uint128 pricePerItem,
        uint64 expirationTime,
        address paymentToken
    );

    event TokenBidCancelled(address bidder, address nftAddress, uint256 tokenId);

    event CollectionBidCancelled(address bidder, address nftAddress);

    event BidAccepted(
        address seller,
        address bidder,
        address nftAddress,
        uint256 tokenId,
        uint64 quantity,
        uint128 pricePerItem,
        address paymentToken,
        BidType bidType
    );

    /// @notice An item was listed for sale
    /// @param  seller         the offeror of the item
    /// @param  nftAddress     which token contract holds the offered token
    /// @param  tokenId        the identifier for the offered token
    /// @param  quantity       how many of this token identifier are offered (or 1 for a ERC-721 token)
    /// @param  pricePerItem   the price (in units of the paymentToken) for each token offered
    /// @param  expirationTime UNIX timestamp after when this listing expires
    /// @param  paymentToken   the token used to list this item
    event ItemListed(
        address seller,
        address nftAddress,
        uint256 tokenId,
        uint64 quantity,
        uint128 pricePerItem,
        uint64 expirationTime,
        address paymentToken
    );

    /// @notice An item listing was updated
    /// @param  seller         the offeror of the item
    /// @param  nftAddress     which token contract holds the offered token
    /// @param  tokenId        the identifier for the offered token
    /// @param  quantity       how many of this token identifier are offered (or 1 for a ERC-721 token)
    /// @param  pricePerItem   the price (in units of the paymentToken) for each token offered
    /// @param  expirationTime UNIX timestamp after when this listing expires
    /// @param  paymentToken   the token used to list this item
    event ItemUpdated(
        address seller,
        address nftAddress,
        uint256 tokenId,
        uint64 quantity,
        uint128 pricePerItem,
        uint64 expirationTime,
        address paymentToken
    );

    /// @notice An item is no longer listed for sale
    /// @param  seller     former offeror of the item
    /// @param  nftAddress which token contract holds the formerly offered token
    /// @param  tokenId    the identifier for the formerly offered token
    event ItemCanceled(address indexed seller, address indexed nftAddress, uint256 indexed tokenId);

    /// @notice A listed item was sold
    /// @param  seller       the offeror of the item
    /// @param  buyer        the buyer of the item
    /// @param  nftAddress   which token contract holds the sold token
    /// @param  tokenId      the identifier for the sold token
    /// @param  quantity     how many of this token identifier where sold (or 1 for a ERC-721 token)
    /// @param  pricePerItem the price (in units of the paymentToken) for each token sold
    /// @param  paymentToken the payment token that was used to pay for this item
    event ItemSold(
        address seller,
        address buyer,
        address nftAddress,
        uint256 tokenId,
        uint64 quantity,
        uint128 pricePerItem,
        address paymentToken
    );

    /// @notice The sales tracker contract was update
    /// @param  _priceTrackerAddress the new address to call for sales price tracking
    event UpdateSalesTracker(address _priceTrackerAddress);

    /// @notice TREASURE_MARKETPLACE_ADMIN_ROLE role hash
    function TREASURE_MARKETPLACE_ADMIN_ROLE() external view returns (bytes32);

    /// @notice the denominator for portion calculation, i.e. how many basis points are in 100%
    function BASIS_POINTS() external view returns (uint256);

    /// @notice the maximum fee which the owner may set (in units of basis points)
    function MAX_FEE() external view returns (uint256);

    /// @notice the maximum fee which the collection owner may set
    function MAX_COLLECTION_FEE() external view returns (uint256);

    /// @notice the minimum price for which any item can be sold
    function MIN_PRICE() external view returns (uint256);

    /// @notice the default token that is used for marketplace sales and fee payments
    function paymentToken() external view returns (IERC20);

    /// @notice fee portion (in basis points) for each sale
    function fee() external view returns (uint256);

    /// @notice address that receives fees
    function feeRecipient() external view returns (address);

    /// @notice mapping for listings: nftAddress => tokenId => offeror => ListingOrBid
    function listings(address nftAddress, uint256 tokenId, address offeror)
        external
        view
        returns (uint64 quantity, uint128 pricePerItem, uint64 expirationTime, address paymentTokenAddress);

    /// @notice NFTs which are approved to be sold on the marketplace
    function tokenApprovals(address nft) external view returns (TokenApprovalStatus);

    /// @notice fee portion for collections with owner fees
    function feeWithCollectionOwner() external view returns (uint256);

    /// @notice collection owner fees: collection => CollectionOwnerFee
    function collectionToCollectionOwnerFee(address collection) external view returns (uint32 fee, address recipient);

    /// @notice collection payment tokens: collection => token
    function collectionToPaymentToken(address collection) external view returns (address);

    /// @notice The address for wMagic
    function wMagic() external view returns (IERC20);

    /// @notice mapping for token bids: nftAddress => tokenId => offeror => ListingOrBid
    function tokenBids(address nftAddress, uint256 tokenId, address offeror)
        external
        view
        returns (uint64 quantity, uint128 pricePerItem, uint64 expirationTime, address paymentTokenAddress);

    /// @notice mapping for collection bids: nftAddress => offeror => ListingOrBid
    function collectionBids(address nftAddress, address offeror)
        external
        view
        returns (uint64 quantity, uint128 pricePerItem, uint64 expirationTime, address paymentTokenAddress);

    /// @notice Indicates if bid related functions are active
    function areBidsActive() external view returns (bool);

    /// @notice Address of the contract that tracks sales and prices
    function priceTrackerAddress() external view returns (address);

    /// @notice Creates an item listing. You must authorize this marketplace with your item's token contract to list.
    /// @param  _nftAddress which token contract holds the offered token
    /// @param  _tokenId the identifier for the offered token
    /// @param  _quantity how many of this token identifier are offered (or 1 for a ERC-721 token)
    /// @param  _pricePerItem the price (in units of the paymentToken) for each token offered
    /// @param  _expirationTime UNIX timestamp after when this listing expires
    /// @param  _paymentToken the token to be used for payment
    function createListing(
        address _nftAddress,
        uint256 _tokenId,
        uint64 _quantity,
        uint128 _pricePerItem,
        uint64 _expirationTime,
        address _paymentToken
    ) external;

    /// @notice Updates an item listing
    /// @param  _nftAddress which token contract holds the offered token
    /// @param  _tokenId the identifier for the offered token
    /// @param  _newQuantity how many of this token identifier are offered
    /// @param  _newPricePerItem the price for each token offered
    /// @param  _newExpirationTime timestamp after when this listing expires
    /// @param  _paymentToken the token to be used for payment
    function updateListing(
        address _nftAddress,
        uint256 _tokenId,
        uint64 _newQuantity,
        uint128 _newPricePerItem,
        uint64 _newExpirationTime,
        address _paymentToken
    ) external;

    /// @notice Create or update multiple listings
    function createOrUpdateListings(CreateOrUpdateListingParams[] calldata _params) external;

    /// @notice Remove an item listing
    /// @param  _nftAddress which token contract holds the offered token
    /// @param  _tokenId    the identifier for the offered token
    function cancelListing(address _nftAddress, uint256 _tokenId) external;

    /// @notice Buy multiple listed items
    function buyItems(BuyItemParams[] calldata _buyItemParams) external payable;

    /// @notice Updates the fee amount for sales
    /// @param  _newFee the updated fee amount in basis points
    /// @param  _newFeeWithCollectionOwner fee for collections with owners
    function setFee(uint256 _newFee, uint256 _newFeeWithCollectionOwner) external;

    /// @notice Updates collection owner fees
    /// @param  _collectionAddress The collection to update
    /// @param  _collectionOwnerFee The new fee configuration
    function setCollectionOwnerFee(address _collectionAddress, CollectionOwnerFee calldata _collectionOwnerFee)
        external;

    /// @notice Updates the fee recipient
    /// @param  _newFeeRecipient the wallet to receive fees
    function setFeeRecipient(address _newFeeRecipient) external;

    /// @notice Sets token approval status
    /// @param  _nft address of the NFT to be approved
    /// @param  _status the kind of NFT approved
    /// @param  _paymentToken the token used for payments
    function setTokenApprovalStatus(address _nft, TokenApprovalStatus _status, address _paymentToken) external;

    /// @notice Updates the price tracker address
    function setPriceTracker(address _priceTrackerAddress) external;

    /// @notice Toggles bid functionality
    function toggleAreBidsActive() external;

    /// @notice Pauses the marketplace
    function pause() external;

    /// @notice Unpauses the marketplace
    function unpause() external;

    /// @notice Gets the payment token for a collection
    /// @param  collection The collection address
    /// @return The payment token address for the collection, or the default payment token if none is set
    function getPaymentTokenForCollection(address collection) external view returns (address);

    /// @notice Creates or updates a bid for a specific token
    /// @param  _nftAddress The address of the NFT contract
    /// @param  _tokenId The token ID to bid on
    /// @param  _quantity The quantity of tokens to bid for
    /// @param  _pricePerItem The price per item offered
    /// @param  _expirationTime When the bid expires
    /// @param  _paymentToken The token to be used for payment
    function createOrUpdateTokenBid(
        address _nftAddress,
        uint256 _tokenId,
        uint64 _quantity,
        uint128 _pricePerItem,
        uint64 _expirationTime,
        address _paymentToken
    ) external;

    /// @notice Creates or updates a bid for an entire collection
    /// @param  _nftAddress The address of the NFT contract
    /// @param  _quantity The quantity of tokens to bid for
    /// @param  _pricePerItem The price per item offered
    /// @param  _expirationTime When the bid expires
    /// @param  _paymentToken The token to be used for payment
    function createOrUpdateCollectionBid(
        address _nftAddress,
        uint64 _quantity,
        uint128 _pricePerItem,
        uint64 _expirationTime,
        address _paymentToken
    ) external;
}
