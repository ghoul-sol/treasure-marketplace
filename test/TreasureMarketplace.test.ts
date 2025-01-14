import hre from 'hardhat';
import { expect } from 'chai';
import { getCurrentTime, mineBlock } from './utils';

const { ethers, artifacts, getNamedAccounts } = hre;

describe('TreasureMarketplace', () => {
    let marketplace: any;
    let weth: any;
    let magicToken: any;
    let nft: any;
    let erc1155: any;
    let seller: any;
    let buyer: any;
    let staker3: any;
    let feeRecipient: any;
    let deployer: any;
    let admin: any;
    let sellerSigner: any;
    let buyerSigner: any;
    let staker3Signer: any;
    let deployerSigner: any;

    const TOKEN_APPROVAL_STATUS_NOT_APPROVED = 0;
    const TOKEN_APPROVAL_STATUS_ERC_721_APPROVED = 1;
    const TOKEN_APPROVAL_STATUS_ERC_1155_APPROVED = 2;

    before(async () => {
        ({
            staker1: seller,
            staker2: buyer,
            staker3,
            hacker: feeRecipient,
            deployer,
            admin,
        } = await getNamedAccounts());

        sellerSigner = await ethers.provider.getSigner(seller);
        buyerSigner = await ethers.provider.getSigner(buyer);
        staker3Signer = await ethers.provider.getSigner(staker3);
        deployerSigner = await ethers.provider.getSigner(deployer);
    });

    beforeEach(async () => {
        const ERC20Mintable = await ethers.getContractFactory('ERC20Mintable');
        magicToken = await ERC20Mintable.deploy();
        await magicToken.waitForDeployment();

        const MockWETH = await ethers.getContractFactory('MockWeth');
        weth = await MockWETH.deploy();
        await weth.waitForDeployment();

        const ERC721Mintable = await ethers.getContractFactory('ERC721Mintable');
        nft = await ERC721Mintable.deploy();
        await nft.waitForDeployment();

        const ERC1155Mintable = await ethers.getContractFactory('ERC1155Mintable');
        erc1155 = await ERC1155Mintable.deploy();
        await erc1155.waitForDeployment();

        const TreasureMarketplace = await ethers.getContractFactory('TreasureMarketplace');
        const marketplaceImpl = await TreasureMarketplace.deploy();

        const TreasureMarketplaceAbi = (await artifacts.readArtifact('TreasureMarketplace')).abi;
        const iface = new ethers.Interface(TreasureMarketplaceAbi);
        const data = iface.encodeFunctionData('initialize', [100, feeRecipient, await magicToken.getAddress()]);

        const OptimizedTransparentUpgradeableProxy = await ethers.getContractFactory(
            'OptimizedTransparentUpgradeableProxy',
        );
        const proxy = await OptimizedTransparentUpgradeableProxy.deploy(
            await marketplaceImpl.getAddress(),
            admin,
            data,
        );
        await proxy.waitForDeployment();

        marketplace = new ethers.Contract(await proxy.getAddress(), TreasureMarketplaceAbi, deployerSigner);

        await (await marketplace.setWeth(await weth.getAddress())).wait();
        await (await marketplace.toggleAreBidsActive()).wait();
    });

    describe('init', () => {
        it('initialize()', async () => {
            await expect(
                marketplace.initialize(100, feeRecipient, await magicToken.getAddress()),
            ).to.be.revertedWithCustomError(marketplace, 'InvalidInitialization');
        });

        it('setFee()', async () => {
            expect(await marketplace.fee()).to.be.equal(100);
            const newFee = 1500;
            const newFeeWithCollectionOwner = 750;

            await expect(marketplace.connect(staker3Signer).setFee(newFee, newFeeWithCollectionOwner))
                .to.be.revertedWithCustomError(marketplace, 'AccessControlUnauthorizedAccount')
                .withArgs(
                    '0x90F79bf6EB2c4f870365E785982E1f101E93b906',
                    '0x34d5e892b0a7ec1561fc4a5fdcb31b798cf623590906b938d356c9619e539958',
                );

            const tooHighFee = (await marketplace.MAX_FEE()) + 1n;

            await expect(marketplace.setFee(tooHighFee, newFeeWithCollectionOwner)).to.be.revertedWith(
                'TreasureMarketplace: max fee',
            );

            await marketplace.setFee(newFee, newFeeWithCollectionOwner);
            expect(await marketplace.fee()).to.be.equal(newFee);
            expect(await marketplace.feeWithCollectionOwner()).to.be.equal(newFeeWithCollectionOwner);
        });

        it('setFeeRecipient()', async () => {
            expect(await marketplace.feeReceipient()).to.be.equal(feeRecipient);
            const newRecipient = seller;

            await expect(marketplace.connect(staker3Signer).setFeeRecipient(newRecipient))
                .to.be.revertedWithCustomError(marketplace, 'AccessControlUnauthorizedAccount')
                .withArgs(
                    '0x90F79bf6EB2c4f870365E785982E1f101E93b906',
                    '0x34d5e892b0a7ec1561fc4a5fdcb31b798cf623590906b938d356c9619e539958',
                );
            await expect(marketplace.setFeeRecipient(ethers.ZeroAddress)).to.be.revertedWith(
                'TreasureMarketplace: cannot set 0x0 address',
            );

            await marketplace.setFeeRecipient(newRecipient);
            expect(await marketplace.feeReceipient()).to.be.equal(newRecipient);
        });

        it('setCollectionOwnerFee()', async () => {
            expect(await marketplace.feeReceipient()).to.be.equal(feeRecipient);

            await (
                await marketplace.setTokenApprovalStatus(
                    await nft.getAddress(),
                    TOKEN_APPROVAL_STATUS_ERC_721_APPROVED,
                    await magicToken.getAddress(),
                )
            ).wait();

            const collectionOwnerFee = {
                recipient: seller,
                fee: 500,
            };

            await expect(
                marketplace.connect(staker3Signer).setCollectionOwnerFee(await nft.getAddress(), collectionOwnerFee),
            )
                .to.be.revertedWithCustomError(marketplace, 'AccessControlUnauthorizedAccount')
                .withArgs(
                    '0x90F79bf6EB2c4f870365E785982E1f101E93b906',
                    '0x34d5e892b0a7ec1561fc4a5fdcb31b798cf623590906b938d356c9619e539958',
                );

            await (await marketplace.setCollectionOwnerFee(await nft.getAddress(), collectionOwnerFee)).wait();

            expect((await marketplace.collectionToCollectionOwnerFee(await nft.getAddress())).recipient).to.be.equal(
                seller,
            );
            expect((await marketplace.collectionToCollectionOwnerFee(await nft.getAddress())).fee).to.be.equal(500);
        });

        it('setPriceTracker()', async () => {
            const salesTrackerAddress = staker3;

            await expect(marketplace.connect(staker3Signer).setPriceTracker(salesTrackerAddress))
                .to.be.revertedWithCustomError(marketplace, 'AccessControlUnauthorizedAccount')
                .withArgs(
                    '0x90F79bf6EB2c4f870365E785982E1f101E93b906',
                    '0x34d5e892b0a7ec1561fc4a5fdcb31b798cf623590906b938d356c9619e539958',
                );

            await expect(marketplace.setPriceTracker(salesTrackerAddress))
                .to.emit(marketplace, 'UpdateSalesTracker')
                .withArgs(salesTrackerAddress);
            expect(await marketplace.priceTrackerAddress()).to.be.equal(salesTrackerAddress);
        });

        it('approve token', async () => {
            expect(await marketplace.tokenApprovals(await nft.getAddress())).to.equal(
                TOKEN_APPROVAL_STATUS_NOT_APPROVED,
            );
            await marketplace.setTokenApprovalStatus(
                await nft.getAddress(),
                TOKEN_APPROVAL_STATUS_ERC_721_APPROVED,
                await magicToken.getAddress(),
            );
            expect(await marketplace.tokenApprovals(await nft.getAddress())).to.equal(
                TOKEN_APPROVAL_STATUS_ERC_721_APPROVED,
            );
            // Allow to approve twice
            await marketplace.setTokenApprovalStatus(
                await nft.getAddress(),
                TOKEN_APPROVAL_STATUS_ERC_721_APPROVED,
                await magicToken.getAddress(),
            );
            expect(await marketplace.tokenApprovals(await nft.getAddress())).to.equal(
                TOKEN_APPROVAL_STATUS_ERC_721_APPROVED,
            );

            await expect(
                marketplace.setTokenApprovalStatus(
                    await nft.getAddress(),
                    TOKEN_APPROVAL_STATUS_ERC_1155_APPROVED,
                    await magicToken.getAddress(),
                ),
            ).to.be.revertedWith('TreasureMarketplace: not an ERC1155 contract');
        });

        it('approve token with weth', async () => {
            expect(await marketplace.tokenApprovals(await nft.getAddress())).to.equal(
                TOKEN_APPROVAL_STATUS_NOT_APPROVED,
            );
            await marketplace.setTokenApprovalStatus(
                await nft.getAddress(),
                TOKEN_APPROVAL_STATUS_ERC_721_APPROVED,
                await weth.getAddress(),
            );
            expect(await marketplace.tokenApprovals(await nft.getAddress())).to.equal(
                TOKEN_APPROVAL_STATUS_ERC_721_APPROVED,
            );

            expect(await marketplace.getPaymentTokenForCollection(await nft.getAddress())).to.equal(
                await weth.getAddress(),
            );
        });

        it('unapprove token', async () => {
            await marketplace.setTokenApprovalStatus(
                await nft.getAddress(),
                TOKEN_APPROVAL_STATUS_ERC_721_APPROVED,
                await magicToken.getAddress(),
            );
            expect(await marketplace.tokenApprovals(await nft.getAddress())).to.equal(
                TOKEN_APPROVAL_STATUS_ERC_721_APPROVED,
            );
            await marketplace.setTokenApprovalStatus(
                await nft.getAddress(),
                TOKEN_APPROVAL_STATUS_NOT_APPROVED,
                await magicToken.getAddress(),
            );
            expect(await marketplace.tokenApprovals(await nft.getAddress())).to.equal(
                TOKEN_APPROVAL_STATUS_NOT_APPROVED,
            );
            // Allow to remove twice
            await marketplace.setTokenApprovalStatus(
                await nft.getAddress(),
                TOKEN_APPROVAL_STATUS_NOT_APPROVED,
                await magicToken.getAddress(),
            );
            expect(await marketplace.tokenApprovals(await nft.getAddress())).to.equal(
                TOKEN_APPROVAL_STATUS_NOT_APPROVED,
            );
        });

        it('pause() & unpause()', async () => {
            expect(await marketplace.paused()).to.equal(false);
            await marketplace.pause();
            expect(await marketplace.paused()).to.equal(true);
            await marketplace.unpause();
            expect(await marketplace.paused()).to.equal(false);
        });
    });

    describe('ERC721', () => {
        it('createOrUpdateListings()', async () => {
            const pricePerItem = ethers.parseUnits('1', 'ether');
            const expirationTime = 4102462800; // Midnight Jan 1, 2100
            const ListingsToCreate = {
                INVALID_MIN_PRICE: {
                    tokenId: 0,
                    nftAddress: await nft.getAddress(),
                    quantity: 1,
                    pricePerItem: 0,
                    expirationTime,
                    paymentToken: await magicToken.getAddress(),
                },
                INVALID_OVERFLOW_PRICE: {
                    tokenId: 0,
                    nftAddress: await nft.getAddress(),
                    quantity: 1,
                    pricePerItem: 999999999n,
                    expirationTime,
                    paymentToken: await magicToken.getAddress(),
                },
                INVALID_QUANTITY: {
                    tokenId: 0,
                    nftAddress: await nft.getAddress(),
                    quantity: 0,
                    pricePerItem,
                    expirationTime,
                    paymentToken: await magicToken.getAddress(),
                },
                INVALID_PAYMENT_TOKEN: {
                    tokenId: 0,
                    nftAddress: await nft.getAddress(),
                    quantity: 1,
                    pricePerItem,
                    expirationTime,
                    paymentToken: await weth.getAddress(),
                },
                INVALID_EXPIRATION: {
                    tokenId: 0,
                    nftAddress: await nft.getAddress(),
                    quantity: 5,
                    pricePerItem,
                    expirationTime: (await getCurrentTime()) - 100000,
                    paymentToken: await magicToken.getAddress(),
                },
                VALID_1: {
                    tokenId: 1,
                    nftAddress: await nft.getAddress(),
                    quantity: 1,
                    pricePerItem,
                    expirationTime,
                    paymentToken: await magicToken.getAddress(),
                },
                VALID_2: {
                    tokenId: 2,
                    nftAddress: await nft.getAddress(),
                    quantity: 1,
                    pricePerItem,
                    expirationTime,
                    paymentToken: await magicToken.getAddress(),
                },
                VALID_3: {
                    tokenId: 3,
                    nftAddress: await nft.getAddress(),
                    quantity: 1,
                    pricePerItem,
                    expirationTime,
                    paymentToken: await magicToken.getAddress(),
                },
                VALID_4: {
                    tokenId: 4,
                    nftAddress: await nft.getAddress(),
                    quantity: 1,
                    pricePerItem,
                    expirationTime,
                    paymentToken: await magicToken.getAddress(),
                },
            };
            const ListingsToUpdate = {
                INCREASE_PRICE: {
                    ...ListingsToCreate.VALID_1,
                    pricePerItem: ListingsToCreate.VALID_1.pricePerItem + 100n,
                },
                CHANGE_EXPIRATION: {
                    ...ListingsToCreate.VALID_1,
                    expirationTime: ListingsToCreate.VALID_1.expirationTime + 100,
                },
                CHANGE_EXPIRATION_2: {
                    ...ListingsToCreate.VALID_2,
                    expirationTime: ListingsToCreate.VALID_2.expirationTime + 100,
                },
                CHANGE_EXPIRATION_3: {
                    ...ListingsToCreate.VALID_3,
                    expirationTime: ListingsToCreate.VALID_2.expirationTime + 100,
                },
                INVALID_MIN_PRICE: {
                    ...ListingsToCreate.VALID_1,
                    pricePerItem: 0n,
                },
                INVALID_QUANTITY: {
                    ...ListingsToCreate.VALID_1,
                    quantity: 0,
                },
            };
            await nft.mint(seller);
            await nft.mint(seller);
            await nft.mint(seller);
            await nft.mint(seller);
            await nft.mint(seller);
            await nft.connect(sellerSigner).setApprovalForAll(await marketplace.getAddress(), true);
            await expect(
                marketplace.connect(sellerSigner).createOrUpdateListings([ListingsToCreate.VALID_1]),
            ).to.be.revertedWith('TreasureMarketplace: token is not approved for trading');
            await marketplace.setTokenApprovalStatus(
                await nft.getAddress(),
                TOKEN_APPROVAL_STATUS_ERC_721_APPROVED,
                await magicToken.getAddress(),
            );
            await expect(
                marketplace
                    .connect(sellerSigner)
                    .createOrUpdateListings([ListingsToCreate.VALID_1, ListingsToCreate.INVALID_MIN_PRICE]),
            ).to.be.revertedWith('TreasureMarketplace: below min price');
            await expect(
                marketplace
                    .connect(sellerSigner)
                    .createOrUpdateListings([ListingsToCreate.VALID_1, ListingsToCreate.INVALID_QUANTITY]),
            ).to.be.revertedWith('TreasureMarketplace: cannot list multiple ERC721');
            await expect(
                marketplace
                    .connect(sellerSigner)
                    .createOrUpdateListings([ListingsToCreate.VALID_1, ListingsToCreate.INVALID_EXPIRATION]),
            ).to.be.revertedWith('TreasureMarketplace: invalid expiration time');
            await expect(
                marketplace.connect(buyerSigner).createOrUpdateListings([ListingsToCreate.VALID_1]),
            ).to.be.revertedWith('TreasureMarketplace: not owning item');
            await marketplace.pause();
            await expect(
                marketplace.connect(sellerSigner).createOrUpdateListings([ListingsToCreate.VALID_1]),
            ).to.be.revertedWithCustomError(marketplace, 'EnforcedPause');
            await marketplace.unpause();
            await expect(
                marketplace
                    .connect(sellerSigner)
                    .createOrUpdateListings([ListingsToCreate.VALID_1, ListingsToCreate.INVALID_OVERFLOW_PRICE]),
            ).to.be.revertedWith('TreasureMarketplace: below min price');
            await expect(
                marketplace
                    .connect(sellerSigner)
                    .createOrUpdateListings([ListingsToCreate.VALID_1, ListingsToCreate.INVALID_PAYMENT_TOKEN]),
            ).to.be.revertedWith('TreasureMarketplace: Wrong payment token');
            await marketplace.connect(sellerSigner).createOrUpdateListings([ListingsToCreate.VALID_1]);
            await marketplace
                .connect(sellerSigner)
                .createOrUpdateListings([ListingsToCreate.VALID_2, ListingsToCreate.VALID_3]);
            const createdListings = [ListingsToCreate.VALID_1, ListingsToCreate.VALID_2, ListingsToCreate.VALID_3];
            await Promise.all(
                createdListings.map(async (createdListing) => {
                    const listing = await marketplace.listings(
                        await nft.getAddress(),
                        ListingsToCreate.VALID_1.tokenId,
                        seller,
                    );
                    expect(listing.quantity).to.be.equal(createdListing.quantity);
                    expect(listing.pricePerItem).to.be.equal(createdListing.pricePerItem);
                    expect(listing.expirationTime).to.be.equal(createdListing.expirationTime);
                }),
            );
            await marketplace.pause();
            await expect(
                marketplace.connect(sellerSigner).createOrUpdateListings([ListingsToUpdate.INCREASE_PRICE]),
            ).to.be.revertedWithCustomError(marketplace, 'EnforcedPause');

            await marketplace.unpause();
            // Can increase price
            await marketplace.connect(sellerSigner).createOrUpdateListings([ListingsToUpdate.INCREASE_PRICE]);

            const listing = await marketplace.listings(
                await nft.getAddress(),
                ListingsToUpdate.INCREASE_PRICE.tokenId,
                seller,
            );
            expect(listing.pricePerItem).to.be.equal(listing.pricePerItem);

            await expect(
                marketplace
                    .connect(sellerSigner)
                    .createOrUpdateListings([ListingsToUpdate.INCREASE_PRICE, ListingsToUpdate.INVALID_MIN_PRICE]),
            ).to.be.revertedWith('TreasureMarketplace: below min price');

            await expect(
                marketplace
                    .connect(sellerSigner)
                    .createOrUpdateListings([ListingsToUpdate.INCREASE_PRICE, ListingsToUpdate.INVALID_QUANTITY]),
            ).to.be.revertedWith('TreasureMarketplace: cannot list multiple ERC721');

            // Can create an update in the same transaction
            await marketplace
                .connect(sellerSigner)
                .createOrUpdateListings([ListingsToCreate.VALID_4, ListingsToUpdate.CHANGE_EXPIRATION]);
            await marketplace
                .connect(sellerSigner)
                .createOrUpdateListings([ListingsToUpdate.CHANGE_EXPIRATION_2, ListingsToUpdate.CHANGE_EXPIRATION_3]);
            await Promise.all(
                [
                    ListingsToCreate.VALID_4,
                    ListingsToUpdate.CHANGE_EXPIRATION,
                    ListingsToUpdate.CHANGE_EXPIRATION_2,
                    ListingsToUpdate.CHANGE_EXPIRATION_3,
                ].map(async (expectedListing) => {
                    const actualListing = await marketplace.listings(
                        await nft.getAddress(),
                        expectedListing.tokenId,
                        seller,
                    );
                    expect(actualListing.quantity).to.be.equal(expectedListing.quantity);
                    expect(actualListing.pricePerItem).to.be.equal(expectedListing.pricePerItem);
                    expect(actualListing.expirationTime).to.be.equal(expectedListing.expirationTime);
                }),
            );
        });

        describe('with NFT minted', () => {
            beforeEach(async () => {
                await nft.mint(seller);
            });

            it('createListing()', async () => {
                const tokenId = 0;
                const pricePerItem = ethers.parseUnits('1', 'ether');
                const expirationTime = 4102462800; // Midnight Jan 1, 2100
                expect(await nft.ownerOf(tokenId)).to.be.equal(seller);

                await nft.connect(sellerSigner).setApprovalForAll(await marketplace.getAddress(), true);

                await expect(
                    marketplace
                        .connect(sellerSigner)
                        .createListing(
                            await nft.getAddress(),
                            tokenId,
                            1,
                            pricePerItem,
                            expirationTime,
                            await magicToken.getAddress(),
                        ),
                ).to.be.revertedWith('TreasureMarketplace: token is not approved for trading');

                await marketplace.setTokenApprovalStatus(
                    await nft.getAddress(),
                    TOKEN_APPROVAL_STATUS_ERC_721_APPROVED,
                    await magicToken.getAddress(),
                );

                await expect(
                    marketplace
                        .connect(sellerSigner)
                        .createListing(
                            await nft.getAddress(),
                            tokenId,
                            1,
                            0,
                            expirationTime,
                            await magicToken.getAddress(),
                        ),
                ).to.be.revertedWith('TreasureMarketplace: below min price');

                await expect(
                    marketplace
                        .connect(sellerSigner)
                        .createListing(
                            await nft.getAddress(),
                            tokenId,
                            0,
                            pricePerItem,
                            expirationTime,
                            await magicToken.getAddress(),
                        ),
                ).to.be.revertedWith('TreasureMarketplace: cannot list multiple ERC721');

                await expect(
                    marketplace
                        .connect(buyerSigner)
                        .createListing(
                            await nft.getAddress(),
                            tokenId,
                            1,
                            pricePerItem,
                            expirationTime,
                            await magicToken.getAddress(),
                        ),
                ).to.be.revertedWith('TreasureMarketplace: not owning item');

                await marketplace.pause();

                await expect(
                    marketplace
                        .connect(sellerSigner)
                        .createListing(
                            await nft.getAddress(),
                            tokenId,
                            1,
                            pricePerItem,
                            expirationTime,
                            await magicToken.getAddress(),
                        ),
                ).to.be.revertedWithCustomError(marketplace, 'EnforcedPause');

                await marketplace.unpause();

                await expect(
                    marketplace
                        .connect(sellerSigner)
                        .createListing(
                            await nft.getAddress(),
                            tokenId,
                            1,
                            999999999n,
                            expirationTime,
                            await magicToken.getAddress(),
                        ),
                ).to.be.revertedWith('TreasureMarketplace: below min price');

                await expect(
                    marketplace
                        .connect(sellerSigner)
                        .createListing(
                            await nft.getAddress(),
                            tokenId,
                            1,
                            pricePerItem,
                            expirationTime,
                            await weth.getAddress(),
                        ),
                ).to.be.revertedWith('TreasureMarketplace: Wrong payment token');

                await marketplace
                    .connect(sellerSigner)
                    .createListing(
                        await nft.getAddress(),
                        tokenId,
                        1,
                        pricePerItem,
                        expirationTime,
                        await magicToken.getAddress(),
                    );

                const listing = await marketplace.listings(await nft.getAddress(), tokenId, seller);
                expect(listing.quantity).to.be.equal(1);
                expect(listing.pricePerItem).to.be.equal(pricePerItem);
                expect(listing.expirationTime).to.be.equal(expirationTime);
            });

            describe('with listing', () => {
                const tokenId = 0;
                const pricePerItem = ethers.parseUnits('1', 'ether');
                const expirationTime = 4102462800; // Midnight Jan 1, 2100

                beforeEach(async () => {
                    expect(await nft.ownerOf(tokenId)).to.be.equal(seller);

                    await nft.connect(sellerSigner).setApprovalForAll(await marketplace.getAddress(), true);
                    await marketplace.setTokenApprovalStatus(
                        await nft.getAddress(),
                        TOKEN_APPROVAL_STATUS_ERC_721_APPROVED,
                        await magicToken.getAddress(),
                    );
                    await marketplace
                        .connect(sellerSigner)
                        .createListing(
                            await nft.getAddress(),
                            tokenId,
                            1,
                            pricePerItem,
                            expirationTime,
                            await magicToken.getAddress(),
                        );
                });

                it('updateListing()', async () => {
                    const newPricePerItem = pricePerItem / 2n;
                    const newExpirationTime = (await getCurrentTime()) + 500;

                    await marketplace.pause();

                    await expect(
                        marketplace
                            .connect(sellerSigner)
                            .updateListing(
                                await nft.getAddress(),
                                tokenId,
                                1,
                                newPricePerItem,
                                newExpirationTime,
                                await magicToken.getAddress(),
                            ),
                    ).to.be.revertedWithCustomError(marketplace, 'EnforcedPause');

                    await marketplace.unpause();

                    // Can increase price
                    await marketplace
                        .connect(sellerSigner)
                        .updateListing(
                            await nft.getAddress(),
                            tokenId,
                            1,
                            pricePerItem + 1n,
                            newExpirationTime,
                            await magicToken.getAddress(),
                        );

                    await marketplace
                        .connect(sellerSigner)
                        .updateListing(
                            await nft.getAddress(),
                            tokenId,
                            1,
                            newPricePerItem,
                            newExpirationTime,
                            await magicToken.getAddress(),
                        );

                    await expect(
                        marketplace
                            .connect(sellerSigner)
                            .updateListing(
                                await nft.getAddress(),
                                tokenId,
                                1,
                                0,
                                newExpirationTime,
                                await magicToken.getAddress(),
                            ),
                    ).to.be.revertedWith('TreasureMarketplace: below min price');

                    await expect(
                        marketplace
                            .connect(sellerSigner)
                            .updateListing(
                                await nft.getAddress(),
                                tokenId,
                                0,
                                newPricePerItem,
                                newExpirationTime,
                                await magicToken.getAddress(),
                            ),
                    ).to.be.revertedWith('TreasureMarketplace: cannot list multiple ERC721');

                    const listing = await marketplace.listings(await nft.getAddress(), tokenId, seller);
                    expect(listing.quantity).to.be.equal(1);
                    expect(listing.pricePerItem).to.be.equal(newPricePerItem);
                    expect(listing.expirationTime).to.be.equal(newExpirationTime);
                });

                it('cancelListing()', async () => {
                    // Can cancel even if not listed
                    marketplace.connect(buyerSigner).cancelListing(await nft.getAddress(), tokenId);

                    await marketplace.connect(sellerSigner).cancelListing(await nft.getAddress(), tokenId);

                    const listing = await marketplace.listings(await nft.getAddress(), tokenId, seller);
                    expect(listing.quantity).to.be.equal(0);
                    expect(listing.pricePerItem).to.be.equal(0);
                    expect(listing.expirationTime).to.be.equal(0);
                });

                it('buyItem()', async () => {
                    expect(await nft.ownerOf(tokenId)).to.be.equal(seller);
                    await magicToken.mint(buyer, pricePerItem);
                    await magicToken.connect(buyerSigner).approve(await marketplace.getAddress(), pricePerItem);
                    expect(await magicToken.balanceOf(await marketplace.getAddress())).to.be.equal(0);
                    expect(await magicToken.balanceOf(seller)).to.be.equal(0);

                    await expect(
                        marketplace
                            .connect(buyerSigner)
                            .buyItems([
                                [
                                    await nft.getAddress(),
                                    tokenId,
                                    seller,
                                    0,
                                    pricePerItem,
                                    await magicToken.getAddress(),
                                    false,
                                ],
                            ]),
                    ).to.be.revertedWith('TreasureMarketplace: Nothing to buy');

                    await expect(
                        marketplace
                            .connect(buyerSigner)
                            .buyItems([
                                [
                                    await nft.getAddress(),
                                    tokenId,
                                    seller,
                                    2,
                                    pricePerItem,
                                    await magicToken.getAddress(),
                                    false,
                                ],
                            ]),
                    ).to.be.revertedWith('TreasureMarketplace: not enough quantity');

                    await expect(
                        marketplace
                            .connect(buyerSigner)
                            .buyItems([
                                [
                                    await nft.getAddress(),
                                    tokenId,
                                    seller,
                                    1,
                                    pricePerItem - 1n,
                                    await magicToken.getAddress(),
                                    false,
                                ],
                            ]),
                    ).to.be.revertedWith('TreasureMarketplace: price increased');

                    await expect(
                        marketplace
                            .connect(sellerSigner)
                            .buyItems([
                                [
                                    await nft.getAddress(),
                                    tokenId,
                                    seller,
                                    1,
                                    pricePerItem,
                                    await magicToken.getAddress(),
                                    false,
                                ],
                            ]),
                    ).to.be.revertedWith('TreasureMarketplace: Cannot buy your own item');

                    await marketplace.pause();

                    await expect(
                        marketplace
                            .connect(buyerSigner)
                            .buyItems([
                                [
                                    await nft.getAddress(),
                                    tokenId,
                                    seller,
                                    1,
                                    pricePerItem,
                                    await magicToken.getAddress(),
                                    false,
                                ],
                            ]),
                    ).to.be.revertedWithCustomError(marketplace, 'EnforcedPause');

                    await marketplace.unpause();

                    await expect(
                        marketplace
                            .connect(buyerSigner)
                            .buyItems([
                                [
                                    await nft.getAddress(),
                                    tokenId,
                                    seller,
                                    1,
                                    pricePerItem,
                                    await weth.getAddress(),
                                    false,
                                ],
                            ]),
                    ).to.be.revertedWith('TreasureMarketplace: Wrong payment token');

                    await marketplace
                        .connect(buyerSigner)
                        .buyItems([
                            [
                                await nft.getAddress(),
                                tokenId,
                                seller,
                                1,
                                pricePerItem,
                                await magicToken.getAddress(),
                                false,
                            ],
                        ]);

                    expect(await magicToken.balanceOf(await marketplace.feeReceipient())).to.be.equal(
                        pricePerItem / 100n,
                    );
                    expect(await magicToken.balanceOf(seller)).to.be.equal((pricePerItem * 99n) / 100n);

                    expect(await nft.ownerOf(tokenId)).to.be.equal(buyer);
                    const listing = await marketplace.listings(await nft.getAddress(), tokenId, seller);
                    expect(listing.quantity).to.be.equal(0);
                    expect(listing.pricePerItem).to.be.equal(0);
                    expect(listing.expirationTime).to.be.equal(0);
                });

                it('buyItem() with collection owner fee', async () => {
                    await magicToken.mint(buyer, pricePerItem);
                    await magicToken.connect(buyerSigner).approve(await marketplace.getAddress(), pricePerItem);

                    // When no collection owner, 5% fee. With collection owner, 2.5% fee to protocol.
                    await (await marketplace.setFee(500, 250)).wait();

                    // Admin owns this collection. 5% fee for collection.
                    const collectionOwnerFee = {
                        recipient: admin,
                        fee: 500,
                    };

                    await (await marketplace.setCollectionOwnerFee(await nft.getAddress(), collectionOwnerFee)).wait();

                    await (
                        await marketplace
                            .connect(buyerSigner)
                            .buyItems([
                                [
                                    await nft.getAddress(),
                                    tokenId,
                                    seller,
                                    1,
                                    pricePerItem,
                                    await magicToken.getAddress(),
                                    false,
                                ],
                            ])
                    ).wait();

                    expect(await magicToken.balanceOf(await marketplace.feeReceipient())).to.be.equal(
                        (pricePerItem * 25n) / 1000n,
                    );
                    // Owner of collection.
                    expect(await magicToken.balanceOf(admin)).to.be.equal((pricePerItem * 50n) / 1000n);
                    expect(await magicToken.balanceOf(seller)).to.be.equal((pricePerItem * 925n) / 1000n);
                });

                it('buyItem() with quantity 0', async () => {
                    expect(await nft.ownerOf(tokenId)).to.be.equal(seller);
                    await magicToken.mint(buyer, pricePerItem);
                    await magicToken.connect(buyerSigner).approve(await marketplace.getAddress(), pricePerItem);
                    expect(await magicToken.balanceOf(await marketplace.getAddress())).to.be.equal(0);
                    expect(await magicToken.balanceOf(seller)).to.be.equal(0);

                    await expect(
                        marketplace
                            .connect(buyerSigner)
                            .buyItems([
                                [
                                    await nft.getAddress(),
                                    tokenId,
                                    seller,
                                    0,
                                    pricePerItem,
                                    await magicToken.getAddress(),
                                    false,
                                ],
                            ]),
                    ).to.be.revertedWith('TreasureMarketplace: Nothing to buy');
                });

                describe('token approval revoked', () => {
                    beforeEach(async () => {
                        await marketplace.setTokenApprovalStatus(
                            await nft.getAddress(),
                            TOKEN_APPROVAL_STATUS_NOT_APPROVED,
                            await magicToken.getAddress(),
                        );
                    });

                    it('buyItem()', async () => {
                        expect(await nft.ownerOf(tokenId)).to.be.equal(seller);
                        await magicToken.mint(buyer, pricePerItem);
                        await magicToken.connect(buyerSigner).approve(await marketplace.getAddress(), pricePerItem);
                        expect(await magicToken.balanceOf(await marketplace.getAddress())).to.be.equal(0);
                        expect(await magicToken.balanceOf(seller)).to.be.equal(0);

                        await expect(
                            marketplace
                                .connect(buyerSigner)
                                .buyItems([
                                    [
                                        await nft.getAddress(),
                                        tokenId,
                                        seller,
                                        1,
                                        pricePerItem,
                                        await magicToken.getAddress(),
                                        false,
                                    ],
                                ]),
                        ).to.be.revertedWith('TreasureMarketplace: token is not approved for trading');
                    });
                });
            });
        });
    });

    describe('ERC1155', () => {
        it('createOrUpdateListings()', async () => {
            const pricePerItem = ethers.parseUnits('1', 'ether');
            const expirationTime = 4102462800; // Midnight Jan 1, 2100
            const quantity = 10;
            const ListingsToCreate = {
                INVALID_MIN_PRICE: {
                    tokenId: 0,
                    nftAddress: await erc1155.getAddress(),
                    quantity: 5,
                    pricePerItem: 0,
                    expirationTime,
                    paymentToken: await magicToken.getAddress(),
                },
                INVALID_OVERFLOW_PRICE: {
                    tokenId: 0,
                    nftAddress: await erc1155.getAddress(),
                    quantity: 5,
                    pricePerItem: 999999999n,
                    expirationTime,
                    paymentToken: await magicToken.getAddress(),
                },
                INVALID_MIN_QUANTITY: {
                    tokenId: 0,
                    nftAddress: await erc1155.getAddress(),
                    quantity: 0,
                    pricePerItem,
                    expirationTime,
                    paymentToken: await magicToken.getAddress(),
                },
                INVALID_OVERFLOW_QUANTITY: {
                    tokenId: 0,
                    nftAddress: await erc1155.getAddress(),
                    quantity: quantity + 1,
                    pricePerItem,
                    expirationTime,
                    paymentToken: await magicToken.getAddress(),
                },
                INVALID_PAYMENT_TOKEN: {
                    tokenId: 0,
                    nftAddress: await erc1155.getAddress(),
                    quantity: 5,
                    pricePerItem,
                    expirationTime,
                    paymentToken: await weth.getAddress(),
                },
                INVALID_EXPIRATION: {
                    tokenId: 1,
                    nftAddress: await erc1155.getAddress(),
                    quantity: 5,
                    pricePerItem,
                    expirationTime: (await getCurrentTime()) - 1,
                    paymentToken: await magicToken.getAddress(),
                },
                VALID_1: {
                    tokenId: 2,
                    nftAddress: await erc1155.getAddress(),
                    quantity: 5,
                    pricePerItem,
                    expirationTime,
                    paymentToken: await magicToken.getAddress(),
                },
                VALID_2: {
                    tokenId: 3,
                    nftAddress: await erc1155.getAddress(),
                    quantity: 5,
                    pricePerItem,
                    expirationTime,
                    paymentToken: await magicToken.getAddress(),
                },
                VALID_3: {
                    tokenId: 4,
                    nftAddress: await erc1155.getAddress(),
                    quantity: 2,
                    pricePerItem,
                    expirationTime,
                    paymentToken: await magicToken.getAddress(),
                },
                VALID_4: {
                    tokenId: 5,
                    nftAddress: await erc1155.getAddress(),
                    quantity: 5,
                    pricePerItem,
                    expirationTime,
                    paymentToken: await magicToken.getAddress(),
                },
            };
            const ListingsToUpdate = {
                INCREASE_PRICE: {
                    ...ListingsToCreate.VALID_1,
                    pricePerItem: ListingsToCreate.VALID_1.pricePerItem + 100n,
                },
                CHANGE_EXPIRATION: {
                    ...ListingsToCreate.VALID_1,
                    expirationTime: ListingsToCreate.VALID_1.expirationTime + 100,
                },
                CHANGE_EXPIRATION_2: {
                    ...ListingsToCreate.VALID_2,
                    expirationTime: ListingsToCreate.VALID_2.expirationTime + 100,
                },
                INCREASE_QUANTITY: {
                    ...ListingsToCreate.VALID_3,
                    quantity: ListingsToCreate.VALID_3.quantity + 1,
                },
                INVALID_MIN_PRICE: {
                    ...ListingsToCreate.VALID_1,
                    pricePerItem: 0,
                },
                INVALID_MIN_QUANTITY: {
                    ...ListingsToCreate.VALID_1,
                    quantity: 0,
                },
                INVALID_OVERFLOW_QUANTITY: {
                    ...ListingsToCreate.VALID_1,
                    quantity: quantity + 1,
                },
            };
            await erc1155['mint(address,uint256,uint256)'](seller, 0, quantity);
            await erc1155['mint(address,uint256,uint256)'](seller, 1, quantity);
            await erc1155['mint(address,uint256,uint256)'](seller, 2, quantity);
            await erc1155['mint(address,uint256,uint256)'](seller, 3, quantity);
            await erc1155['mint(address,uint256,uint256)'](seller, 4, quantity);
            await erc1155['mint(address,uint256,uint256)'](seller, 5, quantity);
            await erc1155.connect(sellerSigner).setApprovalForAll(await marketplace.getAddress(), true);
            await expect(
                marketplace.connect(sellerSigner).createOrUpdateListings([ListingsToCreate.VALID_1]),
            ).to.be.revertedWith('TreasureMarketplace: token is not approved for trading');
            await marketplace.setTokenApprovalStatus(
                await erc1155.getAddress(),
                TOKEN_APPROVAL_STATUS_ERC_1155_APPROVED,
                await magicToken.getAddress(),
            );
            await expect(
                marketplace
                    .connect(sellerSigner)
                    .createOrUpdateListings([ListingsToCreate.VALID_1, ListingsToCreate.INVALID_MIN_PRICE]),
            ).to.be.revertedWith('TreasureMarketplace: below min price');
            await expect(
                marketplace
                    .connect(sellerSigner)
                    .createOrUpdateListings([ListingsToCreate.VALID_1, ListingsToCreate.INVALID_EXPIRATION]),
            ).to.be.revertedWith('TreasureMarketplace: invalid expiration time');
            await expect(
                marketplace
                    .connect(sellerSigner)
                    .createOrUpdateListings([ListingsToCreate.VALID_1, ListingsToCreate.INVALID_MIN_QUANTITY]),
            ).to.be.revertedWith('TreasureMarketplace: nothing to list');
            await expect(
                marketplace
                    .connect(sellerSigner)
                    .createOrUpdateListings([ListingsToCreate.VALID_1, ListingsToCreate.INVALID_OVERFLOW_QUANTITY]),
            ).to.be.revertedWith('TreasureMarketplace: must hold enough nfts');
            await expect(
                marketplace.connect(buyerSigner).createOrUpdateListings([ListingsToCreate.VALID_1]),
            ).to.be.revertedWith('TreasureMarketplace: must hold enough nfts');
            await marketplace.pause();
            await expect(
                marketplace.connect(sellerSigner).createOrUpdateListings([ListingsToCreate.VALID_1]),
            ).to.be.revertedWithCustomError(marketplace, 'EnforcedPause');
            await marketplace.unpause();
            await expect(
                marketplace
                    .connect(sellerSigner)
                    .createOrUpdateListings([ListingsToCreate.VALID_1, ListingsToCreate.INVALID_OVERFLOW_PRICE]),
            ).to.be.revertedWith('TreasureMarketplace: below min price');
            await expect(
                marketplace
                    .connect(sellerSigner)
                    .createOrUpdateListings([ListingsToCreate.VALID_1, ListingsToCreate.INVALID_PAYMENT_TOKEN]),
            ).to.be.revertedWith('TreasureMarketplace: Wrong payment token');
            await marketplace.connect(sellerSigner).createOrUpdateListings([ListingsToCreate.VALID_1]);
            await marketplace
                .connect(sellerSigner)
                .createOrUpdateListings([ListingsToCreate.VALID_2, ListingsToCreate.VALID_3]);
            const createdListings = [ListingsToCreate.VALID_1, ListingsToCreate.VALID_2, ListingsToCreate.VALID_3];
            await Promise.all(
                createdListings.map(async (createdListing) => {
                    const listing = await marketplace.listings(
                        await erc1155.getAddress(),
                        createdListing.tokenId,
                        seller,
                    );
                    expect(listing.quantity).to.be.equal(createdListing.quantity);
                    expect(listing.pricePerItem).to.be.equal(createdListing.pricePerItem);
                    expect(listing.expirationTime).to.be.equal(createdListing.expirationTime);
                }),
            );
            await marketplace.pause();
            await expect(
                marketplace.connect(sellerSigner).createOrUpdateListings([ListingsToUpdate.INCREASE_PRICE]),
            ).to.be.revertedWithCustomError(marketplace, 'EnforcedPause');

            await marketplace.unpause();
            // Can increase price
            await marketplace.connect(sellerSigner).createOrUpdateListings([ListingsToUpdate.INCREASE_PRICE]);

            const listing = await marketplace.listings(
                await erc1155.getAddress(),
                ListingsToUpdate.INCREASE_PRICE.tokenId,
                seller,
            );
            expect(listing.pricePerItem).to.be.equal(listing.pricePerItem);

            await expect(
                marketplace
                    .connect(sellerSigner)
                    .createOrUpdateListings([ListingsToUpdate.INCREASE_PRICE, ListingsToUpdate.INVALID_MIN_PRICE]),
            ).to.be.revertedWith('TreasureMarketplace: below min price');
            await expect(
                marketplace
                    .connect(sellerSigner)
                    .createOrUpdateListings([
                        ListingsToUpdate.INCREASE_PRICE,
                        ListingsToUpdate.INVALID_OVERFLOW_QUANTITY,
                    ]),
            ).to.be.revertedWith('TreasureMarketplace: must hold enough nfts');
            await expect(
                marketplace
                    .connect(sellerSigner)
                    .createOrUpdateListings([ListingsToUpdate.INCREASE_PRICE, ListingsToUpdate.INVALID_MIN_QUANTITY]),
            ).to.be.revertedWith('TreasureMarketplace: nothing to list');

            // Can create an update in the same transaction
            await marketplace
                .connect(sellerSigner)
                .createOrUpdateListings([ListingsToCreate.VALID_4, ListingsToUpdate.CHANGE_EXPIRATION]);
            await marketplace
                .connect(sellerSigner)
                .createOrUpdateListings([ListingsToUpdate.CHANGE_EXPIRATION_2, ListingsToUpdate.INCREASE_QUANTITY]);
            await Promise.all(
                [
                    ListingsToCreate.VALID_4,
                    ListingsToUpdate.CHANGE_EXPIRATION,
                    ListingsToUpdate.CHANGE_EXPIRATION_2,
                    ListingsToUpdate.INCREASE_QUANTITY,
                ].map(async (expectedListing) => {
                    const actualListing = await marketplace.listings(
                        await erc1155.getAddress(),
                        expectedListing.tokenId,
                        seller,
                    );
                    expect(actualListing.quantity).to.be.equal(expectedListing.quantity);
                    expect(actualListing.pricePerItem).to.be.equal(expectedListing.pricePerItem);
                    expect(actualListing.expirationTime).to.be.equal(expectedListing.expirationTime);
                }),
            );
        });
        describe('with NFT minted', () => {
            const tokenId = 0;
            const quantity = 10;
            const pricePerItem = ethers.parseUnits('1', 'ether');
            const expirationTime = 4102462800; // Midnight Jan 1, 2100

            beforeEach(async () => {
                await erc1155['mint(address,uint256,uint256)'](seller, tokenId, quantity);
            });

            it('createListing()', async () => {
                expect(await erc1155.balanceOf(seller, tokenId)).to.be.equal(quantity);

                await erc1155.connect(sellerSigner).setApprovalForAll(await marketplace.getAddress(), true);
                await marketplace.setTokenApprovalStatus(
                    await erc1155.getAddress(),
                    TOKEN_APPROVAL_STATUS_ERC_1155_APPROVED,
                    await magicToken.getAddress(),
                );
                await expect(
                    marketplace
                        .connect(sellerSigner)
                        .createListing(
                            await erc1155.getAddress(),
                            tokenId,
                            quantity,
                            pricePerItem,
                            (await getCurrentTime()) - 1,
                            await magicToken.getAddress(),
                        ),
                ).to.be.revertedWith('TreasureMarketplace: invalid expiration time');

                await expect(
                    marketplace
                        .connect(sellerSigner)
                        .createListing(
                            await erc1155.getAddress(),
                            tokenId,
                            quantity,
                            0,
                            expirationTime,
                            await magicToken.getAddress(),
                        ),
                ).to.be.revertedWith('TreasureMarketplace: below min price');

                await expect(
                    marketplace
                        .connect(sellerSigner)
                        .createListing(
                            await erc1155.getAddress(),
                            tokenId,
                            0,
                            pricePerItem,
                            expirationTime,
                            await magicToken.getAddress(),
                        ),
                ).to.be.revertedWith('TreasureMarketplace: nothing to list');

                await expect(
                    marketplace
                        .connect(buyerSigner)
                        .createListing(
                            await erc1155.getAddress(),
                            tokenId,
                            1,
                            pricePerItem,
                            expirationTime,
                            await magicToken.getAddress(),
                        ),
                ).to.be.revertedWith('TreasureMarketplace: must hold enough nfts');

                await marketplace
                    .connect(sellerSigner)
                    .createListing(
                        await erc1155.getAddress(),
                        tokenId,
                        quantity,
                        pricePerItem,
                        expirationTime,
                        await magicToken.getAddress(),
                    );

                await expect(
                    marketplace
                        .connect(sellerSigner)
                        .createListing(
                            await erc1155.getAddress(),
                            tokenId,
                            quantity,
                            pricePerItem,
                            expirationTime,
                            await magicToken.getAddress(),
                        ),
                ).to.be.revertedWith('TreasureMarketplace: already listed');

                const listing = await marketplace.listings(await erc1155.getAddress(), tokenId, seller);
                expect(listing.quantity).to.be.equal(quantity);
                expect(listing.pricePerItem).to.be.equal(pricePerItem);
                expect(listing.expirationTime).to.be.equal(expirationTime);
            });

            describe('expirationTime', () => {
                const timedelta = 100;
                let thisExpirationTime: any;
                beforeEach(async () => {
                    thisExpirationTime = (await getCurrentTime()) + timedelta;

                    expect(await erc1155.balanceOf(seller, tokenId)).to.be.equal(quantity);
                    await marketplace.setTokenApprovalStatus(
                        await erc1155.getAddress(),
                        TOKEN_APPROVAL_STATUS_ERC_1155_APPROVED,
                        await magicToken.getAddress(),
                    );

                    await erc1155.connect(sellerSigner).setApprovalForAll(await marketplace.getAddress(), true);
                    await marketplace
                        .connect(sellerSigner)
                        .createListing(
                            await erc1155.getAddress(),
                            tokenId,
                            quantity,
                            pricePerItem,
                            thisExpirationTime,
                            await magicToken.getAddress(),
                        );
                });

                it('success', async () => {
                    expect(await erc1155.balanceOf(seller, tokenId)).to.be.equal(quantity);
                    await magicToken.mint(buyer, pricePerItem * BigInt(quantity));
                    await magicToken
                        .connect(buyerSigner)
                        .approve(await marketplace.getAddress(), pricePerItem * BigInt(quantity));
                    expect(await magicToken.balanceOf(await marketplace.getAddress())).to.be.equal(0);
                    expect(await magicToken.balanceOf(seller)).to.be.equal(0);

                    await marketplace
                        .connect(buyerSigner)
                        .buyItems([
                            [
                                await erc1155.getAddress(),
                                tokenId,
                                seller,
                                quantity,
                                pricePerItem,
                                await magicToken.getAddress(),
                                false,
                            ],
                        ]);

                    expect(await magicToken.balanceOf(await marketplace.feeReceipient())).to.be.equal(
                        (pricePerItem * BigInt(quantity)) / 100n,
                    );
                    expect(await magicToken.balanceOf(seller)).to.be.equal(
                        (pricePerItem * BigInt(quantity) * 99n) / 100n,
                    );

                    expect(await erc1155.balanceOf(buyer, tokenId)).to.be.equal(quantity);
                    expect(await erc1155.balanceOf(seller, tokenId)).to.be.equal(0);
                    const listing = await marketplace.listings(await erc1155.getAddress(), tokenId, seller);
                    expect(listing.quantity).to.be.equal(0);
                    expect(listing.pricePerItem).to.be.equal(0);
                    expect(listing.expirationTime).to.be.equal(0);
                });

                it('expired', async () => {
                    await mineBlock(thisExpirationTime + 100);

                    expect(await erc1155.balanceOf(seller, tokenId)).to.be.equal(quantity);
                    await magicToken.mint(buyer, pricePerItem * BigInt(quantity));
                    await magicToken
                        .connect(buyerSigner)
                        .approve(await marketplace.getAddress(), pricePerItem * BigInt(quantity));
                    expect(await magicToken.balanceOf(await marketplace.getAddress())).to.be.equal(0);
                    expect(await magicToken.balanceOf(seller)).to.be.equal(0);

                    await expect(
                        marketplace
                            .connect(buyerSigner)
                            .buyItems([
                                [
                                    await erc1155.getAddress(),
                                    tokenId,
                                    seller,
                                    quantity,
                                    pricePerItem,
                                    await magicToken.getAddress(),
                                    false,
                                ],
                            ]),
                    ).to.be.revertedWith('TreasureMarketplace: listing expired');

                    expect(await magicToken.balanceOf(buyer)).to.be.equal(pricePerItem * BigInt(quantity));
                    expect(await erc1155.balanceOf(seller, tokenId)).to.be.equal(quantity);

                    const listing = await marketplace.listings(await erc1155.getAddress(), tokenId, seller);
                    expect(listing.quantity).to.be.equal(quantity);
                    expect(listing.pricePerItem).to.be.equal(pricePerItem);
                    expect(listing.expirationTime).to.be.equal(thisExpirationTime);
                });
            });

            describe('with listing', () => {
                beforeEach(async () => {
                    expect(await erc1155.balanceOf(seller, tokenId)).to.be.equal(quantity);

                    await erc1155.connect(sellerSigner).setApprovalForAll(await marketplace.getAddress(), true);
                    await marketplace.setTokenApprovalStatus(
                        await erc1155.getAddress(),
                        TOKEN_APPROVAL_STATUS_ERC_1155_APPROVED,
                        await magicToken.getAddress(),
                    );
                    await marketplace
                        .connect(sellerSigner)
                        .createListing(
                            await erc1155.getAddress(),
                            tokenId,
                            quantity,
                            pricePerItem,
                            expirationTime,
                            await magicToken.getAddress(),
                        );
                });

                it('updateListing()', async () => {
                    const newPricePerItem = pricePerItem / 2n;
                    const newQuantity = 5;
                    const newExpirationTime = (await getCurrentTime()) + 500;

                    await expect(
                        marketplace
                            .connect(sellerSigner)
                            .updateListing(
                                await erc1155.getAddress(),
                                2,
                                quantity,
                                pricePerItem,
                                expirationTime,
                                await magicToken.getAddress(),
                            ),
                    ).to.be.revertedWith('TreasureMarketplace: not listed item');

                    await expect(
                        marketplace
                            .connect(buyerSigner)
                            .updateListing(
                                await erc1155.getAddress(),
                                tokenId,
                                quantity,
                                pricePerItem,
                                expirationTime,
                                await magicToken.getAddress(),
                            ),
                    ).to.be.revertedWith('TreasureMarketplace: not listed item');

                    await expect(
                        marketplace
                            .connect(sellerSigner)
                            .updateListing(
                                await erc1155.getAddress(),
                                tokenId,
                                0,
                                newPricePerItem,
                                newExpirationTime,
                                await magicToken.getAddress(),
                            ),
                    ).to.be.revertedWith('TreasureMarketplace: nothing to list');

                    await expect(
                        marketplace
                            .connect(sellerSigner)
                            .updateListing(
                                await erc1155.getAddress(),
                                tokenId,
                                newQuantity,
                                0,
                                newExpirationTime,
                                await magicToken.getAddress(),
                            ),
                    ).to.be.revertedWith('TreasureMarketplace: below min price');

                    // Can increase price
                    await marketplace
                        .connect(sellerSigner)
                        .updateListing(
                            await erc1155.getAddress(),
                            tokenId,
                            newQuantity,
                            pricePerItem + 1n,
                            newExpirationTime,
                            await magicToken.getAddress(),
                        );

                    await marketplace
                        .connect(sellerSigner)
                        .updateListing(
                            await erc1155.getAddress(),
                            tokenId,
                            newQuantity,
                            newPricePerItem,
                            newExpirationTime,
                            await magicToken.getAddress(),
                        );

                    const listing = await marketplace.listings(await erc1155.getAddress(), tokenId, seller);
                    expect(listing.quantity).to.be.equal(newQuantity);
                    expect(listing.pricePerItem).to.be.equal(newPricePerItem);
                    expect(listing.expirationTime).to.be.equal(newExpirationTime);
                });

                it('cancelListing()', async () => {
                    // Can cancel if not listed
                    marketplace.connect(buyerSigner).cancelListing(await erc1155.getAddress(), tokenId);

                    // Can cancel if not listed
                    marketplace.connect(buyerSigner).cancelListing(await erc1155.getAddress(), tokenId);

                    await marketplace.connect(sellerSigner).cancelListing(await erc1155.getAddress(), tokenId);

                    // Can cancel if not listed
                    marketplace.connect(sellerSigner).cancelListing(await erc1155.getAddress(), tokenId);

                    const listing = await marketplace.listings(await erc1155.getAddress(), tokenId, seller);
                    expect(listing.quantity).to.be.equal(0);
                    expect(listing.pricePerItem).to.be.equal(0);
                    expect(listing.expirationTime).to.be.equal(0);
                });

                describe('buyItem()', () => {
                    it('all', async () => {
                        expect(await erc1155.balanceOf(seller, tokenId)).to.be.equal(quantity);
                        await magicToken.mint(buyer, pricePerItem * BigInt(quantity));
                        await magicToken
                            .connect(buyerSigner)
                            .approve(await marketplace.getAddress(), pricePerItem * BigInt(quantity));
                        expect(await magicToken.balanceOf(await marketplace.getAddress())).to.be.equal(0);
                        expect(await magicToken.balanceOf(seller)).to.be.equal(0);

                        await expect(
                            marketplace
                                .connect(buyerSigner)
                                .buyItems([
                                    [
                                        await erc1155.getAddress(),
                                        2,
                                        seller,
                                        quantity,
                                        pricePerItem,
                                        await magicToken.getAddress(),
                                        false,
                                    ],
                                ]),
                        ).to.be.revertedWith('TreasureMarketplace: not listed item');

                        await erc1155.connect(sellerSigner).safeTransferFrom(seller, staker3, tokenId, 1, '0x');

                        await expect(
                            marketplace
                                .connect(buyerSigner)
                                .buyItems([
                                    [
                                        await erc1155.getAddress(),
                                        tokenId,
                                        seller,
                                        quantity,
                                        pricePerItem,
                                        await magicToken.getAddress(),
                                        false,
                                    ],
                                ]),
                        ).to.be.reverted;

                        await erc1155.connect(staker3Signer).safeTransferFrom(staker3, seller, tokenId, 1, '0x');

                        await expect(
                            marketplace
                                .connect(buyerSigner)
                                .buyItems([
                                    [
                                        await erc1155.getAddress(),
                                        tokenId,
                                        seller,
                                        0,
                                        pricePerItem,
                                        await magicToken.getAddress(),
                                        false,
                                    ],
                                ]),
                        ).to.be.revertedWith('TreasureMarketplace: Nothing to buy');

                        await marketplace
                            .connect(buyerSigner)
                            .buyItems([
                                [
                                    await erc1155.getAddress(),
                                    tokenId,
                                    seller,
                                    quantity,
                                    pricePerItem,
                                    await magicToken.getAddress(),
                                    false,
                                ],
                            ]);

                        expect(await magicToken.balanceOf(await marketplace.feeReceipient())).to.be.equal(
                            (pricePerItem * BigInt(quantity)) / 100n,
                        );
                        expect(await magicToken.balanceOf(seller)).to.be.equal(
                            (pricePerItem * BigInt(quantity) * 99n) / 100n,
                        );

                        expect(await erc1155.balanceOf(buyer, tokenId)).to.be.equal(quantity);
                        expect(await erc1155.balanceOf(seller, tokenId)).to.be.equal(0);
                        const listing = await marketplace.listings(await erc1155.getAddress(), tokenId, seller);
                        expect(listing.quantity).to.be.equal(0);
                        expect(listing.pricePerItem).to.be.equal(0);
                        expect(listing.expirationTime).to.be.equal(0);
                    });

                    it('partial', async () => {
                        const buyQuantity = 5;

                        expect(await erc1155.balanceOf(seller, tokenId)).to.be.equal(quantity);
                        await magicToken.mint(buyer, pricePerItem * BigInt(buyQuantity));
                        await magicToken
                            .connect(buyerSigner)
                            .approve(await marketplace.getAddress(), pricePerItem * BigInt(buyQuantity));
                        expect(await magicToken.balanceOf(await marketplace.getAddress())).to.be.equal(0);
                        expect(await magicToken.balanceOf(seller)).to.be.equal(0);

                        await marketplace
                            .connect(buyerSigner)
                            .buyItems([
                                [
                                    await erc1155.getAddress(),
                                    tokenId,
                                    seller,
                                    buyQuantity,
                                    pricePerItem,
                                    await magicToken.getAddress(),
                                    false,
                                ],
                            ]);

                        expect(await magicToken.balanceOf(await marketplace.feeReceipient())).to.be.equal(
                            (pricePerItem * BigInt(buyQuantity)) / 100n,
                        );
                        expect(await magicToken.balanceOf(seller)).to.be.equal(
                            (pricePerItem * BigInt(buyQuantity) * 99n) / 100n,
                        );

                        expect(await erc1155.balanceOf(buyer, tokenId)).to.be.equal(buyQuantity);
                        expect(await erc1155.balanceOf(seller, tokenId)).to.be.equal(quantity - buyQuantity);

                        const listing = await marketplace.listings(await erc1155.getAddress(), tokenId, seller);
                        expect(listing.quantity).to.be.equal(quantity - buyQuantity);
                        expect(listing.pricePerItem).to.be.equal(pricePerItem);
                        expect(listing.expirationTime).to.be.equal(expirationTime);
                    });
                });
            });
        });
    });

    it('Should be able to list/buy in weth', async () => {
        await marketplace.setTokenApprovalStatus(
            await nft.getAddress(),
            TOKEN_APPROVAL_STATUS_ERC_721_APPROVED,
            await weth.getAddress(),
        );

        await (await nft.connect(sellerSigner).setApprovalForAll(await marketplace.getAddress(), true)).wait();
        await (await nft.mint(seller)).wait();

        const tokenId = 0;
        const pricePerItem = ethers.parseEther('1');

        await expect(
            marketplace
                .connect(sellerSigner)
                .createListing(
                    await nft.getAddress(),
                    tokenId,
                    1,
                    pricePerItem,
                    1000000000000,
                    await magicToken.getAddress(),
                ),
        ).to.be.revertedWith('TreasureMarketplace: Wrong payment token');

        await (
            await marketplace
                .connect(sellerSigner)
                .createListing(await nft.getAddress(), tokenId, 1, pricePerItem, 1000000000000, await weth.getAddress())
        ).wait();

        const listing = await marketplace.listings(await nft.getAddress(), tokenId, seller);
        expect(listing.paymentTokenAddress).to.equal(await weth.getAddress());

        await (await weth.connect(buyerSigner).approve(await marketplace.getAddress(), pricePerItem)).wait();

        await (await weth.connect(buyerSigner).deposit({ value: pricePerItem })).wait();

        expect(await weth.balanceOf(buyer)).to.eq(pricePerItem);

        await (
            await marketplace
                .connect(buyerSigner)
                .buyItems([[await nft.getAddress(), tokenId, seller, 1, pricePerItem, await weth.getAddress(), false]])
        ).wait();

        expect(await nft.ownerOf(tokenId)).to.equal(buyer);
        // 1% fees are transferred
        expect(await weth.balanceOf(seller)).to.eq(pricePerItem - ethers.parseEther('0.01'));
    });

    it('Should be able to buy in ETH for listings in weth', async () => {
        await marketplace.setTokenApprovalStatus(
            await nft.getAddress(),
            TOKEN_APPROVAL_STATUS_ERC_721_APPROVED,
            await weth.getAddress(),
        );

        await (await nft.connect(sellerSigner).setApprovalForAll(await marketplace.getAddress(), true)).wait();
        await (await nft.mint(seller)).wait();

        const tokenId = 0;
        const pricePerItem = ethers.parseEther('1');

        await (
            await marketplace
                .connect(sellerSigner)
                .createListing(await nft.getAddress(), tokenId, 1, pricePerItem, 1000000000000, await weth.getAddress())
        ).wait();

        const listing = await marketplace.listings(await nft.getAddress(), tokenId, seller);
        expect(listing.paymentTokenAddress).to.equal(await weth.getAddress());

        await expect(
            marketplace
                .connect(buyerSigner)
                .buyItems([[await nft.getAddress(), tokenId, seller, 1, pricePerItem, await weth.getAddress(), true]]),
        ).to.be.revertedWith('TreasureMarketplace: Sending eth was not successful');

        await expect(
            marketplace
                .connect(buyerSigner)
                .buyItems([[await nft.getAddress(), tokenId, seller, 1, pricePerItem, await weth.getAddress(), true]], {
                    value: pricePerItem + 1n,
                }),
        ).to.be.revertedWith('TreasureMarketplace: Bad ETH value');

        // Contract doesn't have enough eth to process
        await expect(
            marketplace
                .connect(buyerSigner)
                .buyItems([[await nft.getAddress(), tokenId, seller, 1, pricePerItem, await weth.getAddress(), true]], {
                    value: pricePerItem - 1n,
                }),
        ).to.be.revertedWith('TreasureMarketplace: Sending eth was not successful');

        await expect(
            await marketplace
                .connect(buyerSigner)
                .buyItems([[await nft.getAddress(), tokenId, seller, 1, pricePerItem, await weth.getAddress(), true]], {
                    value: pricePerItem,
                }),
        ).to.changeEtherBalances(
            [buyerSigner, sellerSigner],
            [pricePerItem * -1n, pricePerItem - ethers.parseEther('0.01')],
        );

        expect(await nft.ownerOf(tokenId)).to.equal(buyer);
    });

    it('Should be able to create a valid 721/1155 token bid', async () => {
        const tokenId = 0;
        const pricePerItem = ethers.parseEther('1');

        await expect(
            marketplace
                .connect(buyerSigner)
                .createOrUpdateTokenBid(
                    await nft.getAddress(),
                    tokenId,
                    1,
                    pricePerItem,
                    1000000000000,
                    await magicToken.getAddress(),
                ),
        ).to.be.revertedWith('TreasureMarketplace: token is not approved for trading');

        await (
            await marketplace.setTokenApprovalStatus(
                await nft.getAddress(),
                TOKEN_APPROVAL_STATUS_ERC_721_APPROVED,
                await magicToken.getAddress(),
            )
        ).wait();
        await (
            await marketplace.setTokenApprovalStatus(
                await erc1155.getAddress(),
                TOKEN_APPROVAL_STATUS_ERC_1155_APPROVED,
                await magicToken.getAddress(),
            )
        ).wait();

        await (await nft.connect(sellerSigner).setApprovalForAll(await marketplace.getAddress(), true)).wait();
        await (await nft.mint(seller)).wait();

        await expect(
            marketplace
                .connect(buyerSigner)
                .createOrUpdateTokenBid(
                    await nft.getAddress(),
                    tokenId,
                    2,
                    pricePerItem,
                    1000000000000,
                    await magicToken.getAddress(),
                ),
        ).to.be.revertedWith('TreasureMarketplace: token bid quantity 1 for ERC721');

        await expect(
            marketplace
                .connect(buyerSigner)
                .createOrUpdateTokenBid(
                    await nft.getAddress(),
                    tokenId,
                    0,
                    pricePerItem,
                    1000000000000,
                    await magicToken.getAddress(),
                ),
        ).to.be.revertedWith('TreasureMarketplace: token bid quantity 1 for ERC721');

        await expect(
            marketplace
                .connect(buyerSigner)
                .createOrUpdateTokenBid(
                    await nft.getAddress(),
                    tokenId,
                    1,
                    pricePerItem,
                    1,
                    await magicToken.getAddress(),
                ),
        ).to.be.revertedWith('TreasureMarketplace: invalid expiration time');

        await expect(
            marketplace
                .connect(buyerSigner)
                .createOrUpdateTokenBid(
                    await nft.getAddress(),
                    tokenId,
                    1,
                    1,
                    1000000000000,
                    await magicToken.getAddress(),
                ),
        ).to.be.revertedWith('TreasureMarketplace: below min price');

        await expect(
            marketplace
                .connect(buyerSigner)
                .createOrUpdateTokenBid(
                    await nft.getAddress(),
                    tokenId,
                    1,
                    pricePerItem,
                    1000000000000,
                    await weth.getAddress(),
                ),
        ).to.be.revertedWith('TreasureMarketplace: Bad payment token');

        await expect(
            marketplace
                .connect(buyerSigner)
                .createOrUpdateTokenBid(
                    await nft.getAddress(),
                    tokenId,
                    1,
                    pricePerItem,
                    1000000000000,
                    await magicToken.getAddress(),
                ),
        ).to.be.revertedWith('TreasureMarketplace: Not enough tokens owned or allowed for bid');

        await (await magicToken.mint(buyer, pricePerItem)).wait();

        // Hasn't approved enough so the same error will occur
        await expect(
            marketplace
                .connect(buyerSigner)
                .createOrUpdateTokenBid(
                    await nft.getAddress(),
                    tokenId,
                    1,
                    pricePerItem,
                    1000000000000,
                    await magicToken.getAddress(),
                ),
        ).to.be.revertedWith('TreasureMarketplace: Not enough tokens owned or allowed for bid');

        await (await magicToken.connect(buyerSigner).approve(await marketplace.getAddress(), pricePerItem)).wait();

        await (
            await marketplace
                .connect(buyerSigner)
                .createOrUpdateTokenBid(
                    await nft.getAddress(),
                    tokenId,
                    1,
                    pricePerItem,
                    1000000000000,
                    await magicToken.getAddress(),
                )
        ).wait();

        await (
            await marketplace
                .connect(buyerSigner)
                .createOrUpdateTokenBid(
                    await erc1155.getAddress(),
                    tokenId,
                    1,
                    pricePerItem,
                    1000000000000,
                    await magicToken.getAddress(),
                )
        ).wait();
    });

    it('Should be able to create a valid 721 collection bid', async () => {
        const pricePerItem = ethers.parseEther('1');

        await (
            await marketplace.setTokenApprovalStatus(
                await nft.getAddress(),
                TOKEN_APPROVAL_STATUS_ERC_721_APPROVED,
                await magicToken.getAddress(),
            )
        ).wait();
        await (
            await marketplace.setTokenApprovalStatus(
                await erc1155.getAddress(),
                TOKEN_APPROVAL_STATUS_ERC_1155_APPROVED,
                await magicToken.getAddress(),
            )
        ).wait();

        await expect(
            marketplace
                .connect(buyerSigner)
                .createOrUpdateCollectionBid(
                    await erc1155.getAddress(),
                    1,
                    pricePerItem,
                    1000000000000,
                    await magicToken.getAddress(),
                ),
        ).to.be.revertedWith('TreasureMarketplace: No collection bids on 1155s');

        await expect(
            marketplace
                .connect(buyerSigner)
                .createOrUpdateCollectionBid(
                    await nft.getAddress(),
                    0,
                    pricePerItem,
                    1000000000000,
                    await magicToken.getAddress(),
                ),
        ).to.be.revertedWith('TreasureMarketplace: Bad quantity');

        await (await magicToken.mint(buyer, pricePerItem * 2n)).wait();
        await (await magicToken.connect(buyerSigner).approve(await marketplace.getAddress(), pricePerItem)).wait();

        // 2 for an nft is allowed... however, must have enough $$ approved to cover both at the time
        // of bidding.
        await expect(
            marketplace
                .connect(buyerSigner)
                .createOrUpdateCollectionBid(
                    await nft.getAddress(),
                    2,
                    pricePerItem,
                    1000000000000,
                    await magicToken.getAddress(),
                ),
        ).to.be.revertedWith('TreasureMarketplace: Not enough tokens owned or allowed for bid');

        await (await magicToken.connect(buyerSigner).approve(await marketplace.getAddress(), pricePerItem * 2n)).wait();

        await (
            await marketplace
                .connect(buyerSigner)
                .createOrUpdateCollectionBid(
                    await nft.getAddress(),
                    2,
                    pricePerItem,
                    1000000000000,
                    await magicToken.getAddress(),
                )
        ).wait();
    });

    it('Should be able to accept a collection level bid', async () => {
        const pricePerItem = ethers.parseEther('1');

        await (
            await marketplace.setTokenApprovalStatus(
                await nft.getAddress(),
                TOKEN_APPROVAL_STATUS_ERC_721_APPROVED,
                await magicToken.getAddress(),
            )
        ).wait();

        await (await magicToken.mint(buyer, pricePerItem * 3n)).wait();
        await (await magicToken.connect(buyerSigner).approve(await marketplace.getAddress(), pricePerItem * 3n)).wait();

        await (
            await marketplace
                .connect(buyerSigner)
                .createOrUpdateCollectionBid(
                    await nft.getAddress(),
                    2,
                    pricePerItem,
                    1000000000000,
                    await magicToken.getAddress(),
                )
        ).wait();

        await expect(
            marketplace
                .connect(buyerSigner)
                .acceptCollectionBid([
                    await nft.getAddress(),
                    0,
                    buyer,
                    1,
                    pricePerItem,
                    await magicToken.getAddress(),
                ]),
        ).to.be.revertedWith('TreasureMarketplace: Cannot supply own bid');

        await expect(
            marketplace
                .connect(sellerSigner)
                .acceptCollectionBid([
                    await nft.getAddress(),
                    0,
                    buyer,
                    1,
                    pricePerItem - 1n,
                    await magicToken.getAddress(),
                ]),
        ).to.be.revertedWith('TreasureMarketplace: price does not match');

        await expect(
            marketplace
                .connect(sellerSigner)
                .acceptCollectionBid([
                    await nft.getAddress(),
                    0,
                    buyer,
                    2,
                    pricePerItem,
                    await magicToken.getAddress(),
                ]),
        ).to.be.revertedWith('TreasureMarketplace: Cannot supply multiple ERC721s');

        await expect(
            marketplace
                .connect(sellerSigner)
                .acceptCollectionBid([await nft.getAddress(), 0, buyer, 1, pricePerItem, await weth.getAddress()]),
        ).to.be.revertedWith('TreasureMarketplace: Wrong payment token');

        // Doesn't own the token id
        await expect(
            marketplace
                .connect(sellerSigner)
                .acceptCollectionBid([
                    await nft.getAddress(),
                    0,
                    buyer,
                    1,
                    pricePerItem,
                    await magicToken.getAddress(),
                ]),
        )
            .to.be.revertedWithCustomError(nft, 'ERC721NonexistentToken')
            .withArgs(0);

        await (await nft.connect(sellerSigner).setApprovalForAll(await marketplace.getAddress(), true)).wait();

        // Enough to supply 3 nfts to bid, but bidder only asked for two
        await (await nft.mint(seller)).wait();
        await (await nft.mint(seller)).wait();
        await (await nft.mint(seller)).wait();

        await (
            await marketplace
                .connect(sellerSigner)
                .acceptCollectionBid([await nft.getAddress(), 0, buyer, 1, pricePerItem, await magicToken.getAddress()])
        ).wait();

        await (
            await marketplace
                .connect(sellerSigner)
                .acceptCollectionBid([await nft.getAddress(), 1, buyer, 1, pricePerItem, await magicToken.getAddress()])
        ).wait();

        await expect(
            marketplace
                .connect(sellerSigner)
                .acceptCollectionBid([
                    await nft.getAddress(),
                    0,
                    buyer,
                    1,
                    pricePerItem,
                    await magicToken.getAddress(),
                ]),
        ).to.be.revertedWith('TreasureMarketplace: bid does not exist');

        expect(await nft.ownerOf(0)).to.equal(buyer);
        expect(await nft.ownerOf(1)).to.equal(buyer);
        expect(await nft.ownerOf(2)).to.equal(seller);
        expect(await magicToken.balanceOf(buyer)).to.equal(pricePerItem);
        expect(await magicToken.balanceOf(seller)).to.equal(ethers.parseEther('1.98'));
    });

    it('Should be able to accept a token level bid', async () => {
        const pricePerItem = ethers.parseEther('1');

        await (
            await marketplace.setTokenApprovalStatus(
                await nft.getAddress(),
                TOKEN_APPROVAL_STATUS_ERC_721_APPROVED,
                await magicToken.getAddress(),
            )
        ).wait();
        await (
            await marketplace.setTokenApprovalStatus(
                await erc1155.getAddress(),
                TOKEN_APPROVAL_STATUS_ERC_1155_APPROVED,
                await magicToken.getAddress(),
            )
        ).wait();

        await (await magicToken.mint(buyer, pricePerItem * 3n)).wait();
        await (await magicToken.connect(buyerSigner).approve(await marketplace.getAddress(), pricePerItem * 3n)).wait();

        await (
            await marketplace
                .connect(buyerSigner)
                .createOrUpdateTokenBid(
                    await nft.getAddress(),
                    0,
                    1,
                    pricePerItem,
                    1000000000000,
                    await magicToken.getAddress(),
                )
        ).wait();

        await (
            await marketplace
                .connect(buyerSigner)
                .createOrUpdateTokenBid(
                    await erc1155.getAddress(),
                    0,
                    2,
                    pricePerItem,
                    1000000000000,
                    await magicToken.getAddress(),
                )
        ).wait();

        // Wrong token id. No bid found
        await expect(
            marketplace
                .connect(sellerSigner)
                .acceptCollectionBid([
                    await nft.getAddress(),
                    10,
                    buyer,
                    1,
                    pricePerItem - 1n,
                    await magicToken.getAddress(),
                ]),
        ).to.be.revertedWith('TreasureMarketplace: bid does not exist');

        await (await nft.connect(sellerSigner).setApprovalForAll(await marketplace.getAddress(), true)).wait();
        await (await erc1155.connect(sellerSigner).setApprovalForAll(await marketplace.getAddress(), true)).wait();

        await (await nft.mint(seller)).wait();
        await (await erc1155['mint(address,uint256,uint256)'](seller, 0, 2)).wait();

        await (
            await marketplace
                .connect(sellerSigner)
                .acceptTokenBid([await nft.getAddress(), 0, buyer, 1, pricePerItem, await magicToken.getAddress()])
        ).wait();

        await (
            await marketplace
                .connect(sellerSigner)
                .acceptTokenBid([await erc1155.getAddress(), 0, buyer, 2, pricePerItem, await magicToken.getAddress()])
        ).wait();

        expect(await nft.ownerOf(0)).to.equal(buyer);
        expect(await erc1155.balanceOf(buyer, 0)).to.equal(2);
        expect(await magicToken.balanceOf(buyer)).to.equal(0);
        expect(await magicToken.balanceOf(seller)).to.equal(ethers.parseEther('2.97'));
    });
});
