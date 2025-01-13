import { HardhatRuntimeEnvironment } from 'hardhat/types';
import { DeployFunction } from 'hardhat-deploy/types';

const func: DeployFunction = async (hre: HardhatRuntimeEnvironment) => {
    const { deployments, getNamedAccounts } = hre;
    const { deploy, execute, read } = deployments;
    const { deployer } = await getNamedAccounts();

    // Constants for this deploy script.
    const fee = 500; // 5%
    const feeWithCollectionOwner = 250; // 2.5%
    const feeReceipient = '0x36Ec9CF670d220abBc59f866d0BD916166f22b1D'; // Marketplace multisig.
    const newOwner = deployer;
    const newProxyOwner = deployer;
    const magicAddress = '0x263D8f36Bb8d0d9526255E205868C26690b04B88';
    const wethAddress = '0x263D8f36Bb8d0d9526255E205868C26690b04B88';

    const contractName = 'TreasureMarketplace';

    // Deploy/upgrade the Treasure marketplace contract.
    const treasureMarketplace = await deploy(contractName, {
        from: deployer,
        log: true,
        proxy: {
            owner: newProxyOwner,

            // On ZK-based chains, need to manually copy TransparentUpgradeableProxy and
            // ProxyAdmin to your source directory.
            proxyContract: 'TransparentUpgradeableProxy',
            checkABIConflict: false,
            viaAdminContract: 'ProxyAdmin',

            execute: {
                init: {
                    methodName: 'initialize',
                    args: [fee, feeReceipient, magicAddress],
                },
            },
        },
    });

    // Set the WETH address in the marketplace contracted if needed.
    const wethAddressFromContract = await read(contractName, 'weth');
    if (wethAddress.toLowerCase() !== wethAddressFromContract.toLowerCase()) {
        await execute(contractName, { from: deployer, log: true }, 'setWeth', wethAddress);
    }

    const paymentTokenFromContract = await read(contractName, 'paymentToken');
    if (magicAddress.toLowerCase() !== paymentTokenFromContract.toLowerCase()) {
        await execute(contractName, { from: deployer, log: true }, 'setPaymentToken', magicAddress);
    }

    // Set the DAO fees (w/o and w/ collection owner) in the contract.
    const feeFromContract = await read(contractName, 'fee');
    const feeWithCollectionOwnerFromContract = await read(contractName, 'feeWithCollectionOwner');
    if (
        feeFromContract.toNumber() !== fee ||
        feeWithCollectionOwnerFromContract.toNumber() !== feeWithCollectionOwner
    ) {
        await execute(contractName, { from: deployer, log: true }, 'setFee', fee, feeWithCollectionOwner);
    }

    const areBidsActive = await read(contractName, 'areBidsActive');
    if (!areBidsActive) {
        await execute(contractName, { from: deployer, log: true }, 'toggleAreBidsActive');
    }

    // Grep the admin role identifier.
    const TREASURE_MARKETPLACE_ADMIN_ROLE = await read(contractName, 'TREASURE_MARKETPLACE_ADMIN_ROLE');

    // If newOwner is not an admin, grant admin role to newOwner.
    if (!(await read(contractName, 'hasRole', TREASURE_MARKETPLACE_ADMIN_ROLE, newOwner))) {
        await execute(
            contractName,
            { from: deployer, log: true },
            'grantRole',
            TREASURE_MARKETPLACE_ADMIN_ROLE,
            newOwner,
        );
    }

    const ProxyAdmin = await deployments.get('ProxyAdmin');

    const entries = [
        { name: 'TreasureMarketplace.address', value: treasureMarketplace.address },
        { name: 'ProxyAdmin.address', value: ProxyAdmin.address },
        {
            name: 'ProxyAdmin.getProxyAdmin("TreasureMarketplace")',
            value: await read('ProxyAdmin', 'getProxyAdmin', treasureMarketplace.address),
        },
        { name: 'ProxyAdmin.owner()', value: await read('ProxyAdmin', 'owner') },
        {
            name: `TreasureMarketplace.hasRole(${newOwner})`,
            value: await read(contractName, 'hasRole', TREASURE_MARKETPLACE_ADMIN_ROLE, newOwner),
        },
        {
            name: `TreasureMarketplace.hasRole(${deployer})`,
            value: await read(contractName, 'hasRole', TREASURE_MARKETPLACE_ADMIN_ROLE, deployer),
        },
        {
            name: `TreasureMarketplace.feeReceipient()`,
            value: await read(contractName, 'feeReceipient'),
        },
        { name: `TreasureMarketplace.fee()`, value: (await read(contractName, 'fee')).toNumber() },
        {
            name: 'TreasureMarketplace.areBidsActive()',
            value: await read(contractName, 'areBidsActive'),
        },
        { name: 'MAGIC address', value: await read(contractName, 'paymentToken') },
        { name: 'WETH address', value: await read(contractName, 'weth') },
    ];

    console.log(`---- ${contractName} Config ----`);
    console.table(entries);
};
export default func;
func.tags = ['treasure-marketplace'];
