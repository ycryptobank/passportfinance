require("@nomicfoundation/hardhat-toolbox");
require('dotenv').config();

/** @type import('hardhat/config').HardhatUserConfig */
module.exports = {
  networks: {
    arb: {
      url: process.env.HARDHAT_ARBITRUM_URL,
      accounts: [process.env.HARDHAT_ARBITRUM_ACCOUNT_PRIVATE_KEY],
    }
  },
  solidity: "0.8.28",
};
