// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import {Test} from "forge-std/Test.sol";
import {TreasureMarketplace} from "../contracts/TreasureMarketplace.sol";
import {ITreasureMarketplace} from "../contracts/interfaces/ITreasureMarketplace.sol";
import {ERC721Mintable} from "./mocks/ERC721Mintable.sol";
import {ERC1155Mintable} from "./mocks/ERC1155Mintable.sol";
import {ERC20Mintable} from "./mocks/ERC20Mintable.sol";
import {ERC1967Proxy} from "@openzeppelin/contracts/proxy/ERC1967/ERC1967Proxy.sol";
import {IAccessControl} from "@openzeppelin/contracts/access/IAccessControl.sol";
import {Pausable} from "@openzeppelin/contracts/utils/Pausable.sol";

contract TreasureMarketplaceTest is Test {
    ERC1155Mintable internal erc1155;
    ERC721Mintable internal nft;
    ERC20Mintable internal magicToken;
    address internal proxy;

    address internal nftDeployer = vm.addr(1);
    address internal marketplaceDeployer = vm.addr(2);
    address internal seller = vm.addr(3);
    address internal buyer = vm.addr(4);
    address internal staker = vm.addr(5);
    address internal feeRecipient = vm.addr(6);

    uint128 internal constant pricePerItem = 1 ether;
    uint64 internal constant expirationTime = 4102462800; // Midnight Jan 1, 2100

    function setUp() public {
        // Deploy mock tokens
        vm.startPrank(nftDeployer);
        nft = new ERC721Mintable();
        erc1155 = new ERC1155Mintable();
        magicToken = new ERC20Mintable();
        vm.stopPrank();

        // Deploy implementation and proxy
        vm.startPrank(marketplaceDeployer);
        TreasureMarketplace implementation = new TreasureMarketplace();
        bytes memory initData = abi.encodeWithSelector(
            TreasureMarketplace.initialize.selector,
            100, // fee
            100, // feeWithCollectionOwner
            feeRecipient,
            address(magicToken),
            address(magicToken)
        );
        proxy = address(new ERC1967Proxy(address(implementation), initData));
        vm.stopPrank();
    }

    // Helper to setup ERC721 collection
    function _approveMarketplaceERC721() internal {
        vm.prank(marketplaceDeployer);
        ITreasureMarketplace(proxy).setTokenApprovalStatus(
            address(nft), ITreasureMarketplace.TokenApprovalStatus.ERC_721_APPROVED, address(magicToken)
        );
    }

    // Helper to mint and approve ERC721
    function _mintAndApproveERC721(address to) internal {
        vm.startPrank(nftDeployer);
        nft.mint(to);
        vm.stopPrank();

        vm.startPrank(to);
        nft.setApprovalForAll(proxy, true);
        vm.stopPrank();
    }

    // Helper to setup buyer with funds
    function _setupBuyerWithFunds(uint256 amount) internal {
        vm.startPrank(buyer);
        magicToken.mint(buyer, amount);
        magicToken.approve(proxy, amount);
        vm.stopPrank();
    }

    // Helper to verify listing state
    function _verifyListing(
        address nftAddress,
        uint256 tokenId,
        address owner,
        uint64 expectedQuantity,
        uint128 expectedPrice,
        uint64 expectedExpiry,
        address expectedToken
    ) internal view {
        (uint64 quantity, uint128 price, uint64 expiry, address token) =
            ITreasureMarketplace(proxy).listings(nftAddress, tokenId, owner);
        assertEq(quantity, expectedQuantity);
        assertEq(price, expectedPrice);
        assertEq(expiry, expectedExpiry);
        assertEq(token, expectedToken);
    }

    // Helper to verify listing is cancelled/removed
    function _verifyListingRemoved(address nftAddress, uint256 tokenId, address owner) internal view {
        _verifyListing(nftAddress, tokenId, owner, 0, 0, 0, address(0));
    }

    // Helper to setup ERC1155 collection
    function _approveMarketplaceERC1155() internal {
        vm.prank(marketplaceDeployer);
        ITreasureMarketplace(proxy).setTokenApprovalStatus(
            address(erc1155), ITreasureMarketplace.TokenApprovalStatus.ERC_1155_APPROVED, address(magicToken)
        );
    }

    // Helper to mint and approve ERC1155
    function _mintAndApproveERC1155(address to, uint256 tokenId, uint64 quantity) internal {
        vm.startPrank(nftDeployer);
        erc1155.mint(to, tokenId, quantity);
        vm.stopPrank();

        vm.startPrank(to);
        erc1155.setApprovalForAll(proxy, true);
        vm.stopPrank();
    }

    // Helper to create ERC1155 buy params
    function _createERC1155BuyItemParams(
        uint256 tokenId,
        address owner,
        uint64 quantity,
        uint128 maxPrice,
        address paymentToken
    ) internal view returns (ITreasureMarketplace.BuyItemParams[] memory) {
        ITreasureMarketplace.BuyItemParams[] memory buyItems = new ITreasureMarketplace.BuyItemParams[](1);
        buyItems[0] = ITreasureMarketplace.BuyItemParams({
            nftAddress: address(erc1155),
            tokenId: tokenId,
            owner: owner,
            quantity: quantity,
            maxPricePerItem: maxPrice,
            paymentToken: paymentToken,
            usingMagic: false
        });
        return buyItems;
    }
}
