import { ethers } from "hardhat";

async function main() {
  // Get deployer signer
  const [deployer] = await ethers.getSigners();

  console.log("Deploying USDC token with account:", deployer.address);

  // Get balance for info
  const balance = await ethers.provider.getBalance(deployer.address);
  console.log("Deployer ETH balance:", ethers.formatEther(balance));

  // Get contract factory
  const USDC = await ethers.getContractFactory("usdc");

  // Deploy the contract
  const token = await USDC.deploy();
  await token.waitForDeployment();

  // Print deployed address
  console.log("USDC token deployed to:", token.target); // ethers v6
}

main().catch((error) => {
  console.error(error);
  process.exitCode = 1;
});
