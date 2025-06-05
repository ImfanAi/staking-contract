import { ethers } from 'hardhat';

async function main() {
  const [deployer] = await ethers.getSigners();

  const stakingAddress = '0x96A63229d2ECC59158759e98f286aEbB6Eb6348d'; // Staking contract
  const tokenAddress = '0xD733DCcA74fd19dAd6B47216953ea1f34E981dB0';  // $PAPPLE token

  // 100 000 PAPPLE with 9 decimals
  const amountToFund = ethers.parseUnits('100000', 9);

  // Attach both contracts to the deployer signer so resolveName won’t be called
  const token   = await ethers.getContractAt('ERC20',   tokenAddress, deployer);
  const staking = await ethers.getContractAt('Staking', stakingAddress, deployer);

  // Check if already initialized
  const isOpen = await staking.isOpen();
  if (isOpen) {
    console.log('✅ Staking pool is already initialized. Skipping initialization.');
    return;
  }

  console.log(`Approving ${amountToFund} tokens...`);
  const approveTx = await token.approve(stakingAddress, amountToFund);
  console.log(`🟡 Approval Tx submitted: ${approveTx.hash}`);
  await approveTx.wait();
  console.log('✅ Approved.');

  console.log(`Calling initialize(${amountToFund})...`);
  const tx = await staking.initialize(amountToFund);
  console.log(`🟡 Initialize Tx submitted: ${tx.hash}`);
  await tx.wait();
  console.log('✅ Staking pool initialized successfully.');
}

main().catch((error) => {
  console.error(error);
  process.exitCode = 1;
});
