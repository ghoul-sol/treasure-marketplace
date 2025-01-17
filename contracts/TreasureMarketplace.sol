// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {IERC165} from "@openzeppelin/contracts/interfaces/IERC165.sol";
import {IERC721} from "@openzeppelin/contracts/token/ERC721/IERC721.sol";
import {IERC1155} from "@openzeppelin/contracts/token/ERC1155/IERC1155.sol";
import {OwnableUpgradeable} from "@openzeppelin/contracts-upgradeable/access/OwnableUpgradeable.sol";
import {AccessControlEnumerableUpgradeable} from
    "@openzeppelin/contracts-upgradeable/access/extensions/AccessControlEnumerableUpgradeable.sol";
import {ReentrancyGuardUpgradeable} from "@openzeppelin/contracts-upgradeable/utils/ReentrancyGuardUpgradeable.sol";
import {PausableUpgradeable} from "@openzeppelin/contracts-upgradeable/utils/PausableUpgradeable.sol";
import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import {Initializable} from "@openzeppelin/contracts-upgradeable/proxy/utils/Initializable.sol";
import {UUPSUpgradeable} from "@openzeppelin/contracts-upgradeable/proxy/utils/UUPSUpgradeable.sol";
import {ITreasureMarketplace} from "./interfaces/ITreasureMarketplace.sol";

/// @title  Treasure NFT marketplace
/// @notice This contract allows you to buy and sell NFTs from token contracts that are approved by the contract owner.
///         This contract uses the UUPS upgrade pattern. Only accounts with TREASURE_MARKETPLACE_ADMIN_ROLE can upgrade
///         the implementation.
/// @dev    This contract does not store any tokens at any time, it's only collects details "the sale" and approvals
///         from both parties and preforms non-custodial transaction by transfering NFT from owner to buying and payment
///         token from buying to NFT owner.
contract TreasureMarketplace is
    Initializable,
    UUPSUpgradeable,
    AccessControlEnumerableUpgradeable,
    PausableUpgradeable,
    ReentrancyGuardUpgradeable,
    ITreasureMarketplace
{
    using SafeERC20 for IERC20;

    struct ListingOrBid {
        /// @dev number of tokens for sale or requested (1 if ERC-721 token is active for sale) (for bids, quantity for ERC-721 can be greater than 1)
        uint64 quantity;
        /// @dev price per token sold, i.e. extended sale price equals this times quantity purchased. For bids, price offered per item.
        uint128 pricePerItem;
        /// @dev timestamp after which the listing/bid is invalid
        uint64 expirationTime;
        /// @dev the payment token for this listing/bid.
        address paymentTokenAddress;
    }

    bytes32 public constant TREASURE_MARKETPLACE_ADMIN_ROLE = keccak256("TREASURE_MARKETPLACE_ADMIN_ROLE");
    uint256 public constant BASIS_POINTS = 10000;
    uint256 public constant MAX_FEE = 1500;
    uint256 public constant MAX_COLLECTION_FEE = 2000;
    uint256 public constant MIN_PRICE = 1e9;

    /// @notice ERC165 interface signatures
    bytes4 private constant INTERFACE_ID_ERC721 = 0x80ac58cd;
    bytes4 private constant INTERFACE_ID_ERC1155 = 0xd9b67a26;

    IERC20 public paymentToken;
    IERC20 public wMagic;
    uint256 public fee;
    address public feeReceipient;
    address public priceTrackerAddress;
    uint256 public feeWithCollectionOwner;
    bool public areBidsActive;

    mapping(address => mapping(uint256 => mapping(address => ListingOrBid))) public listings;
    mapping(address => TokenApprovalStatus) public tokenApprovals;
    mapping(address => CollectionOwnerFee) public collectionToCollectionOwnerFee;
    mapping(address => address) public collectionToPaymentToken;
    mapping(address => mapping(uint256 => mapping(address => ListingOrBid))) public tokenBids;
    mapping(address => mapping(address => ListingOrBid)) public collectionBids;

    /// @custom:oz-upgrades-unsafe-allow constructor
    constructor() {
        _disableInitializers();
    }

    /// @notice Perform initial contract setup
    /// @dev    The initializer modifier ensures this is only called once, the owner should confirm this was properly
    ///         performed before publishing this contract address.
    /// @param  _initialFee          fee to be paid on each sale, in basis points
    /// @param  _initialFeeWithCollectionOwner fee to be paid on each sale, in basis points
    /// @param  _initialFeeRecipient wallet to collets fees
    /// @param  _paymentToken address of the token that is used for settlement
    /// @param  _wMagic       address of the wMagic token
    function initialize(
        uint256 _initialFee,
        uint256 _initialFeeWithCollectionOwner,
        address _initialFeeRecipient,
        address _paymentToken,
        address _wMagic
    ) external initializer {
        require(address(_paymentToken) != address(0), "TreasureMarketplace: cannot set address(0)");
        require(address(_wMagic) != address(0), "TreasureMarketplace: cannot set address(0)");

        __UUPSUpgradeable_init();
        __AccessControl_init_unchained();
        __Pausable_init_unchained();
        __ReentrancyGuard_init_unchained();

        _setRoleAdmin(TREASURE_MARKETPLACE_ADMIN_ROLE, TREASURE_MARKETPLACE_ADMIN_ROLE);
        _grantRole(TREASURE_MARKETPLACE_ADMIN_ROLE, msg.sender);

        setFee(_initialFee, _initialFeeWithCollectionOwner);
        setFeeRecipient(_initialFeeRecipient);
        paymentToken = IERC20(_paymentToken);
        wMagic = IERC20(_wMagic);
    }

    /// @notice Creates an item listing. You must authorize this marketplace with your item's token contract to list.
    /// @param  _nftAddress     which token contract holds the offered token
    /// @param  _tokenId        the identifier for the offered token
    /// @param  _quantity       how many of this token identifier are offered (or 1 for a ERC-721 token)
    /// @param  _pricePerItem   the price (in units of the paymentToken) for each token offered
    /// @param  _expirationTime UNIX timestamp after when this listing expires
    function createListing(
        address _nftAddress,
        uint256 _tokenId,
        uint64 _quantity,
        uint128 _pricePerItem,
        uint64 _expirationTime,
        address _paymentToken
    ) external nonReentrant whenNotPaused {
        require(listings[_nftAddress][_tokenId][_msgSender()].quantity == 0, "TreasureMarketplace: already listed");
        _createListingWithoutEvent(_nftAddress, _tokenId, _quantity, _pricePerItem, _expirationTime, _paymentToken);
        emit ItemListed(_msgSender(), _nftAddress, _tokenId, _quantity, _pricePerItem, _expirationTime, _paymentToken);
    }

    /// @notice Updates an item listing
    /// @param  _nftAddress        which token contract holds the offered token
    /// @param  _tokenId           the identifier for the offered token
    /// @param  _newQuantity       how many of this token identifier are offered (or 1 for a ERC-721 token)
    /// @param  _newPricePerItem   the price (in units of the paymentToken) for each token offered
    /// @param  _newExpirationTime UNIX timestamp after when this listing expires
    function updateListing(
        address _nftAddress,
        uint256 _tokenId,
        uint64 _newQuantity,
        uint128 _newPricePerItem,
        uint64 _newExpirationTime,
        address _paymentToken
    ) external nonReentrant whenNotPaused {
        require(listings[_nftAddress][_tokenId][_msgSender()].quantity > 0, "TreasureMarketplace: not listed item");
        _createListingWithoutEvent(
            _nftAddress, _tokenId, _newQuantity, _newPricePerItem, _newExpirationTime, _paymentToken
        );
        emit ItemUpdated(
            _msgSender(), _nftAddress, _tokenId, _newQuantity, _newPricePerItem, _newExpirationTime, _paymentToken
        );
    }

    /// @notice Create or update multiple listings.
    function createOrUpdateListings(CreateOrUpdateListingParams[] calldata _createOrUpdateListingParams)
        external
        nonReentrant
        whenNotPaused
    {
        for (uint256 i = 0; i < _createOrUpdateListingParams.length;) {
            CreateOrUpdateListingParams calldata _createOrUpdateListingParam = _createOrUpdateListingParams[i];
            _createOrUpdateListing(
                _createOrUpdateListingParam.nftAddress,
                _createOrUpdateListingParam.tokenId,
                _createOrUpdateListingParam.quantity,
                _createOrUpdateListingParam.pricePerItem,
                _createOrUpdateListingParam.expirationTime,
                _createOrUpdateListingParam.paymentToken
            );
            unchecked {
                i += 1;
            }
        }
    }

    function createOrUpdateListing(
        address _nftAddress,
        uint256 _tokenId,
        uint64 _quantity,
        uint128 _pricePerItem,
        uint64 _expirationTime,
        address _paymentToken
    ) external nonReentrant whenNotPaused {
        _createOrUpdateListing(_nftAddress, _tokenId, _quantity, _pricePerItem, _expirationTime, _paymentToken);
    }

    function _createOrUpdateListing(
        address _nftAddress,
        uint256 _tokenId,
        uint64 _quantity,
        uint128 _pricePerItem,
        uint64 _expirationTime,
        address _paymentToken
    ) internal {
        bool _existingListing = listings[_nftAddress][_tokenId][_msgSender()].quantity > 0;
        _createListingWithoutEvent(_nftAddress, _tokenId, _quantity, _pricePerItem, _expirationTime, _paymentToken);
        // Keep the events the same as they were before.
        if (_existingListing) {
            emit ItemUpdated(
                _msgSender(), _nftAddress, _tokenId, _quantity, _pricePerItem, _expirationTime, _paymentToken
            );
        } else {
            emit ItemListed(
                _msgSender(), _nftAddress, _tokenId, _quantity, _pricePerItem, _expirationTime, _paymentToken
            );
        }
    }

    /// @notice Performs the listing and does not emit the event
    /// @param  _nftAddress     which token contract holds the offered token
    /// @param  _tokenId        the identifier for the offered token
    /// @param  _quantity       how many of this token identifier are offered (or 1 for a ERC-721 token)
    /// @param  _pricePerItem   the price (in units of the paymentToken) for each token offered
    /// @param  _expirationTime UNIX timestamp after when this listing expires
    function _createListingWithoutEvent(
        address _nftAddress,
        uint256 _tokenId,
        uint64 _quantity,
        uint128 _pricePerItem,
        uint64 _expirationTime,
        address _paymentToken
    ) internal {
        require(_expirationTime > block.timestamp, "TreasureMarketplace: invalid expiration time");
        require(_pricePerItem >= MIN_PRICE, "TreasureMarketplace: below min price");

        if (tokenApprovals[_nftAddress] == TokenApprovalStatus.ERC_721_APPROVED) {
            IERC721 nft = IERC721(_nftAddress);
            require(nft.ownerOf(_tokenId) == _msgSender(), "TreasureMarketplace: not owning item");
            require(nft.isApprovedForAll(_msgSender(), address(this)), "TreasureMarketplace: item not approved");
            require(_quantity == 1, "TreasureMarketplace: cannot list multiple ERC721");
        } else if (tokenApprovals[_nftAddress] == TokenApprovalStatus.ERC_1155_APPROVED) {
            IERC1155 nft = IERC1155(_nftAddress);
            require(nft.balanceOf(_msgSender(), _tokenId) >= _quantity, "TreasureMarketplace: must hold enough nfts");
            require(nft.isApprovedForAll(_msgSender(), address(this)), "TreasureMarketplace: item not approved");
            require(_quantity > 0, "TreasureMarketplace: nothing to list");
        } else {
            revert("TreasureMarketplace: token is not approved for trading");
        }

        address _paymentTokenForCollection = getPaymentTokenForCollection(_nftAddress);
        require(_paymentTokenForCollection == _paymentToken, "TreasureMarketplace: Wrong payment token");

        listings[_nftAddress][_tokenId][_msgSender()] =
            ListingOrBid(_quantity, _pricePerItem, _expirationTime, _paymentToken);
    }

    /// @notice Remove an item listing
    /// @param  _nftAddress which token contract holds the offered token
    /// @param  _tokenId    the identifier for the offered token
    function cancelListing(address _nftAddress, uint256 _tokenId) external nonReentrant {
        delete (listings[_nftAddress][_tokenId][_msgSender()]);
        emit ItemCanceled(_msgSender(), _nftAddress, _tokenId);
    }

    function cancelManyBids(CancelBidParams[] calldata _cancelBidParams) external nonReentrant {
        for (uint256 i = 0; i < _cancelBidParams.length; i++) {
            CancelBidParams calldata _cancelBidParam = _cancelBidParams[i];
            if (_cancelBidParam.bidType == BidType.COLLECTION) {
                collectionBids[_cancelBidParam.nftAddress][_msgSender()].quantity = 0;

                emit CollectionBidCancelled(_msgSender(), _cancelBidParam.nftAddress);
            } else {
                tokenBids[_cancelBidParam.nftAddress][_cancelBidParam.tokenId][_msgSender()].quantity = 0;

                emit TokenBidCancelled(_msgSender(), _cancelBidParam.nftAddress, _cancelBidParam.tokenId);
            }
        }
    }

    /// @notice Creates a bid for a particular token.
    function createOrUpdateTokenBid(
        address _nftAddress,
        uint256 _tokenId,
        uint64 _quantity,
        uint128 _pricePerItem,
        uint64 _expirationTime,
        address _paymentToken
    ) external nonReentrant whenNotPaused whenBiddingActive {
        if (tokenApprovals[_nftAddress] == TokenApprovalStatus.ERC_721_APPROVED) {
            require(_quantity == 1, "TreasureMarketplace: token bid quantity 1 for ERC721");
        } else if (tokenApprovals[_nftAddress] == TokenApprovalStatus.ERC_1155_APPROVED) {
            require(_quantity > 0, "TreasureMarketplace: bad quantity");
        } else {
            revert("TreasureMarketplace: token is not approved for trading");
        }

        _createBidWithoutEvent(
            _nftAddress,
            _quantity,
            _pricePerItem,
            _expirationTime,
            _paymentToken,
            tokenBids[_nftAddress][_tokenId][_msgSender()]
        );

        emit TokenBidCreatedOrUpdated(
            _msgSender(), _nftAddress, _tokenId, _quantity, _pricePerItem, _expirationTime, _paymentToken
        );
    }

    function createOrUpdateCollectionBid(
        address _nftAddress,
        uint64 _quantity,
        uint128 _pricePerItem,
        uint64 _expirationTime,
        address _paymentToken
    ) external nonReentrant whenNotPaused whenBiddingActive {
        if (tokenApprovals[_nftAddress] == TokenApprovalStatus.ERC_721_APPROVED) {
            require(_quantity > 0, "TreasureMarketplace: Bad quantity");
        } else if (tokenApprovals[_nftAddress] == TokenApprovalStatus.ERC_1155_APPROVED) {
            revert("TreasureMarketplace: No collection bids on 1155s");
        } else {
            revert("TreasureMarketplace: token is not approved for trading");
        }

        _createBidWithoutEvent(
            _nftAddress,
            _quantity,
            _pricePerItem,
            _expirationTime,
            _paymentToken,
            collectionBids[_nftAddress][_msgSender()]
        );

        emit CollectionBidCreatedOrUpdated(
            _msgSender(), _nftAddress, _quantity, _pricePerItem, _expirationTime, _paymentToken
        );
    }

    function _createBidWithoutEvent(
        address _nftAddress,
        uint64 _quantity,
        uint128 _pricePerItem,
        uint64 _expirationTime,
        address _paymentToken,
        ListingOrBid storage _bid
    ) private {
        require(_expirationTime > block.timestamp, "TreasureMarketplace: invalid expiration time");
        require(_pricePerItem >= MIN_PRICE, "TreasureMarketplace: below min price");

        address _paymentTokenForCollection = getPaymentTokenForCollection(_nftAddress);
        require(_paymentTokenForCollection == _paymentToken, "TreasureMarketplace: Bad payment token");

        IERC20 _token = IERC20(_paymentToken);

        uint256 _totalAmountNeeded = _pricePerItem * _quantity;

        require(
            _token.allowance(_msgSender(), address(this)) >= _totalAmountNeeded
                && _token.balanceOf(_msgSender()) >= _totalAmountNeeded,
            "TreasureMarketplace: Not enough tokens owned or allowed for bid"
        );

        _bid.quantity = _quantity;
        _bid.pricePerItem = _pricePerItem;
        _bid.expirationTime = _expirationTime;
        _bid.paymentTokenAddress = _paymentToken;
    }

    function acceptCollectionBid(AcceptBidParams calldata _acceptBidParams)
        external
        nonReentrant
        whenNotPaused
        whenBiddingActive
    {
        _acceptBid(_acceptBidParams, BidType.COLLECTION);
    }

    function acceptTokenBid(AcceptBidParams calldata _acceptBidParams)
        external
        nonReentrant
        whenNotPaused
        whenBiddingActive
    {
        _acceptBid(_acceptBidParams, BidType.TOKEN);
    }

    function _acceptBid(AcceptBidParams calldata _acceptBidParams, BidType _bidType) private {
        // Validate buy order
        require(_msgSender() != _acceptBidParams.bidder, "TreasureMarketplace: Cannot supply own bid");
        require(_acceptBidParams.quantity > 0, "TreasureMarketplace: Nothing to supply to bidder");

        // Validate bid
        ListingOrBid storage _bid = _bidType == BidType.COLLECTION
            ? collectionBids[_acceptBidParams.nftAddress][_acceptBidParams.bidder]
            : tokenBids[_acceptBidParams.nftAddress][_acceptBidParams.tokenId][_acceptBidParams.bidder];

        require(_bid.quantity > 0, "TreasureMarketplace: bid does not exist");
        require(_bid.expirationTime >= block.timestamp, "TreasureMarketplace: bid expired");
        require(_bid.pricePerItem > 0, "TreasureMarketplace: bid price invalid");
        require(_bid.quantity >= _acceptBidParams.quantity, "TreasureMarketplace: not enough quantity");
        require(_bid.pricePerItem == _acceptBidParams.pricePerItem, "TreasureMarketplace: price does not match");

        // Ensure the accepter, the bidder, and the collection all agree on the token to be used for the purchase.
        // If the token used for buying/selling has changed since the bid was created, this effectively blocks
        // all the old bids with the old payment tokens from being bought.
        address _paymentTokenForCollection = getPaymentTokenForCollection(_acceptBidParams.nftAddress);

        require(
            _bid.paymentTokenAddress == _acceptBidParams.paymentToken
                && _acceptBidParams.paymentToken == _paymentTokenForCollection,
            "TreasureMarketplace: Wrong payment token"
        );

        // Transfer NFT to buyer, also validates owner owns it, and token is approved for trading
        if (tokenApprovals[_acceptBidParams.nftAddress] == TokenApprovalStatus.ERC_721_APPROVED) {
            require(_acceptBidParams.quantity == 1, "TreasureMarketplace: Cannot supply multiple ERC721s");

            IERC721(_acceptBidParams.nftAddress).safeTransferFrom(
                _msgSender(), _acceptBidParams.bidder, _acceptBidParams.tokenId
            );
        } else if (tokenApprovals[_acceptBidParams.nftAddress] == TokenApprovalStatus.ERC_1155_APPROVED) {
            IERC1155(_acceptBidParams.nftAddress).safeTransferFrom(
                _msgSender(), _acceptBidParams.bidder, _acceptBidParams.tokenId, _acceptBidParams.quantity, bytes("")
            );
        } else {
            revert("TreasureMarketplace: token is not approved for trading");
        }

        _payFees(
            _bid,
            _acceptBidParams.quantity,
            _acceptBidParams.nftAddress,
            _acceptBidParams.bidder,
            _msgSender(),
            _acceptBidParams.paymentToken,
            false
        );

        // Announce accepting bid
        emit BidAccepted(
            _msgSender(),
            _acceptBidParams.bidder,
            _acceptBidParams.nftAddress,
            _acceptBidParams.tokenId,
            _acceptBidParams.quantity,
            _acceptBidParams.pricePerItem,
            _acceptBidParams.paymentToken,
            _bidType
        );

        // Deplete or cancel listing
        _bid.quantity -= _acceptBidParams.quantity;
    }

    /// @notice Buy multiple listed items. You must authorize this marketplace with your payment token to completed the buy or purchase with magic if it is a wMagic collection.
    function buyItems(BuyItemParams[] calldata _buyItemParams) external payable nonReentrant whenNotPaused {
        uint256 _magicAmountRequired;
        for (uint256 i = 0; i < _buyItemParams.length; i++) {
            _magicAmountRequired += _buyItem(_buyItemParams[i]);
        }

        require(msg.value == _magicAmountRequired, "TreasureMarketplace: Bad magic value");
    }

    // Returns the amount of magic a user must have sent.
    function _buyItem(BuyItemParams calldata _buyItemParams) private returns (uint256) {
        // Validate buy order
        require(_msgSender() != _buyItemParams.owner, "TreasureMarketplace: Cannot buy your own item");
        require(_buyItemParams.quantity > 0, "TreasureMarketplace: Nothing to buy");

        // Validate listing
        ListingOrBid memory listedItem =
            listings[_buyItemParams.nftAddress][_buyItemParams.tokenId][_buyItemParams.owner];
        require(listedItem.quantity > 0, "TreasureMarketplace: not listed item");
        require(listedItem.expirationTime >= block.timestamp, "TreasureMarketplace: listing expired");
        require(listedItem.pricePerItem > 0, "TreasureMarketplace: listing price invalid");
        require(listedItem.quantity >= _buyItemParams.quantity, "TreasureMarketplace: not enough quantity");
        require(listedItem.pricePerItem <= _buyItemParams.maxPricePerItem, "TreasureMarketplace: price increased");

        // Ensure the buyer, the seller, and the collection all agree on the token to be used for the purchase.
        // If the token used for buying/selling has changed since the listing was created, this effectively blocks
        // all the old listings with the old payment tokens from being bought.
        address _paymentTokenForCollection = getPaymentTokenForCollection(_buyItemParams.nftAddress);
        address _paymentTokenForListing = _getPaymentTokenForListing(listedItem);

        require(
            _paymentTokenForListing == _buyItemParams.paymentToken
                && _buyItemParams.paymentToken == _paymentTokenForCollection,
            "TreasureMarketplace: Wrong payment token"
        );

        if (_buyItemParams.usingMagic) {
            require(
                _paymentTokenForListing == address(wMagic),
                "TreasureMarketplace: magic only used with wMagic collection"
            );
        }

        // Transfer NFT to buyer, also validates owner owns it, and token is approved for trading
        if (tokenApprovals[_buyItemParams.nftAddress] == TokenApprovalStatus.ERC_721_APPROVED) {
            require(_buyItemParams.quantity == 1, "TreasureMarketplace: Cannot buy multiple ERC721");
            IERC721(_buyItemParams.nftAddress).safeTransferFrom(
                _buyItemParams.owner, _msgSender(), _buyItemParams.tokenId
            );
        } else if (tokenApprovals[_buyItemParams.nftAddress] == TokenApprovalStatus.ERC_1155_APPROVED) {
            IERC1155(_buyItemParams.nftAddress).safeTransferFrom(
                _buyItemParams.owner, _msgSender(), _buyItemParams.tokenId, _buyItemParams.quantity, bytes("")
            );
        } else {
            revert("TreasureMarketplace: token is not approved for trading");
        }

        _payFees(
            listedItem,
            _buyItemParams.quantity,
            _buyItemParams.nftAddress,
            _msgSender(),
            _buyItemParams.owner,
            _buyItemParams.paymentToken,
            _buyItemParams.usingMagic
        );

        // Announce sale
        emit ItemSold(
            _buyItemParams.owner,
            _msgSender(),
            _buyItemParams.nftAddress,
            _buyItemParams.tokenId,
            _buyItemParams.quantity,
            listedItem.pricePerItem, // this is deleted below in "Deplete or cancel listing"
            _buyItemParams.paymentToken
        );

        // Deplete or cancel listing
        if (listedItem.quantity == _buyItemParams.quantity) {
            delete listings[_buyItemParams.nftAddress][_buyItemParams.tokenId][_buyItemParams.owner];
        } else {
            listings[_buyItemParams.nftAddress][_buyItemParams.tokenId][_buyItemParams.owner].quantity -=
                _buyItemParams.quantity;
        }

        if (_buyItemParams.usingMagic) {
            return _buyItemParams.quantity * listedItem.pricePerItem;
        } else {
            return 0;
        }
    }

    /// @dev pays the fees to the marketplace fee recipient, the collection recipient if one exists, and to the seller of the item.
    /// @param _listOrBid the item that is being purchased/accepted
    /// @param _quantity the quantity of the item being purchased/accepted
    /// @param _collectionAddress the collection to which this item belongs
    function _payFees(
        ListingOrBid memory _listOrBid,
        uint256 _quantity,
        address _collectionAddress,
        address _from,
        address _to,
        address _paymentTokenAddress,
        bool _usingMagic
    ) private {
        IERC20 _paymentToken = IERC20(_paymentTokenAddress);

        // Handle purchase price payment
        uint256 _totalPrice = _listOrBid.pricePerItem * _quantity;

        address _collectionFeeRecipient = collectionToCollectionOwnerFee[_collectionAddress].recipient;

        uint256 _protocolFee;
        uint256 _collectionFee;

        if (_collectionFeeRecipient != address(0)) {
            _protocolFee = feeWithCollectionOwner;
            _collectionFee = collectionToCollectionOwnerFee[_collectionAddress].fee;
        } else {
            _protocolFee = fee;
            _collectionFee = 0;
        }

        uint256 _protocolFeeAmount = _totalPrice * _protocolFee / BASIS_POINTS;
        uint256 _collectionFeeAmount = _totalPrice * _collectionFee / BASIS_POINTS;

        _transferAmount(_from, feeReceipient, _protocolFeeAmount, _paymentToken, _usingMagic);
        _transferAmount(_from, _collectionFeeRecipient, _collectionFeeAmount, _paymentToken, _usingMagic);

        // Transfer rest to seller
        _transferAmount(_from, _to, _totalPrice - _protocolFeeAmount - _collectionFeeAmount, _paymentToken, _usingMagic);
    }

    function _transferAmount(address _from, address _to, uint256 _amount, IERC20 _paymentToken, bool _usingMagic)
        private
    {
        if (_amount == 0) {
            return;
        }

        if (_usingMagic) {
            (bool _success,) = payable(_to).call{value: _amount}("");
            require(_success, "TreasureMarketplace: Sending magic was not successful");
        } else {
            _paymentToken.safeTransferFrom(_from, _to, _amount);
        }
    }

    function getPaymentTokenForCollection(address _collection) public view returns (address) {
        address _collectionPaymentToken = collectionToPaymentToken[_collection];

        // For backwards compatability. If a collection payment wasn't set at the collection level, it was using the payment token.
        return _collectionPaymentToken == address(0) ? address(paymentToken) : _collectionPaymentToken;
    }

    function _getPaymentTokenForListing(ListingOrBid memory listedItem) private view returns (address) {
        // For backwards compatability. If a listing has no payment token address, it was using the original, default payment token.
        return listedItem.paymentTokenAddress == address(0) ? address(paymentToken) : listedItem.paymentTokenAddress;
    }

    // Owner administration ////////////////////////////////////////////////////////////////////////////////////////////

    /// @notice Updates the fee amount which is collected during sales, for both collections with and without owner specific fees.
    /// @dev    This is callable only by the owner. Both fees may not exceed MAX_FEE
    /// @param  _newFee the updated fee amount is basis points
    function setFee(uint256 _newFee, uint256 _newFeeWithCollectionOwner)
        public
        onlyRole(TREASURE_MARKETPLACE_ADMIN_ROLE)
    {
        require(_newFee <= MAX_FEE && _newFeeWithCollectionOwner <= MAX_FEE, "TreasureMarketplace: max fee");

        fee = _newFee;
        feeWithCollectionOwner = _newFeeWithCollectionOwner;

        emit UpdateFee(_newFee);
        emit UpdateFeeWithCollectionOwner(_newFeeWithCollectionOwner);
    }

    /// @notice Updates the fee amount which is collected during sales fro a specific collection
    /// @dev    This is callable only by the owner
    /// @param  _collectionAddress The collection in question. This must be whitelisted.
    /// @param _collectionOwnerFee The fee and recipient for the collection. If the 0 address is passed as the recipient, collection specific fees will not be collected.
    function setCollectionOwnerFee(address _collectionAddress, CollectionOwnerFee calldata _collectionOwnerFee)
        external
        onlyRole(TREASURE_MARKETPLACE_ADMIN_ROLE)
    {
        require(
            tokenApprovals[_collectionAddress] == TokenApprovalStatus.ERC_1155_APPROVED
                || tokenApprovals[_collectionAddress] == TokenApprovalStatus.ERC_721_APPROVED,
            "TreasureMarketplace: Collection is not approved"
        );
        require(_collectionOwnerFee.fee <= MAX_COLLECTION_FEE, "TreasureMarketplace: Collection fee too high");

        // The collection recipient can be the 0 address, meaning we will treat this as a collection with no collection owner fee.
        collectionToCollectionOwnerFee[_collectionAddress] = _collectionOwnerFee;

        emit UpdateCollectionOwnerFee(_collectionAddress, _collectionOwnerFee.recipient, _collectionOwnerFee.fee);
    }

    /// @notice Updates the fee recipient which receives fees during sales
    /// @dev    This is callable only by the owner.
    /// @param  _newFeeRecipient the wallet to receive fees
    function setFeeRecipient(address _newFeeRecipient) public onlyRole(TREASURE_MARKETPLACE_ADMIN_ROLE) {
        require(_newFeeRecipient != address(0), "TreasureMarketplace: cannot set 0x0 address");
        feeReceipient = _newFeeRecipient;
        emit UpdateFeeRecipient(_newFeeRecipient);
    }

    /// @notice Sets a token as an approved kind of NFT or as ineligible for trading
    /// @dev    This is callable only by the owner.
    /// @param  _nft    address of the NFT to be approved
    /// @param  _status the kind of NFT approved, or NOT_APPROVED to remove approval
    function setTokenApprovalStatus(address _nft, TokenApprovalStatus _status, address _paymentToken)
        external
        onlyRole(TREASURE_MARKETPLACE_ADMIN_ROLE)
    {
        if (_status == TokenApprovalStatus.ERC_721_APPROVED) {
            require(IERC165(_nft).supportsInterface(INTERFACE_ID_ERC721), "TreasureMarketplace: not an ERC721 contract");
        } else if (_status == TokenApprovalStatus.ERC_1155_APPROVED) {
            require(
                IERC165(_nft).supportsInterface(INTERFACE_ID_ERC1155), "TreasureMarketplace: not an ERC1155 contract"
            );
        }

        require(
            _paymentToken != address(0) && (_paymentToken == address(wMagic) || _paymentToken == address(paymentToken)),
            "TreasureMarketplace: Payment token not supported"
        );

        tokenApprovals[_nft] = _status;

        collectionToPaymentToken[_nft] = _paymentToken;
        emit TokenApprovalStatusUpdated(_nft, _status, _paymentToken);
    }

    /// @notice Updates the fee recipient which receives fees during sales
    /// @dev    This is callable only by the owner.
    /// @param  _priceTrackerAddress the wallet to receive fees
    function setPriceTracker(address _priceTrackerAddress) public onlyRole(TREASURE_MARKETPLACE_ADMIN_ROLE) {
        require(_priceTrackerAddress != address(0), "TreasureMarketplace: cannot set 0x0 address");
        priceTrackerAddress = _priceTrackerAddress;
        emit UpdateSalesTracker(_priceTrackerAddress);
    }

    function toggleAreBidsActive() external onlyRole(TREASURE_MARKETPLACE_ADMIN_ROLE) {
        areBidsActive = !areBidsActive;
    }

    /// @notice Pauses the marketplace, creatisgn and executing listings is paused
    /// @dev    This is callable only by the owner. Canceling listings is not paused.
    function pause() external onlyRole(TREASURE_MARKETPLACE_ADMIN_ROLE) {
        _pause();
    }

    /// @notice Unpauses the marketplace, all functionality is restored
    /// @dev    This is callable only by the owner.
    function unpause() external onlyRole(TREASURE_MARKETPLACE_ADMIN_ROLE) {
        _unpause();
    }

    modifier whenBiddingActive() {
        require(areBidsActive, "TreasureMarketplace: Bidding is not active");

        _;
    }

    /// @dev Function that should revert when `msg.sender` is not authorized to upgrade the contract. Called by
    ///      {upgradeTo} and {upgradeToAndCall}.
    /// @param newImplementation address of the new implementation
    function _authorizeUpgrade(address newImplementation) internal override onlyRole(TREASURE_MARKETPLACE_ADMIN_ROLE) {}
}

struct AcceptBidParams {
    // Which token contract holds the given tokens
    address nftAddress;
    // The token id being given
    uint256 tokenId;
    // The user who created the bid initially
    address bidder;
    // The quantity of items being supplied to the bidder
    uint64 quantity;
    // The price per item that the bidder is offering
    uint128 pricePerItem;
    /// the payment token to be used
    address paymentToken;
}
