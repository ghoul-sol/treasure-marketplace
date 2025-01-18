import { HardhatRuntimeEnvironment } from 'hardhat/types';
import { DeployFunction } from 'hardhat-deploy/types';
import { deploymentArguments } from './config';

const func: DeployFunction = async (hre: HardhatRuntimeEnvironment) => {
    const { deployments, getNamedAccounts } = hre;
    const { deploy, execute, read } = deployments;
    const { deployer } = await getNamedAccounts();

    if (hre.network.name !== 'treasureMainnet' && hre.network.name !== 'treasureTopaz') {
        throw new Error('TreasureMarketplace.deploy.ts is not supported on Mainnet or Topaz');
    }
    const { fee, feeWithCollectionOwner, feeReceipient, wMagicAddress } = deploymentArguments[hre.network.name];
    // Constants for this deploy script.
    const newOwner = deployer;
    const contractName = 'TreasureMarketplace';

    // Deploy/upgrade the Treasure marketplace contract.
    const treasureMarketplace = await deploy(contractName, {
        from: deployer,
        log: true,
        args: [],
        proxy: {
            proxyContract: 'ERC1967Proxy',
            checkABIConflict: false,
            checkProxyAdmin: false,
            proxyArgs: ['{implementation}', '{data}'],

            execute: {
                init: {
                    methodName: 'initialize',
                    args: [fee, feeWithCollectionOwner, feeReceipient, wMagicAddress, wMagicAddress],
                },
            },
            upgradeFunction: {
                methodName: 'upgradeToAndCall',
                upgradeArgs: ['{implementation}', '{data}'],
            },
        },
    });

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

    const entries = [
        { name: 'TreasureMarketplace.address', value: treasureMarketplace.address },
        // { name: 'TreasureMarketplace.owner()', value: await read('TreasureMarketplace', 'owner') },
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
            name: `TreasureMarketplace.feeWithCollectionOwner()`,
            value: (await read(contractName, 'feeWithCollectionOwner')).toNumber(),
        },
        {
            name: 'TreasureMarketplace.areBidsActive()',
            value: await read(contractName, 'areBidsActive'),
        },
        { name: 'MAGIC address', value: await read(contractName, 'paymentToken') },
    ];

    console.log(`---- ${contractName} Config ----`);
    console.table(entries);
};
export default func;
func.tags = ['treasure-marketplace'];
