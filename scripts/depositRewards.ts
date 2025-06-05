import { ethers } from 'hardhat';

async function main() {
  const [deployer] = await ethers.getSigners();

  const stakingAddress = '0x96A63229d2ECC59158759e98f286aEbB6Eb6348'; // Staking contract
  const tokenAddress = '0xD733DCcA74fd19dAd6B47216953ea1f34E981dB0';  // $PAPPLE token

  const amountToDeposit = ethers.parseUnits('1000000', 9); // 1M PAPPLE as rewards

  const token = await ethers.getContractAt('ERC20', tokenAddress);

  console.log(`Transferring ${amountToDeposit} tokens to    staking pool...`);
  const tx = await token.transfer(stakingAddress, amountToDeposit);
  console.log(`🟡 Transfer Tx submitted: ${tx.hash}`);
  await tx.wait();  
  console.log('✅ Rewards deposited into staking pool successfully.');
}

main().catch((error) => {
  console.error(error);
  process.exitCode = 1;
});
