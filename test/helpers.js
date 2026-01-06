// Test helpers
async function mineBlocks(count) {
  for (let i = 0; i < count; i++) {
    await ethers.provider.send("evm_mine");
  }
}

module.exports = {
  mineBlocks
};
