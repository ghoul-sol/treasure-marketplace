// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import {Test} from "forge-std/Test.sol";
import {TreasureMarketplaceTest} from "./TreasureMarketplaceTest.sol";
import {TreasureMarketplace} from "../contracts/TreasureMarketplace.sol";
import {ITreasureMarketplace} from "../contracts/interfaces/ITreasureMarketplace.sol";
import {ERC721Mintable} from "./mocks/ERC721Mintable.sol";
import {ERC20Mintable} from "./mocks/ERC20Mintable.sol";
import {ERC1967Proxy} from "@openzeppelin/contracts/proxy/ERC1967/ERC1967Proxy.sol";
import {IAccessControl} from "@openzeppelin/contracts/access/IAccessControl.sol";
import {Pausable} from "@openzeppelin/contracts/utils/Pausable.sol";

contract TreasureMarketplaceERC721Test is TreasureMarketplaceTest {
    function test_ERC721_BuyingWithQuantityZero() public {
        _approveMarketplaceERC721();
        uint256 tokenId = 0;
        _mintAndApproveERC721(seller);

        // Create listing
        vm.prank(seller);
        ITreasureMarketplace(proxy).createListing(
            address(nft), tokenId, 1, pricePerItem, expirationTime, address(magicToken)
        );

        _setupBuyerWithFunds(pricePerItem);

        // Try buying with quantity 0
        vm.startPrank(buyer);
        ITreasureMarketplace.BuyItemParams[] memory buyItems = new ITreasureMarketplace.BuyItemParams[](1);
        buyItems[0] = ITreasureMarketplace.BuyItemParams({
            nftAddress: address(nft),
            tokenId: tokenId,
            owner: seller,
            quantity: 0,
            maxPricePerItem: pricePerItem,
            paymentToken: address(magicToken),
            usingMagic: false
        });
        vm.expectRevert("TreasureMarketplace: Nothing to buy");
        ITreasureMarketplace(proxy).buyItems(buyItems);
        vm.stopPrank();
    }

    function test_ERC721_BuyingWithQuantityTooHigh() public {
        _approveMarketplaceERC721();
        uint256 tokenId = 0;
        _mintAndApproveERC721(seller);

        // Create listing
        vm.prank(seller);
        ITreasureMarketplace(proxy).createListing(
            address(nft), tokenId, 1, pricePerItem, expirationTime, address(magicToken)
        );

        _setupBuyerWithFunds(pricePerItem * 2);

        // Try buying with quantity > 1
        vm.startPrank(buyer);
        ITreasureMarketplace.BuyItemParams[] memory buyItems = new ITreasureMarketplace.BuyItemParams[](1);
        buyItems[0] = ITreasureMarketplace.BuyItemParams({
            nftAddress: address(nft),
            tokenId: tokenId,
            owner: seller,
            quantity: 2,
            maxPricePerItem: pricePerItem,
            paymentToken: address(magicToken),
            usingMagic: false
        });
        vm.expectRevert("TreasureMarketplace: not enough quantity");
        ITreasureMarketplace(proxy).buyItems(buyItems);
        vm.stopPrank();
    }

    function test_ERC721_ListingAndBuying() public {
        uint256 tokenId = 0;

        // Mint and approve
        vm.startPrank(nftDeployer);
        nft.mint(seller);
        vm.stopPrank();

        vm.startPrank(seller);
        nft.setApprovalForAll(proxy, true);
        vm.stopPrank();

        // Approve collection in marketplace
        vm.prank(marketplaceDeployer);
        ITreasureMarketplace(proxy).setTokenApprovalStatus(
            address(nft), ITreasureMarketplace.TokenApprovalStatus.ERC_721_APPROVED, address(magicToken)
        );

        // Create listing
        vm.prank(seller);
        ITreasureMarketplace(proxy).createListing(
            address(nft), tokenId, 1, pricePerItem, expirationTime, address(magicToken)
        );

        // Verify listing
        _verifyListing(address(nft), tokenId, seller, 1, pricePerItem, expirationTime, address(magicToken));

        // Setup buyer
        vm.startPrank(buyer);
        magicToken.mint(buyer, pricePerItem);
        magicToken.approve(proxy, pricePerItem);

        // Buy item
        ITreasureMarketplace.BuyItemParams[] memory buyItems = new ITreasureMarketplace.BuyItemParams[](1);
        buyItems[0] = ITreasureMarketplace.BuyItemParams({
            nftAddress: address(nft),
            tokenId: tokenId,
            owner: seller,
            quantity: 1,
            maxPricePerItem: pricePerItem,
            paymentToken: address(magicToken),
            usingMagic: false
        });
        ITreasureMarketplace(proxy).buyItems(buyItems);
        vm.stopPrank();

        assertEq(nft.ownerOf(tokenId), buyer);
        assertEq(magicToken.balanceOf(buyer), 0);
        assertEq(magicToken.balanceOf(seller), pricePerItem * 99 / 100); // 99% (1% protocol fee)
        assertEq(magicToken.balanceOf(feeRecipient), pricePerItem * 1 / 100); // 1% protocol fee

        // Verify listing is removed
        _verifyListingRemoved(address(nft), tokenId, seller);
    }

    function test_ERC721_ListingAndBuyingWithCollectionFee() public {
        _approveMarketplaceERC721();
        uint256 tokenId = 0;
        _mintAndApproveERC721(seller);

        // Set collection fee (5%)
        ITreasureMarketplace.CollectionOwnerFee memory collectionFee =
            ITreasureMarketplace.CollectionOwnerFee({recipient: staker, fee: 500});
        vm.prank(marketplaceDeployer);
        ITreasureMarketplace(proxy).setCollectionOwnerFee(address(nft), collectionFee);

        // Create listing
        vm.prank(seller);
        ITreasureMarketplace(proxy).createListing(
            address(nft), tokenId, 1, pricePerItem, expirationTime, address(magicToken)
        );

        // Setup buyer with funds
        _setupBuyerWithFunds(pricePerItem);

        // Buy item
        vm.startPrank(buyer);
        ITreasureMarketplace.BuyItemParams[] memory buyItems = new ITreasureMarketplace.BuyItemParams[](1);
        buyItems[0] = ITreasureMarketplace.BuyItemParams({
            nftAddress: address(nft),
            tokenId: tokenId,
            owner: seller,
            quantity: 1,
            maxPricePerItem: pricePerItem,
            paymentToken: address(magicToken),
            usingMagic: false
        });
        ITreasureMarketplace(proxy).buyItems(buyItems);
        vm.stopPrank();

        // Calculate fees
        uint256 protocolFee = pricePerItem * 1 / 100; // 1% protocol fee
        uint256 collectionFeeAmount = pricePerItem * 5 / 100; // 5% collection fee
        uint256 sellerAmount = pricePerItem - protocolFee - collectionFeeAmount; // 94%

        // Verify ownership and payments
        assertEq(nft.ownerOf(tokenId), buyer);
        assertEq(magicToken.balanceOf(buyer), 0);
        assertEq(magicToken.balanceOf(seller), sellerAmount);
        assertEq(magicToken.balanceOf(feeRecipient), protocolFee);
        assertEq(magicToken.balanceOf(staker), collectionFeeAmount);

        // Verify listing is removed
        _verifyListingRemoved(address(nft), tokenId, seller);
    }

    function test_ERC721_BuyingWithWrongPrice() public {
        _approveMarketplaceERC721();
        uint256 tokenId = 0;
        _mintAndApproveERC721(seller);

        // Create listing
        vm.prank(seller);
        ITreasureMarketplace(proxy).createListing(
            address(nft), tokenId, 1, pricePerItem, expirationTime, address(magicToken)
        );

        // Try buying with lower price
        _setupBuyerWithFunds(pricePerItem);
        vm.startPrank(buyer);
        ITreasureMarketplace.BuyItemParams[] memory buyItems = new ITreasureMarketplace.BuyItemParams[](1);
        buyItems[0] = ITreasureMarketplace.BuyItemParams({
            nftAddress: address(nft),
            tokenId: tokenId,
            owner: seller,
            quantity: 1,
            maxPricePerItem: pricePerItem - 1,
            paymentToken: address(magicToken),
            usingMagic: false
        });
        vm.expectRevert("TreasureMarketplace: price increased");
        ITreasureMarketplace(proxy).buyItems(buyItems);
        vm.stopPrank();
    }

    function test_ERC721_BuyingExpiredListing() public {
        _approveMarketplaceERC721();
        uint256 tokenId = 0;
        _mintAndApproveERC721(seller);

        // Create listing with short expiration
        vm.prank(seller);
        ITreasureMarketplace(proxy).createListing(
            address(nft), tokenId, 1, pricePerItem, uint64(block.timestamp + 1 hours), address(magicToken)
        );

        // Advance time past expiration
        vm.warp(block.timestamp + 2 hours);

        // Try buying expired listing
        _setupBuyerWithFunds(pricePerItem);
        vm.startPrank(buyer);
        ITreasureMarketplace.BuyItemParams[] memory buyItems = new ITreasureMarketplace.BuyItemParams[](1);
        buyItems[0] = ITreasureMarketplace.BuyItemParams({
            nftAddress: address(nft),
            tokenId: tokenId,
            owner: seller,
            quantity: 1,
            maxPricePerItem: pricePerItem,
            paymentToken: address(magicToken),
            usingMagic: false
        });
        vm.expectRevert("TreasureMarketplace: listing expired");
        ITreasureMarketplace(proxy).buyItems(buyItems);
        vm.stopPrank();
    }

    function test_ERC721_CreateOrUpdateListings() public {
        // Setup test NFTs
        vm.startPrank(nftDeployer);
        for (uint256 i = 0; i < 5; i++) {
            nft.mint(seller);
        }
        vm.stopPrank();

        vm.startPrank(seller);
        nft.setApprovalForAll(proxy, true);
        vm.stopPrank();

        // Try listing before collection is approved
        ITreasureMarketplace.CreateOrUpdateListingParams[] memory params =
            new ITreasureMarketplace.CreateOrUpdateListingParams[](1);
        params[0] = ITreasureMarketplace.CreateOrUpdateListingParams({
            nftAddress: address(nft),
            tokenId: 0,
            quantity: 1,
            pricePerItem: pricePerItem,
            expirationTime: expirationTime,
            paymentToken: address(magicToken)
        });

        vm.prank(seller);
        vm.expectRevert("TreasureMarketplace: token is not approved for trading");
        ITreasureMarketplace(proxy).createOrUpdateListings(params);

        // Approve collection
        vm.prank(marketplaceDeployer);
        ITreasureMarketplace(proxy).setTokenApprovalStatus(
            address(nft), ITreasureMarketplace.TokenApprovalStatus.ERC_721_APPROVED, address(magicToken)
        );

        // Try listing with invalid price
        params[0].pricePerItem = 0;
        vm.prank(seller);
        vm.expectRevert("TreasureMarketplace: below min price");
        ITreasureMarketplace(proxy).createOrUpdateListings(params);

        // Try listing with invalid quantity
        params[0].pricePerItem = pricePerItem;
        params[0].quantity = 0;
        vm.prank(seller);
        vm.expectRevert("TreasureMarketplace: cannot list multiple ERC721");
        ITreasureMarketplace(proxy).createOrUpdateListings(params);

        // Try listing with expired time
        params[0].quantity = 1;
        params[0].expirationTime = uint64(block.timestamp - 1);
        vm.prank(seller);
        vm.expectRevert("TreasureMarketplace: invalid expiration time");
        ITreasureMarketplace(proxy).createOrUpdateListings(params);

        // Try listing as non-owner
        params[0].expirationTime = expirationTime;
        vm.prank(buyer);
        vm.expectRevert("TreasureMarketplace: not owning item");
        ITreasureMarketplace(proxy).createOrUpdateListings(params);

        // Try listing when paused
        vm.prank(marketplaceDeployer);
        ITreasureMarketplace(proxy).pause();

        vm.prank(seller);
        vm.expectRevert(abi.encodeWithSelector(Pausable.EnforcedPause.selector));
        ITreasureMarketplace(proxy).createOrUpdateListings(params);

        vm.prank(marketplaceDeployer);
        ITreasureMarketplace(proxy).unpause();

        // Try listing with wrong payment token
        params[0].paymentToken = address(0x123);
        vm.prank(seller);
        vm.expectRevert("TreasureMarketplace: Wrong payment token");
        ITreasureMarketplace(proxy).createOrUpdateListings(params);

        // Create valid listings
        ITreasureMarketplace.CreateOrUpdateListingParams[] memory validParams =
            new ITreasureMarketplace.CreateOrUpdateListingParams[](3);
        for (uint256 i = 0; i < 3; i++) {
            validParams[i] = ITreasureMarketplace.CreateOrUpdateListingParams({
                nftAddress: address(nft),
                tokenId: i,
                quantity: 1,
                pricePerItem: pricePerItem,
                expirationTime: expirationTime,
                paymentToken: address(magicToken)
            });
        }

        vm.prank(seller);
        ITreasureMarketplace(proxy).createOrUpdateListings(validParams);

        // Verify listings were created
        for (uint256 i = 0; i < 3; i++) {
            _verifyListing(address(nft), i, seller, 1, pricePerItem, expirationTime, address(magicToken));
        }

        // Update listings
        ITreasureMarketplace.CreateOrUpdateListingParams[] memory updateParams =
            new ITreasureMarketplace.CreateOrUpdateListingParams[](3);
        for (uint256 i = 0; i < 3; i++) {
            updateParams[i] = ITreasureMarketplace.CreateOrUpdateListingParams({
                nftAddress: address(nft),
                tokenId: i,
                quantity: 1,
                pricePerItem: pricePerItem + 100,
                expirationTime: expirationTime + 100,
                paymentToken: address(magicToken)
            });
        }

        vm.prank(seller);
        ITreasureMarketplace(proxy).createOrUpdateListings(updateParams);

        // Verify updates
        for (uint256 i = 0; i < 3; i++) {
            _verifyListing(address(nft), i, seller, 1, pricePerItem + 100, expirationTime + 100, address(magicToken));
        }

        // Create new listing while updating existing ones
        ITreasureMarketplace.CreateOrUpdateListingParams[] memory mixedParams =
            new ITreasureMarketplace.CreateOrUpdateListingParams[](2);
        mixedParams[0] = ITreasureMarketplace.CreateOrUpdateListingParams({
            nftAddress: address(nft),
            tokenId: 4, // New listing
            quantity: 1,
            pricePerItem: pricePerItem,
            expirationTime: expirationTime,
            paymentToken: address(magicToken)
        });
        mixedParams[1] = updateParams[0]; // Update existing

        vm.prank(seller);
        ITreasureMarketplace(proxy).createOrUpdateListings(mixedParams);

        // Verify mixed operation
        _verifyListing(address(nft), 4, seller, 1, pricePerItem, expirationTime, address(magicToken));
    }

    function test_ERC721_CreateListingWithMintedNFT() public {
        // Setup test NFT
        vm.startPrank(nftDeployer);
        nft.mint(seller);
        vm.stopPrank();

        // Try listing before approval
        vm.startPrank(seller);
        vm.expectRevert("TreasureMarketplace: token is not approved for trading");
        ITreasureMarketplace(proxy).createListing(address(nft), 0, 1, pricePerItem, expirationTime, address(magicToken));
        vm.stopPrank();

        // Approve collection
        vm.prank(marketplaceDeployer);
        ITreasureMarketplace(proxy).setTokenApprovalStatus(
            address(nft), ITreasureMarketplace.TokenApprovalStatus.ERC_721_APPROVED, address(magicToken)
        );

        // Try listing without NFT approval
        vm.startPrank(seller);
        vm.expectRevert("TreasureMarketplace: item not approved");
        ITreasureMarketplace(proxy).createListing(address(nft), 0, 1, pricePerItem, expirationTime, address(magicToken));

        // Approve NFT and create listing
        nft.setApprovalForAll(proxy, true);
        ITreasureMarketplace(proxy).createListing(address(nft), 0, 1, pricePerItem, expirationTime, address(magicToken));
        vm.stopPrank();

        // Verify listing
        _verifyListing(address(nft), 0, seller, 1, pricePerItem, expirationTime, address(magicToken));

        // Try creating duplicate listing
        vm.prank(seller);
        vm.expectRevert("TreasureMarketplace: already listed");
        ITreasureMarketplace(proxy).createListing(address(nft), 0, 1, pricePerItem, expirationTime, address(magicToken));
    }

    function test_ERC721_UpdateListing() public {
        // Setup test NFT and create initial listing
        vm.startPrank(nftDeployer);
        nft.mint(seller);
        vm.stopPrank();

        vm.prank(marketplaceDeployer);
        ITreasureMarketplace(proxy).setTokenApprovalStatus(
            address(nft), ITreasureMarketplace.TokenApprovalStatus.ERC_721_APPROVED, address(magicToken)
        );

        vm.startPrank(seller);
        nft.setApprovalForAll(proxy, true);
        ITreasureMarketplace(proxy).createListing(address(nft), 0, 1, pricePerItem, expirationTime, address(magicToken));
        vm.stopPrank();

        // Try updating non-existent listing
        vm.startPrank(buyer);
        vm.expectRevert("TreasureMarketplace: not listed item");
        ITreasureMarketplace(proxy).updateListing(address(nft), 1, 1, pricePerItem, expirationTime, address(magicToken));
        vm.stopPrank();

        // Try updating with invalid expiration
        vm.startPrank(seller);
        vm.expectRevert("TreasureMarketplace: invalid expiration time");
        ITreasureMarketplace(proxy).updateListing(
            address(nft), 0, 1, pricePerItem, uint64(block.timestamp - 1), address(magicToken)
        );

        // Try updating with invalid price
        vm.expectRevert("TreasureMarketplace: below min price");
        ITreasureMarketplace(proxy).updateListing(address(nft), 0, 1, 0, expirationTime, address(magicToken));

        // Try updating with wrong payment token
        vm.expectRevert("TreasureMarketplace: Wrong payment token");
        ITreasureMarketplace(proxy).updateListing(address(nft), 0, 1, pricePerItem, expirationTime, address(0x123));

        // Update listing successfully
        uint128 newPrice = pricePerItem + 0.5 ether;
        uint64 newExpiry = uint64(expirationTime + 1 days);
        ITreasureMarketplace(proxy).updateListing(address(nft), 0, 1, newPrice, newExpiry, address(magicToken));
        vm.stopPrank();

        // Verify listing was updated
        _verifyListing(address(nft), 0, seller, 1, newPrice, newExpiry, address(magicToken));
    }

    function test_ERC721_CancelListing() public {
        // Setup test NFT and create initial listing
        vm.startPrank(nftDeployer);
        nft.mint(seller);
        vm.stopPrank();

        vm.prank(marketplaceDeployer);
        ITreasureMarketplace(proxy).setTokenApprovalStatus(
            address(nft), ITreasureMarketplace.TokenApprovalStatus.ERC_721_APPROVED, address(magicToken)
        );

        vm.startPrank(seller);
        nft.setApprovalForAll(proxy, true);
        ITreasureMarketplace(proxy).createListing(address(nft), 0, 1, pricePerItem, expirationTime, address(magicToken));
        vm.stopPrank();

        // Verify listing exists
        _verifyListing(address(nft), 0, seller, 1, pricePerItem, expirationTime, address(magicToken));

        // Cancel listing
        vm.prank(seller);
        ITreasureMarketplace(proxy).cancelListing(address(nft), 0);

        // Verify listing was cancelled
        _verifyListingRemoved(address(nft), 0, seller);

        // Try canceling non-existent listing (should not revert)
        vm.prank(seller);
        ITreasureMarketplace(proxy).cancelListing(address(nft), 999);
    }

    function test_ERC721_BuyItem() public {
        // Setup test NFT and create initial listing
        vm.startPrank(nftDeployer);
        nft.mint(seller);
        vm.stopPrank();

        vm.prank(marketplaceDeployer);
        ITreasureMarketplace(proxy).setTokenApprovalStatus(
            address(nft), ITreasureMarketplace.TokenApprovalStatus.ERC_721_APPROVED, address(magicToken)
        );

        vm.startPrank(seller);
        nft.setApprovalForAll(proxy, true);
        ITreasureMarketplace(proxy).createListing(address(nft), 0, 1, pricePerItem, expirationTime, address(magicToken));
        vm.stopPrank();

        // Try buying own listing
        vm.startPrank(seller);
        magicToken.approve(proxy, pricePerItem);
        vm.stopPrank();

        ITreasureMarketplace.BuyItemParams[] memory buyItems = new ITreasureMarketplace.BuyItemParams[](1);
        buyItems[0] = ITreasureMarketplace.BuyItemParams({
            nftAddress: address(nft),
            tokenId: 0,
            owner: seller,
            quantity: 1,
            maxPricePerItem: pricePerItem,
            paymentToken: address(magicToken),
            usingMagic: false
        });
        vm.prank(seller);
        vm.expectRevert("TreasureMarketplace: Cannot buy your own item");
        ITreasureMarketplace(proxy).buyItems(buyItems);

        // Setup buyer and buy item
        vm.startPrank(buyer);
        magicToken.mint(buyer, pricePerItem);
        magicToken.approve(proxy, pricePerItem);

        ITreasureMarketplace(proxy).buyItems(buyItems);
        vm.stopPrank();

        // Verify ownership and payments
        assertEq(nft.ownerOf(0), buyer);
        assertEq(magicToken.balanceOf(buyer), 0);
        assertEq(magicToken.balanceOf(seller), pricePerItem * 99 / 100); // 99% (1% protocol fee)
        assertEq(magicToken.balanceOf(feeRecipient), pricePerItem * 1 / 100); // 1% protocol fee

        // Verify listing was removed
        _verifyListingRemoved(address(nft), 0, seller);

        // Try buying non-existent listing
        vm.startPrank(buyer);
        magicToken.mint(buyer, pricePerItem);
        magicToken.approve(proxy, pricePerItem);
        vm.expectRevert("TreasureMarketplace: not listed item");
        ITreasureMarketplace(proxy).buyItems(buyItems);
        vm.stopPrank();
    }
}
