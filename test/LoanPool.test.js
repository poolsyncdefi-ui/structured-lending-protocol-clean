// test/LoanPool.test.js - Suite de tests principale
const { expect } = require("chai");
const { ethers } = require("hardhat");
const { time } = require("@nomicfoundation/hardhat-network-helpers");

describe("PoolSync Protocol", function () {
  let loanPool, riskEngine, criteriaFilter, specialOfferManager;
  let owner, borrower, lender1, lender2, feeCollector;
  let stablecoin;
  
  // Montants en tokens (18 décimales)
  const TOKEN_100 = ethers.parseEther("100");
  const TOKEN_1000 = ethers.parseEther("1000");
  const TOKEN_10000 = ethers.parseEther("10000");
  
  beforeEach(async function () {
    // Récupérer les signers
    [owner, borrower, lender1, lender2, feeCollector] = await ethers.getSigners();
    
    // Déployer un mock stablecoin
    const MockStablecoin = await ethers.getContractFactory("MockERC20");
    stablecoin = await MockStablecoin.deploy("Test USDC", "USDC", 18);
    
    // Déployer RiskEngine avec mocks
    const RiskEngine = await ethers.getContractFactory("RiskEngine");
    riskEngine = await RiskEngine.deploy(ethers.ZeroAddress, ethers.ZeroAddress);
    
    // Déployer LoanPool
    const LoanPool = await ethers.getContractFactory("LoanPool");
    loanPool = await LoanPool.deploy(
      await stablecoin.getAddress(),
      await riskEngine.getAddress(),
      feeCollector.address
    );
    
    // Déployer CriteriaFilter
    const CriteriaFilter = await ethers.getContractFactory("CriteriaFilter");
    criteriaFilter = await CriteriaFilter.deploy(await loanPool.getAddress());
    
    // Déployer SpecialOfferManager
    const SpecialOfferManager = await ethers.getContractFactory("SpecialOfferManager");
    specialOfferManager = await SpecialOfferManager.deploy();
    
    // Configurer les modules
    await loanPool.setExternalModules(
      await riskEngine.getAddress(),
      await criteriaFilter.getAddress(),
      await specialOfferManager.getAddress()
    );
    
    // Autoriser l'owner à créer des pools
    await loanPool.authorizeCreator(owner.address, true);
    await loanPool.authorizeCreator(borrower.address, true);
    
    // Fund les comptes avec stablecoin
    await stablecoin.mint(borrower.address, TOKEN_10000);
    await stablecoin.mint(lender1.address, TOKEN_10000);
    await stablecoin.mint(lender2.address, TOKEN_10000);
    
    // Approve LoanPool pour dépenser
    await stablecoin.connect(borrower).approve(await loanPool.getAddress(), TOKEN_10000);
    await stablecoin.connect(lender1).approve(await loanPool.getAddress(), TOKEN_10000);
    await stablecoin.connect(lender2).approve(await loanPool.getAddress(), TOKEN_10000);
  });
  
  describe("Création et Cycle de Vie d'un Pool", function () {
    it("Devrait créer un pool avec succès", async function () {
      await expect(
        loanPool.connect(borrower).createPool(
          "Projet Écologique Test",
          "Description du projet",
          TOKEN_1000,
          90 * 24 * 60 * 60, // 90 jours
          "Europe",
          true,
          "Renewable Energy",
          "QmTestHash"
        )
      ).to.emit(loanPool, "PoolCreated");
      
      const pool = await loanPool.getPoolDetails(0);
      expect(pool.projectName).to.equal("Projet Écologique Test");
      expect(pool.targetAmount).to.equal(TOKEN_1000);
      expect(pool.borrower).to.equal(borrower.address);
    });
    
    it("Devrait activer un pool créé", async function () {
      await loanPool.connect(borrower).createPool(
        "Projet Test",
        "Description",
        TOKEN_1000,
        30 days,
        "Europe",
        false,
        "Technology",
        "QmTest"
      );
      
      await loanPool.connect(borrower).activatePool(0);
      
      const pool = await loanPool.getPoolDetails(0);
      expect(pool.status).to.equal(1); // PoolStatus.ACTIVE
    });
    
    it("Devrait permettre l'investissement dans un pool actif", async function () {
      // Créer et activer un pool
      await loanPool.connect(borrower).createPool(
        "Projet Test",
        "Description",
        TOKEN_1000,
        30 days,
        "Europe",
        false,
        "Technology",
        "QmTest"
      );
      await loanPool.connect(borrower).activatePool(0);
      
      // Investir
      await expect(
        loanPool.connect(lender1).invest(0, TOKEN_100)
      ).to.emit(loanPool, "InvestmentMade");
      
      const pool = await loanPool.getPoolDetails(0);
      expect(pool.collectedAmount).to.equal(TOKEN_100);
    });
    
    it("Devrait finaliser le financement à 100%", async function () {
      await loanPool.connect(borrower).createPool(
        "Projet Test",
        "Description",
        TOKEN_1000,
        30 days,
        "Europe",
        false,
        "Technology",
        "QmTest"
      );
      await loanPool.connect(borrower).activatePool(0);
      
      // Investir 100%
      await loanPool.connect(lender1).invest(0, TOKEN_1000);
      
      const pool = await loanPool.getPoolDetails(0);
      expect(pool.status).to.equal(3); // PoolStatus.FUNDED -> ONGOING
    });
    
    it("Devrait permettre le remboursement par l'emprunteur", async function () {
      // Créer, financer à 100%
      await loanPool.connect(borrower).createPool(
        "Projet Test",
        "Description",
        TOKEN_100,
        30 days,
        "Europe",
        false,
        "Technology",
        "QmTest"
      );
      await loanPool.connect(borrower).activatePool(0);
      await loanPool.connect(lender1).invest(0, TOKEN_100);
      
      // Rembourser
      const repaymentAmount = TOKEN_105; // 100 + 5% d'intérêt
      await stablecoin.mint(borrower.address, TOKEN_105);
      await stablecoin.connect(borrower).approve(await loanPool.getAddress(), TOKEN_105);
      
      await expect(
        loanPool.connect(borrower).repay(0, TOKEN_105)
      ).to.emit(loanPool, "RepaymentMade");
    });
    
    it("Devrait déclencher un défaut après expiration", async function () {
      await loanPool.connect(borrower).createPool(
        "Projet Test",
        "Description",
        TOKEN_100,
        7 days, // Court pour test
        "Europe",
        false,
        "Technology",
        "QmTest"
      );
      await loanPool.connect(borrower).activatePool(0);
      await loanPool.connect(lender1).invest(0, TOKEN_100);
      
      // Avancer le temps (durée + période de grâce)
      await time.increase(40 days);
      
      await expect(
        loanPool.connect(lender1).triggerDefault(0)
      ).to.emit(loanPool, "DefaultTriggered");
    });
  });
  
  describe("Fonctionnalités Avancées", function () {
    it("Devrait calculer un taux dynamique", async function () {
      await loanPool.connect(borrower).createPool(
        "Projet Test",
        "Description",
        TOKEN_1000,
        30 days,
        "Europe",
        false,
        "Technology",
        "QmTest"
      );
      await loanPool.connect(borrower).activatePool(0);
      
      const rate = await loanPool.getDynamicRate(0);
      expect(rate).to.be.gt(0);
    });
    
    it("Devrait appliquer une offre spéciale", async function () {
      // Créer une offre
      await specialOfferManager.createOffer(
        0, // FLASH
        "Offre Test",
        "Description",
        200, // 2% bonus
        7 days,
        TOKEN_1000,
        [0] // Pool 0 éligible
      );
      
      // Créer et activer pool
      await loanPool.connect(borrower).createPool(
        "Projet Test",
        "Description",
        TOKEN_1000,
        30 days,
        "Europe",
        false,
        "Technology",
        "QmTest"
      );
      await loanPool.connect(borrower).activatePool(0);
      
      // Appliquer offre
      await loanPool.applySpecialOffer(0, 0);
      
      const pool = await loanPool.getPoolDetails(0);
      expect(pool.hasSpecialOffer).to.be.true;
    });
  });
  
  describe("Sécurité et Contrôles d'Accès", function () {
    it("Devrait rejeter les investissements non autorisés", async function () {
      await loanPool.connect(borrower).createPool(
        "Projet Test",
        "Description",
        TOKEN_1000,
        30 days,
        "Europe",
        false,
        "Technology",
        "QmTest"
      );
      
      // Pool pas encore activé
      await expect(
        loanPool.connect(lender1).invest(0, TOKEN_100)
      ).to.be.revertedWith("Pool not active");
    });
    
    it("Devrait rejeter les créations non autorisées", async function () {
      // lender1 n'est pas autorisé à créer
      await expect(
        loanPool.connect(lender1).createPool(
          "Projet Test",
          "Description",
          TOKEN_1000,
          30 days,
          "Europe",
          false,
          "Technology",
          "QmTest"
        )
      ).to.be.revertedWith("Not authorized to create pools");
    });
    
    it("Devrait activer/désactiver le mode pause", async function () {
      await loanPool.setEmergencyPause(true);
      
      await loanPool.connect(borrower).createPool(
        "Projet Test",
        "Description",
        TOKEN_1000,
        30 days,
        "Europe",
        false,
        "Technology",
        "QmTest"
      );
      
      await expect(
        loanPool.connect(borrower).activatePool(0)
      ).to.be.revertedWith("Protocol paused");
    });
  });
});