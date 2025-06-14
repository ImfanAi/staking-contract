import { ethers, upgrades } from "hardhat";

async function main() {
  // 1. Pick a deployer
  const [deployer] = await ethers.getSigners();

  console.log("Deploying with:", deployer.address);

  // 2. Get your contract factory
  const Staking = await ethers.getContractFactory("Staking");

  // 3. Deploy a UUPS proxy, passing initialize args
  const initialSupply = ethers.parseUnits("1000000", 18);
  const staking = await upgrades.deployProxy(
    Staking,
    [ process.env.STAKING_TOKEN_ADDRESS, initialSupply ],
    {
      initializer: "initialize",
      kind: "uups"
    }
  );
  await staking.waitForDeployment();

  console.log("✅ Staking proxy deployed to:", staking.target);
  console.log("👉 Implementation at:", await upgrades.erc1967.getImplementationAddress(staking.target as string));
}

main().catch((err) => {
  console.error(err);
  process.exit(1);
});
