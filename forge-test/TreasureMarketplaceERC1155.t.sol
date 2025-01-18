// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import {Test} from "forge-std/Test.sol";
import {TreasureMarketplaceTest} from "./TreasureMarketplaceTest.sol";
import {TreasureMarketplace} from "../contracts/TreasureMarketplace.sol";
import {ITreasureMarketplace} from "../contracts/interfaces/ITreasureMarketplace.sol";
import {ERC1155Mintable} from "./mocks/ERC1155Mintable.sol";
import {ERC20Mintable} from "./mocks/ERC20Mintable.sol";
import {ERC1967Proxy} from "@openzeppelin/contracts/proxy/ERC1967/ERC1967Proxy.sol";
import {IAccessControl} from "@openzeppelin/contracts/access/IAccessControl.sol";
import {Pausable} from "@openzeppelin/contracts/utils/Pausable.sol";

contract TreasureMarketplaceERC1155Test is TreasureMarketplaceTest {
    function test_ERC1155_BuyingWithQuantityZero() public {
        uint256 tokenId = 0;
        uint64 quantity = 5;

        _mintAndApproveERC1155(seller, tokenId, quantity);
        _approveMarketplaceERC1155();

        vm.startPrank(seller);
        ITreasureMarketplace(proxy).createListing(
            address(erc1155), tokenId, quantity, pricePerItem, expirationTime, address(magicToken)
        );
        vm.stopPrank();

        _setupBuyerWithFunds(pricePerItem);

        vm.startPrank(buyer);
        ITreasureMarketplace.BuyItemParams[] memory buyItems =
            _createERC1155BuyItemParams(tokenId, seller, 0, pricePerItem, address(magicToken));
        vm.expectRevert("TreasureMarketplace: Nothing to buy");
        ITreasureMarketplace(proxy).buyItems(buyItems);
        vm.stopPrank();
    }

    function test_ERC1155_BuyingWithQuantityTooHigh() public {
        uint256 tokenId = 0;
        uint64 quantity = 5;
        uint64 buyQuantity = quantity + 1; // Try to buy more than available

        _mintAndApproveERC1155(seller, tokenId, quantity);
        _approveMarketplaceERC1155();

        vm.startPrank(seller);
        ITreasureMarketplace(proxy).createListing(
            address(erc1155), tokenId, quantity, pricePerItem, expirationTime, address(magicToken)
        );
        vm.stopPrank();

        _setupBuyerWithFunds(pricePerItem * buyQuantity);

        vm.startPrank(buyer);
        ITreasureMarketplace.BuyItemParams[] memory buyItems =
            _createERC1155BuyItemParams(tokenId, seller, buyQuantity, pricePerItem, address(magicToken));
        vm.expectRevert("TreasureMarketplace: not enough quantity");
        ITreasureMarketplace(proxy).buyItems(buyItems);
        vm.stopPrank();
    }

    function test_ERC1155_ListingAndBuying() public {
        uint256 tokenId = 0;
        uint64 quantity = 5;
        uint64 buyQuantity = 3;

        _mintAndApproveERC1155(seller, tokenId, quantity);

        // Try listing before approval
        vm.startPrank(seller);
        vm.expectRevert("TreasureMarketplace: token is not approved for trading");
        ITreasureMarketplace(proxy).createListing(
            address(erc1155), tokenId, quantity, pricePerItem, expirationTime, address(magicToken)
        );
        vm.stopPrank();

        _approveMarketplaceERC1155();

        // Create listing
        vm.startPrank(seller);
        ITreasureMarketplace(proxy).createListing(
            address(erc1155), tokenId, quantity, pricePerItem, expirationTime, address(magicToken)
        );
        vm.stopPrank();

        // Verify listing
        _verifyListing(address(erc1155), tokenId, seller, quantity, pricePerItem, expirationTime, address(magicToken));

        // Buy partial quantity
        _setupBuyerWithFunds(pricePerItem * buyQuantity);

        vm.startPrank(buyer);
        ITreasureMarketplace.BuyItemParams[] memory buyItems =
            _createERC1155BuyItemParams(tokenId, seller, buyQuantity, pricePerItem, address(magicToken));
        ITreasureMarketplace(proxy).buyItems(buyItems);
        vm.stopPrank();

        // Verify partial purchase
        assertEq(erc1155.balanceOf(buyer, tokenId), buyQuantity);
        assertEq(erc1155.balanceOf(seller, tokenId), quantity - buyQuantity);
        assertEq(magicToken.balanceOf(buyer), 0);
        assertEq(magicToken.balanceOf(seller), pricePerItem * buyQuantity * 99 / 100);
        assertEq(magicToken.balanceOf(feeRecipient), pricePerItem * buyQuantity * 1 / 100);

        // Verify listing was updated
        _verifyListing(
            address(erc1155), tokenId, seller, quantity - buyQuantity, pricePerItem, expirationTime, address(magicToken)
        );

        // Buy remaining quantity
        _setupBuyerWithFunds(pricePerItem * (quantity - buyQuantity));

        vm.startPrank(buyer);
        buyItems =
            _createERC1155BuyItemParams(tokenId, seller, quantity - buyQuantity, pricePerItem, address(magicToken));
        ITreasureMarketplace(proxy).buyItems(buyItems);
        vm.stopPrank();

        // Verify complete purchase
        assertEq(erc1155.balanceOf(buyer, tokenId), quantity);
        assertEq(erc1155.balanceOf(seller, tokenId), 0);
        assertEq(magicToken.balanceOf(buyer), 0);
        assertEq(magicToken.balanceOf(seller), pricePerItem * quantity * 99 / 100);
        assertEq(magicToken.balanceOf(feeRecipient), pricePerItem * quantity * 1 / 100);

        // Verify listing was removed
        _verifyListingRemoved(address(erc1155), tokenId, seller);
    }

    function test_ERC1155_ListingAndBuyingWithCollectionFee() public {
        uint256 tokenId = 0;
        uint64 quantity = 5;
        uint64 buyQuantity = 3;

        _mintAndApproveERC1155(seller, tokenId, quantity);
        _approveMarketplaceERC1155();

        // Set collection fee
        vm.startPrank(marketplaceDeployer);
        ITreasureMarketplace.CollectionOwnerFee memory collectionFee =
            ITreasureMarketplace.CollectionOwnerFee({recipient: staker, fee: 500}); // 5%
        ITreasureMarketplace(proxy).setCollectionOwnerFee(address(erc1155), collectionFee);
        vm.stopPrank();

        // Create listing
        vm.startPrank(seller);
        ITreasureMarketplace(proxy).createListing(
            address(erc1155), tokenId, quantity, pricePerItem, expirationTime, address(magicToken)
        );
        vm.stopPrank();

        // Setup buyer and buy items
        _setupBuyerWithFunds(pricePerItem * buyQuantity);

        vm.startPrank(buyer);
        ITreasureMarketplace.BuyItemParams[] memory buyItems =
            _createERC1155BuyItemParams(tokenId, seller, buyQuantity, pricePerItem, address(magicToken));
        ITreasureMarketplace(proxy).buyItems(buyItems);
        vm.stopPrank();

        // Verify ownership transfer
        assertEq(erc1155.balanceOf(buyer, tokenId), buyQuantity);
        assertEq(erc1155.balanceOf(seller, tokenId), quantity - buyQuantity);

        // Calculate and verify fee distribution
        uint256 totalPrice = pricePerItem * buyQuantity;
        uint256 protocolFee = totalPrice * 1 / 100;
        uint256 collectionFeeAmount = totalPrice * 5 / 100;
        uint256 sellerAmount = totalPrice - protocolFee - collectionFeeAmount;

        assertEq(magicToken.balanceOf(buyer), 0);
        assertEq(magicToken.balanceOf(seller), sellerAmount);
        assertEq(magicToken.balanceOf(feeRecipient), protocolFee);
        assertEq(magicToken.balanceOf(staker), collectionFeeAmount);

        // Verify listing was updated
        _verifyListing(
            address(erc1155), tokenId, seller, quantity - buyQuantity, pricePerItem, expirationTime, address(magicToken)
        );
    }

    function test_ERC1155_BuyingWithWrongPaymentToken() public {
        uint256 tokenId = 0;
        uint64 quantity = 5;
        uint64 buyQuantity = 3;

        _mintAndApproveERC1155(seller, tokenId, quantity);
        _approveMarketplaceERC1155();

        vm.startPrank(seller);
        ITreasureMarketplace(proxy).createListing(
            address(erc1155), tokenId, quantity, pricePerItem, expirationTime, address(magicToken)
        );
        vm.stopPrank();

        // Try buying with wrong payment token
        ERC20Mintable wrongToken = new ERC20Mintable();
        vm.startPrank(buyer);
        wrongToken.mint(buyer, pricePerItem * buyQuantity);
        wrongToken.approve(proxy, pricePerItem * buyQuantity);

        ITreasureMarketplace.BuyItemParams[] memory buyItems =
            _createERC1155BuyItemParams(tokenId, seller, buyQuantity, pricePerItem, address(wrongToken));
        vm.expectRevert("TreasureMarketplace: Wrong payment token");
        ITreasureMarketplace(proxy).buyItems(buyItems);
        vm.stopPrank();
    }

    function test_ERC1155_BuyingWithWrongPrice() public {
        uint256 tokenId = 0;
        uint64 quantity = 5;
        uint64 buyQuantity = 3;

        _mintAndApproveERC1155(seller, tokenId, quantity);
        _approveMarketplaceERC1155();

        vm.startPrank(seller);
        ITreasureMarketplace(proxy).createListing(
            address(erc1155), tokenId, quantity, pricePerItem, expirationTime, address(magicToken)
        );
        vm.stopPrank();

        // Try buying with lower price
        _setupBuyerWithFunds(pricePerItem * buyQuantity);

        vm.startPrank(buyer);
        ITreasureMarketplace.BuyItemParams[] memory buyItems =
            _createERC1155BuyItemParams(tokenId, seller, buyQuantity, pricePerItem - 1, address(magicToken));
        vm.expectRevert("TreasureMarketplace: price increased");
        ITreasureMarketplace(proxy).buyItems(buyItems);
        vm.stopPrank();
    }

    function test_ERC1155_BuyingExpiredListing() public {
        uint256 tokenId = 0;
        uint64 quantity = 5;
        uint64 buyQuantity = 3;

        _mintAndApproveERC1155(seller, tokenId, quantity);
        _approveMarketplaceERC1155();

        vm.startPrank(seller);
        ITreasureMarketplace(proxy).createListing(
            address(erc1155),
            tokenId,
            quantity,
            pricePerItem,
            uint64(block.timestamp + 1 hours), // Short expiration time
            address(magicToken)
        );
        vm.stopPrank();

        // Advance time past expiration
        vm.warp(block.timestamp + 2 hours);

        // Try buying expired listing
        _setupBuyerWithFunds(pricePerItem * buyQuantity);

        vm.startPrank(buyer);
        ITreasureMarketplace.BuyItemParams[] memory buyItems =
            _createERC1155BuyItemParams(tokenId, seller, buyQuantity, pricePerItem, address(magicToken));
        vm.expectRevert("TreasureMarketplace: listing expired");
        ITreasureMarketplace(proxy).buyItems(buyItems);
        vm.stopPrank();
    }

    function test_ERC1155_CreateOrUpdateListings() public {
        uint64 quantity = 5;

        // Setup test NFTs
        vm.startPrank(nftDeployer);
        for (uint256 i = 0; i < 5; i++) {
            erc1155.mint(seller, i, quantity);
        }
        vm.stopPrank();

        vm.startPrank(seller);
        erc1155.setApprovalForAll(proxy, true);
        vm.stopPrank();

        // Try listing before collection is approved
        ITreasureMarketplace.CreateOrUpdateListingParams[] memory params =
            new ITreasureMarketplace.CreateOrUpdateListingParams[](1);
        params[0] = ITreasureMarketplace.CreateOrUpdateListingParams({
            nftAddress: address(erc1155),
            tokenId: 0,
            quantity: quantity,
            pricePerItem: pricePerItem,
            expirationTime: expirationTime,
            paymentToken: address(magicToken)
        });

        vm.prank(seller);
        vm.expectRevert("TreasureMarketplace: token is not approved for trading");
        ITreasureMarketplace(proxy).createOrUpdateListings(params);

        _approveMarketplaceERC1155();

        // Create valid listings
        ITreasureMarketplace.CreateOrUpdateListingParams[] memory validParams =
            new ITreasureMarketplace.CreateOrUpdateListingParams[](3);
        for (uint256 i = 0; i < 3; i++) {
            validParams[i] = ITreasureMarketplace.CreateOrUpdateListingParams({
                nftAddress: address(erc1155),
                tokenId: i,
                quantity: quantity,
                pricePerItem: pricePerItem,
                expirationTime: expirationTime,
                paymentToken: address(magicToken)
            });
        }

        vm.prank(seller);
        ITreasureMarketplace(proxy).createOrUpdateListings(validParams);

        // Verify listings were created
        for (uint256 i = 0; i < 3; i++) {
            _verifyListing(address(erc1155), i, seller, quantity, pricePerItem, expirationTime, address(magicToken));
        }

        // Update listings
        uint64 newQuantity = quantity + 2;
        vm.startPrank(nftDeployer);
        for (uint256 i = 0; i < 3; i++) {
            erc1155.mint(seller, i, 2); // Additional tokens for increased quantity
        }
        vm.stopPrank();

        ITreasureMarketplace.CreateOrUpdateListingParams[] memory updateParams =
            new ITreasureMarketplace.CreateOrUpdateListingParams[](3);
        for (uint256 i = 0; i < 3; i++) {
            updateParams[i] = ITreasureMarketplace.CreateOrUpdateListingParams({
                nftAddress: address(erc1155),
                tokenId: i,
                quantity: newQuantity,
                pricePerItem: pricePerItem + 100,
                expirationTime: expirationTime + 100,
                paymentToken: address(magicToken)
            });
        }

        vm.prank(seller);
        ITreasureMarketplace(proxy).createOrUpdateListings(updateParams);

        // Verify updates
        for (uint256 i = 0; i < 3; i++) {
            _verifyListing(
                address(erc1155), i, seller, newQuantity, pricePerItem + 100, expirationTime + 100, address(magicToken)
            );
        }
    }

    function test_ERC1155_CreateListingWithMintedNFT() public {
        uint256 tokenId = 0;
        uint64 quantity = 5;

        // Setup test NFT
        _mintAndApproveERC1155(seller, tokenId, quantity);

        // Try listing before approval
        vm.startPrank(seller);
        vm.expectRevert("TreasureMarketplace: token is not approved for trading");
        ITreasureMarketplace(proxy).createListing(
            address(erc1155), tokenId, quantity, pricePerItem, expirationTime, address(magicToken)
        );
        vm.stopPrank();

        _approveMarketplaceERC1155();

        // Try listing without NFT approval
        vm.startPrank(seller);
        erc1155.setApprovalForAll(proxy, false); // Remove approval
        vm.expectRevert("TreasureMarketplace: item not approved");
        ITreasureMarketplace(proxy).createListing(
            address(erc1155), tokenId, quantity, pricePerItem, expirationTime, address(magicToken)
        );

        // Approve NFT and create listing
        erc1155.setApprovalForAll(proxy, true);
        ITreasureMarketplace(proxy).createListing(
            address(erc1155), tokenId, quantity, pricePerItem, expirationTime, address(magicToken)
        );
        vm.stopPrank();

        // Verify listing
        _verifyListing(address(erc1155), tokenId, seller, quantity, pricePerItem, expirationTime, address(magicToken));

        // Try creating duplicate listing
        vm.prank(seller);
        vm.expectRevert("TreasureMarketplace: already listed");
        ITreasureMarketplace(proxy).createListing(
            address(erc1155), tokenId, quantity, pricePerItem, expirationTime, address(magicToken)
        );
    }

    function test_ERC1155_UpdateListing() public {
        uint256 tokenId = 0;
        uint64 quantity = 5;

        // Setup test NFT and create initial listing
        _mintAndApproveERC1155(seller, tokenId, quantity);
        _approveMarketplaceERC1155();

        vm.startPrank(seller);
        ITreasureMarketplace(proxy).createListing(
            address(erc1155), tokenId, quantity, pricePerItem, expirationTime, address(magicToken)
        );
        vm.stopPrank();

        // Try updating non-existent listing
        vm.startPrank(buyer);
        vm.expectRevert("TreasureMarketplace: not listed item");
        ITreasureMarketplace(proxy).updateListing(
            address(erc1155), 1, quantity, pricePerItem, expirationTime, address(magicToken)
        );
        vm.stopPrank();

        // Try updating with invalid expiration
        vm.startPrank(seller);
        vm.expectRevert("TreasureMarketplace: invalid expiration time");
        ITreasureMarketplace(proxy).updateListing(
            address(erc1155), tokenId, quantity, pricePerItem, uint64(block.timestamp - 1), address(magicToken)
        );

        // Try updating with invalid price
        vm.expectRevert("TreasureMarketplace: below min price");
        ITreasureMarketplace(proxy).updateListing(
            address(erc1155), tokenId, quantity, 0, expirationTime, address(magicToken)
        );

        // Try updating with wrong payment token
        vm.expectRevert("TreasureMarketplace: Wrong payment token");
        ITreasureMarketplace(proxy).updateListing(
            address(erc1155), tokenId, quantity, pricePerItem, expirationTime, address(0x123)
        );
        vm.stopPrank();

        // Update listing successfully
        uint128 newPrice = pricePerItem + 0.5 ether;
        uint64 newExpiry = uint64(expirationTime + 1 days);
        uint64 newQuantity = quantity + 2;

        // Mint additional tokens for increased quantity
        vm.prank(nftDeployer);
        erc1155.mint(seller, tokenId, 2);

        vm.prank(seller);
        ITreasureMarketplace(proxy).updateListing(
            address(erc1155), tokenId, newQuantity, newPrice, newExpiry, address(magicToken)
        );

        // Verify listing was updated
        _verifyListing(address(erc1155), tokenId, seller, newQuantity, newPrice, newExpiry, address(magicToken));
    }

    function test_ERC1155_CancelListing() public {
        uint256 tokenId = 0;
        uint64 quantity = 5;

        // Setup test NFT and create initial listing
        _mintAndApproveERC1155(seller, tokenId, quantity);
        _approveMarketplaceERC1155();

        vm.startPrank(seller);
        ITreasureMarketplace(proxy).createListing(
            address(erc1155), tokenId, quantity, pricePerItem, expirationTime, address(magicToken)
        );
        vm.stopPrank();

        // Verify listing exists
        _verifyListing(address(erc1155), tokenId, seller, quantity, pricePerItem, expirationTime, address(magicToken));

        // Cancel listing
        vm.prank(seller);
        ITreasureMarketplace(proxy).cancelListing(address(erc1155), tokenId);

        // Verify listing was cancelled
        _verifyListingRemoved(address(erc1155), tokenId, seller);

        // Try canceling non-existent listing (should not revert)
        vm.prank(seller);
        ITreasureMarketplace(proxy).cancelListing(address(erc1155), 999);
    }

    function test_ERC1155_BuyItem() public {
        uint256 tokenId = 0;
        uint64 quantity = 5;
        uint64 buyQuantity = 3;

        // Setup test NFT and create initial listing
        vm.startPrank(nftDeployer);
        erc1155.mint(seller, tokenId, quantity);
        vm.stopPrank();

        vm.prank(marketplaceDeployer);
        ITreasureMarketplace(proxy).setTokenApprovalStatus(
            address(erc1155), ITreasureMarketplace.TokenApprovalStatus.ERC_1155_APPROVED, address(magicToken)
        );

        vm.startPrank(seller);
        erc1155.setApprovalForAll(proxy, true);
        ITreasureMarketplace(proxy).createListing(
            address(erc1155), tokenId, quantity, pricePerItem, expirationTime, address(magicToken)
        );
        vm.stopPrank();

        // Try buying own listing
        vm.startPrank(seller);
        magicToken.approve(proxy, pricePerItem * buyQuantity);
        vm.stopPrank();

        ITreasureMarketplace.BuyItemParams[] memory buyItems = new ITreasureMarketplace.BuyItemParams[](1);
        buyItems[0] = ITreasureMarketplace.BuyItemParams({
            nftAddress: address(erc1155),
            tokenId: tokenId,
            owner: seller,
            quantity: buyQuantity,
            maxPricePerItem: pricePerItem,
            paymentToken: address(magicToken),
            usingMagic: false
        });

        vm.prank(seller);
        vm.expectRevert("TreasureMarketplace: Cannot buy your own item");
        ITreasureMarketplace(proxy).buyItems(buyItems);

        // Setup buyer and buy item
        vm.startPrank(buyer);
        magicToken.mint(buyer, pricePerItem * buyQuantity);
        magicToken.approve(proxy, pricePerItem * buyQuantity);

        ITreasureMarketplace(proxy).buyItems(buyItems);
        vm.stopPrank();

        // Verify ownership and payments
        assertEq(erc1155.balanceOf(buyer, tokenId), buyQuantity);
        assertEq(erc1155.balanceOf(seller, tokenId), quantity - buyQuantity);
        assertEq(magicToken.balanceOf(buyer), 0);
        assertEq(magicToken.balanceOf(seller), pricePerItem * buyQuantity * 99 / 100); // 99% (1% protocol fee)
        assertEq(magicToken.balanceOf(feeRecipient), pricePerItem * buyQuantity * 1 / 100); // 1% protocol fee

        // Verify listing was updated
        (uint64 listedQuantity, uint128 price, uint64 expiry, address token) =
            ITreasureMarketplace(proxy).listings(address(erc1155), tokenId, seller);
        assertEq(listedQuantity, quantity - buyQuantity);
        assertEq(price, pricePerItem);
        assertEq(expiry, expirationTime);
        assertEq(token, address(magicToken));

        // Try buying more than available
        vm.startPrank(buyer);
        magicToken.mint(buyer, pricePerItem * quantity);
        magicToken.approve(proxy, pricePerItem * quantity);
        buyItems[0].quantity = quantity;
        vm.expectRevert("TreasureMarketplace: not enough quantity");
        ITreasureMarketplace(proxy).buyItems(buyItems);
        vm.stopPrank();
    }
}
