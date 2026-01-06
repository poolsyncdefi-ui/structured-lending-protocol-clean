const { expect } = require("chai");
const { ethers } = require("hardhat");

describe("Full Protocol Integration", function() {
  it("Should compile and deploy basic contracts", async function() {
    const [owner] = await ethers.getSigners();
    
    // Test simple deployment
    const ReputationToken = await ethers.getContractFactory("ReputationToken");
    const reputationToken = await ReputationToken.deploy();
    await reputationToken.deployed();
    
    expect(reputationToken.address).to.exist;
    
    const LoanNFT = await ethers.getContractFactory("LoanNFT");
    const loanNFT = await LoanNFT.deploy();
    await loanNFT.deployed();
    
    expect(loanNFT.address).to.exist;
  });
});
