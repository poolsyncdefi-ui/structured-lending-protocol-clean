const { expect } = require("chai");
const { ethers } = require("hardhat");

describe("GovernanceDAO", function() {
  it("Should deploy", async function() {
    const [owner] = await ethers.getSigners();
    
    const ReputationToken = await ethers.getContractFactory("ReputationToken");
    const reputationToken = await ReputationToken.deploy();
    await reputationToken.deployed();
    
    const GovernanceDAO = await ethers.getContractFactory("GovernanceDAO");
    const governanceDAO = await GovernanceDAO.deploy(
      reputationToken.address,
      owner.address,
      reputationToken.address
    );
    
    await governanceDAO.deployed();
    expect(governanceDAO.address).to.exist;
  });
});