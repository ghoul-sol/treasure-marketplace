import 'dotenv/config';
import '@nomicfoundation/hardhat-chai-matchers';
import '@nomicfoundation/hardhat-ethers';
import 'hardhat-contract-sizer';
import 'hardhat-deploy';
import 'hardhat-gas-reporter';
import 'solidity-coverage';
import '@matterlabs/hardhat-zksync';
import '@matterlabs/hardhat-zksync-verify';
import { HardhatUserConfig } from 'hardhat/config';
import './hardhat-extra';

// Prod Legacy deployer: 0xd1d943c09b9c3355207ce8c85ab1c4558f6cd851
const prodKmsKey = 'arn:aws:kms:us-east-1:884078395586:key/mrk-646fd3ea71b94861a3ff4f3229d92573';

// Dev Legacy deployer: 0xd9f1e68fd5b9749abc8c87241ddda171baa0d791
const devKmsKey = 'arn:aws:kms:us-west-2:665230337498:key/mrk-5a1618d2c69c4986b414b617fac6bfd1';

const config: HardhatUserConfig = {
    defaultNetwork: 'hardhat',
    networks: {
        hardhat: {
            forking: {
                enabled: process.env.FORKING === 'true',
                url: `${process.env.ARBITRUM_SEPOLIA_URL}`,
                blockNumber: parseInt(process.env.FORKING_BLOCK || '12821000', 10),
            },
            live: false,
            saveDeployments: true,
            tags: ['test', 'local'],
            chainId: 1337,
            zksync: false,
        },
        localhost: {
            url: 'http://localhost:8545',
            chainId: 61337,
            zksync: false,
        },
        eraTestNode: {
            chainId: 260,
            url: 'http://127.0.0.1:8011',
            zksync: true,
        },
        zkSyncSepolia: {
            url: 'https://sepolia.era.zksync.dev',
            kmsKeyId: devKmsKey,
            ethNetwork: 'sepolia', // or a Sepolia RPC endpoint from Infura/Alchemy/Chainstack etc.
            zksync: true,
            verifyURL: 'https://explorer.sepolia.era.zksync.dev/contract_verification',
        },
        treasureTopaz: {
            url: 'https://rpc.topaz.treasure.lol',
            ethNetwork: 'sepolia',
            zksync: true,
            kmsKeyId: devKmsKey,
            verifyURL: 'https://rpc-explorer-verify.topaz.treasure.lol/contract_verification',
        },
        treasureMainnet: {
            url: 'https://rpc.treasure.lol',
            ethNetwork: 'mainnet',
            zksync: true,
            kmsKeyId: prodKmsKey,
            verifyURL: 'https://rpc-explorer-verify.treasure.lol/contract_verification',
        },
    },
    zksolc: {
        version: '1.5.7',
        settings: {},
    },
    solidity: {
        compilers: [
            {
                version: '0.8.28',
                settings: {
                    optimizer: {
                        enabled: true,
                        runs: 200,
                    },
                },
            },
            {
                version: '0.7.6',
                settings: {
                    optimizer: {
                        enabled: true,
                        runs: 999999,
                    },
                },
            },
        ],
    },
    namedAccounts: {
        deployer: 0,
        staker1: 1,
        staker2: 2,
        staker3: 3,
        hacker: 4,
        admin: 5,
    },
    mocha: {
        timeout: 60000,
    },
    gasReporter: {
        currency: 'USD',
        enabled: false,
    },
    paths: {
        artifacts: 'artifacts',
        cache: 'cache',
        deploy: 'deploy/arbitrum',
        deployments: 'deployments',
        imports: 'imports',
        sources: 'contracts',
        tests: 'test',
    },
    contractSizer: {
        runOnCompile: true,
    },
    etherscan: {
        apiKey: process.env.ETHERSCAN_API_KEY,
        customChains: [
            {
                network: 'arbitrumNova',
                chainId: 42170,
                urls: {
                    apiURL: 'https://api-nova.arbiscan.io/api',
                    browserURL: 'https://nova.arbiscan.io',
                },
            },
            {
                network: 'arbitrumSepolia',
                chainId: 421614,
                urls: {
                    apiURL: 'https://api-sepolia.arbiscan.io/api',
                    browserURL: 'https://sepolia.arbiscan.io',
                },
            },
        ],
    },
};

export default config;
