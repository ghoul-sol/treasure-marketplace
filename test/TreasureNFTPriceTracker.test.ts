import hre from 'hardhat';
import { expect } from 'chai';

const { ethers, getNamedAccounts } = hre;

enum LegionRarity {
    LEGENDARY,
    RARE,
    SPECIAL,
    UNCOMMON,
    COMMON,
    RECRUIT,
}

enum LegionGeneration {
    GENESIS,
    AUXILIARY,
    RECRUIT,
}

enum FloorType {
    FLOOR,
    SUBFLOOR1,
    SUBFLOOR2,
    SUBFLOOR3,
}

describe('TreasureNFTPriceTracker', () => {
    let nftPriceTracker: any;
    let genCommonMetadataContract: any;

    let legionNFTContractAddress: string;

    let marketplaceSigner: any;

    before(async () => {
        const namedAccounts = await getNamedAccounts();
        marketplaceSigner = await ethers.provider.getSigner(namedAccounts.staker1);
        legionNFTContractAddress = await (await ethers.provider.getSigner(namedAccounts.staker3)).getAddress();
    });

    beforeEach(async () => {
        const metadataMockFactory = await ethers.getContractFactory('LegionMetadataStoreMock');
        genCommonMetadataContract = await metadataMockFactory.deploy(LegionGeneration.GENESIS, LegionRarity.COMMON);
        await genCommonMetadataContract.waitForDeployment();

        const trackerFactory = await ethers.getContractFactory('TreasureNFTPriceTracker');
        nftPriceTracker = await trackerFactory.deploy();
        await nftPriceTracker.waitForDeployment();
        await nftPriceTracker.initialize(
            await marketplaceSigner.getAddress(),
            legionNFTContractAddress,
            await genCommonMetadataContract.getAddress(),
        );
    });

    it('initialize()', async () => {
        await expect(
            nftPriceTracker.initialize(
                await marketplaceSigner.getAddress(),
                legionNFTContractAddress,
                await genCommonMetadataContract.getAddress(),
            ),
        ).to.be.revertedWithCustomError(nftPriceTracker, 'InvalidInitialization');

        expect(await nftPriceTracker.treasureMarketplaceContract()).to.equal(await marketplaceSigner.getAddress());
        expect(await nftPriceTracker.legionContract()).to.equal(legionNFTContractAddress);
        expect(await nftPriceTracker.legionMetadata()).to.equal(await genCommonMetadataContract.getAddress());
    });

    it('recordSale()', async () => {
        const tokenId = 1;
        const salePrice1 = ethers.parseEther('500');
        const salePrice2 = ethers.parseEther('100');
        const salePrice3 = ethers.parseEther('900');
        await expect(nftPriceTracker.recordSale(legionNFTContractAddress, tokenId, salePrice1)).to.be.revertedWith(
            'Invalid caller',
        );

        // AveragePriceUpdated(
        //     address indexed _collection,
        //     FloorType indexed _floorType,
        //     uint256 _oldAverage,
        //     uint256 _salePrice,
        //     uint256 _newAverage
        // )
        await expect(
            nftPriceTracker.connect(marketplaceSigner).recordSale(legionNFTContractAddress, tokenId, salePrice1),
        )
            .to.emit(nftPriceTracker, 'AveragePriceUpdated')
            .withArgs(legionNFTContractAddress, FloorType.SUBFLOOR1, 0, salePrice1, salePrice1);

        const expectedAvgPrice = (salePrice1 + salePrice2) / 2n;
        await expect(
            nftPriceTracker.connect(marketplaceSigner).recordSale(legionNFTContractAddress, tokenId, salePrice2),
        )
            .to.emit(nftPriceTracker, 'AveragePriceUpdated')
            .withArgs(legionNFTContractAddress, FloorType.SUBFLOOR1, salePrice1, salePrice2, expectedAvgPrice);

        expect(
            await nftPriceTracker.getAveragePriceForCollection(legionNFTContractAddress, FloorType.SUBFLOOR1),
        ).to.equal(expectedAvgPrice);

        const expectedAvgPrice2 = (expectedAvgPrice + salePrice3) / 2n;
        await expect(
            nftPriceTracker.connect(marketplaceSigner).recordSale(legionNFTContractAddress, tokenId, salePrice3),
        )
            .to.emit(nftPriceTracker, 'AveragePriceUpdated')
            .withArgs(legionNFTContractAddress, FloorType.SUBFLOOR1, expectedAvgPrice, salePrice3, expectedAvgPrice2);

        expect(
            await nftPriceTracker.getAveragePriceForCollection(legionNFTContractAddress, FloorType.SUBFLOOR1),
        ).to.equal(expectedAvgPrice2);
    });
});
