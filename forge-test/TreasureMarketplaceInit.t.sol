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

contract TreasureMarketplaceInitTest is TreasureMarketplaceTest {
    function test_setFee() public {
        // Check initial fee
        assertEq(ITreasureMarketplace(proxy).fee(), 100);

        // Try setting fee as non-admin
        vm.prank(staker);
        vm.expectRevert(
            abi.encodeWithSelector(
                IAccessControl.AccessControlUnauthorizedAccount.selector,
                staker,
                keccak256("TREASURE_MARKETPLACE_ADMIN_ROLE")
            )
        );
        ITreasureMarketplace(proxy).setFee(1500, 750);

        // Try setting fee too high
        vm.prank(marketplaceDeployer);
        vm.expectRevert("TreasureMarketplace: max fee");
        ITreasureMarketplace(proxy).setFee(1501, 750);

        // Set fee successfully
        vm.prank(marketplaceDeployer);
        ITreasureMarketplace(proxy).setFee(1500, 750);
        assertEq(ITreasureMarketplace(proxy).fee(), 1500);
        assertEq(ITreasureMarketplace(proxy).feeWithCollectionOwner(), 750);
    }

    function test_setFeeRecipient() public {
        // Check initial fee recipient
        assertEq(ITreasureMarketplace(proxy).feeRecipient(), feeRecipient);

        // Try setting as non-admin
        vm.prank(staker);
        vm.expectRevert(
            abi.encodeWithSelector(
                IAccessControl.AccessControlUnauthorizedAccount.selector,
                staker,
                keccak256("TREASURE_MARKETPLACE_ADMIN_ROLE")
            )
        );
        ITreasureMarketplace(proxy).setFeeRecipient(seller);

        // Try setting zero address
        vm.prank(marketplaceDeployer);
        vm.expectRevert("TreasureMarketplace: cannot set 0x0 address");
        ITreasureMarketplace(proxy).setFeeRecipient(address(0));

        // Set new recipient successfully
        vm.prank(marketplaceDeployer);
        ITreasureMarketplace(proxy).setFeeRecipient(seller);
        assertEq(ITreasureMarketplace(proxy).feeRecipient(), seller);
    }

    function test_setCollectionOwnerFee() public {
        // First approve the collection
        vm.prank(marketplaceDeployer);
        ITreasureMarketplace(proxy).setTokenApprovalStatus(
            address(nft), ITreasureMarketplace.TokenApprovalStatus.ERC_721_APPROVED, address(magicToken)
        );

        ITreasureMarketplace.CollectionOwnerFee memory collectionOwnerFee =
            ITreasureMarketplace.CollectionOwnerFee({recipient: seller, fee: 500});

        // Try setting as non-admin
        vm.prank(staker);
        vm.expectRevert(
            abi.encodeWithSelector(
                IAccessControl.AccessControlUnauthorizedAccount.selector,
                staker,
                keccak256("TREASURE_MARKETPLACE_ADMIN_ROLE")
            )
        );
        ITreasureMarketplace(proxy).setCollectionOwnerFee(address(nft), collectionOwnerFee);

        // Set fee successfully
        vm.prank(marketplaceDeployer);
        ITreasureMarketplace(proxy).setCollectionOwnerFee(address(nft), collectionOwnerFee);

        // Verify fee was set
        (uint32 fee, address recipient) = ITreasureMarketplace(proxy).collectionToCollectionOwnerFee(address(nft));
        assertEq(fee, 500);
        assertEq(recipient, seller);
    }

    function test_RevertWhenPaused() public {
        // Setup basic listing/bid parameters
        uint256 tokenId = 0;
        vm.startPrank(nftDeployer);
        nft.mint(seller);
        vm.stopPrank();

        vm.startPrank(seller);
        nft.setApprovalForAll(proxy, true);
        vm.stopPrank();
        // Setup marketplace approval
        vm.startPrank(marketplaceDeployer);
        ITreasureMarketplace(proxy).setTokenApprovalStatus(
            address(nft), ITreasureMarketplace.TokenApprovalStatus.ERC_721_APPROVED, address(magicToken)
        );

        ITreasureMarketplace(proxy).pause();
        vm.stopPrank();

        // Test buyItems
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
        vm.expectRevert(abi.encodeWithSelector(Pausable.EnforcedPause.selector));
        ITreasureMarketplace(proxy).buyItems(buyItems);
        vm.stopPrank();

        // Test createListing
        vm.startPrank(seller);
        vm.expectRevert(abi.encodeWithSelector(Pausable.EnforcedPause.selector));
        ITreasureMarketplace(proxy).createListing(
            address(nft), tokenId, 1, pricePerItem, expirationTime, address(magicToken)
        );
        vm.stopPrank();

        // Test createOrUpdateListings
        vm.startPrank(seller);
        ITreasureMarketplace.CreateOrUpdateListingParams[] memory listings =
            new ITreasureMarketplace.CreateOrUpdateListingParams[](1);
        listings[0] = ITreasureMarketplace.CreateOrUpdateListingParams({
            nftAddress: address(nft),
            tokenId: tokenId,
            quantity: 1,
            pricePerItem: pricePerItem,
            expirationTime: expirationTime,
            paymentToken: address(magicToken)
        });
        vm.expectRevert(abi.encodeWithSelector(Pausable.EnforcedPause.selector));
        ITreasureMarketplace(proxy).createOrUpdateListings(listings);
        vm.stopPrank();

        // Test createOrUpdateTokenBid
        vm.startPrank(buyer);
        vm.expectRevert(abi.encodeWithSelector(Pausable.EnforcedPause.selector));
        ITreasureMarketplace(proxy).createOrUpdateTokenBid(
            address(nft), tokenId, 1, pricePerItem, expirationTime, address(magicToken)
        );
        vm.stopPrank();

        // Test createOrUpdateCollectionBid
        vm.startPrank(buyer);
        vm.expectRevert(abi.encodeWithSelector(Pausable.EnforcedPause.selector));
        ITreasureMarketplace(proxy).createOrUpdateCollectionBid(
            address(nft), 1, pricePerItem, expirationTime, address(magicToken)
        );
        vm.stopPrank();

        // Verify we can call these functions after unpausing
        vm.prank(marketplaceDeployer);
        ITreasureMarketplace(proxy).unpause();

        // Try one function to verify it works when unpaused
        vm.startPrank(seller);
        ITreasureMarketplace(proxy).createListing(
            address(nft), tokenId, 1, pricePerItem, expirationTime, address(magicToken)
        );
        vm.stopPrank();
    }
}
