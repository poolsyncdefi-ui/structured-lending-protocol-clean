// test/mocks/MockERC20.test.js
const { expect } = require("chai");
const { ethers } = require("hardhat");

describe("MockERC20", function () {
  let mockToken;
  let owner, user1, user2;
  
  beforeEach(async function () {
    [owner, user1, user2] = await ethers.getSigners();
    
    const MockERC20 = await ethers.getContractFactory("MockERC20");
    mockToken = await MockERC20.deploy("Mock USDC", "mUSDC", 6);
  });
  
  describe("Déploiement", function () {
    it("Devrait avoir le bon nom et symbole", async function () {
      expect(await mockToken.name()).to.equal("Mock USDC");
      expect(await mockToken.symbol()).to.equal("mUSDC");
      expect(await mockToken.decimals()).to.equal(6);
    });
    
    it("Devrait mint des tokens initiaux au owner", async function () {
      const balance = await mockToken.balanceOf(owner.address);
      expect(balance).to.equal(1000000 * 10 ** 6);
    });
  });
  
  describe("Fonctions Mint/Burn", function () {
    it("Devrait permettre au owner de mint", async function () {
      await mockToken.mint(user1.address, 1000 * 10 ** 6);
      expect(await mockToken.balanceOf(user1.address)).to.equal(1000 * 10 ** 6);
    });
    
    it("Ne devrait pas permettre aux non-owners de mint", async function () {
      await expect(
        mockToken.connect(user1).mint(user2.address, 1000 * 10 ** 6)
      ).to.be.revertedWith("MockERC20: Only owner can mint");
    });
    
    it("Devrait permettre au owner de burn", async function () {
      // D'abord mint
      await mockToken.mint(user1.address, 1000 * 10 ** 6);
      
      // Puis burn
      await mockToken.burn(user1.address, 500 * 10 ** 6);
      expect(await mockToken.balanceOf(user1.address)).to.equal(500 * 10 ** 6);
    });
  });
  
  describe("Batch Mint", function () {
    it("Devrait mint en batch", async function () {
      const recipients = [user1.address, user2.address];
      const amounts = [1000 * 10 ** 6, 2000 * 10 ** 6];
      
      await mockToken.batchMint(recipients, amounts);
      
      expect(await mockToken.balanceOf(user1.address)).to.equal(1000 * 10 ** 6);
      expect(await mockToken.balanceOf(user2.address)).to.equal(2000 * 10 ** 6);
    });
    
    it("Ne devrait pas mint en batch avec des tableaux de tailles différentes", async function () {
      const recipients = [user1.address, user2.address];
      const amounts = [1000 * 10 ** 6];
      
      await expect(
        mockToken.batchMint(recipients, amounts)
      ).to.be.revertedWith("MockERC20: Arrays length mismatch");
    });
  });
  
  describe("Transfert de propriété", function () {
    it("Devrait transférer la propriété", async function () {
      await mockToken.transferOwnership(user1.address);
      expect(await mockToken.owner()).to.equal(user1.address);
    });
    
    it("Le nouveau owner devrait pouvoir mint", async function () {
      await mockToken.transferOwnership(user1.address);
      await mockToken.connect(user1).mint(user2.address, 1000 * 10 ** 6);
      expect(await mockToken.balanceOf(user2.address)).to.equal(1000 * 10 ** 6);
    });
  });
});