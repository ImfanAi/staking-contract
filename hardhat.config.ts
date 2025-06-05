import { HardhatUserConfig } from "hardhat/config";
import * as dotenv from "dotenv";
dotenv.config();

import "@nomicfoundation/hardhat-toolbox";
import "@nomicfoundation/hardhat-chai-matchers";

const infuraKey = "99b3813d7d62470987697dfa83991abe";
const privateKey = "b604952f3daaeb6a7295828e80756020e95b8459a074700c2d4c954812bb5540";

const config: HardhatUserConfig = {
  solidity: {
    version: "0.8.24",
    settings: {
      optimizer: {
        enabled: true,
        runs: 100,
      },
      viaIR: true,
    },
  },
  networks: {
    sepolia: {
      url: `https://sepolia.infura.io/v3/${infuraKey}`,
      accounts: [privateKey],
    },
    hardhat: {
      chainId: 31337,
    },
  },
  etherscan: {
    apiKey: {
      sepolia: "ED2NED96C214Y891MR98PZZ1Q45VTFYZRV",
    },
  },
  gasReporter: {
    enabled: true,
  },
  sourcify: {
    enabled: true,
  },
};

export default config;