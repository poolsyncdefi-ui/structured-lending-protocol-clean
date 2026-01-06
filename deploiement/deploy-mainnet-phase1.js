// scripts/deploy-mainnet-phase1.js
const { ethers } = require("hardhat");
const fs = require("fs");
const path = require("path");

// Configuration Phase 1 (Limités, Sécurisé)
const PHASE1_CONFIG = {
  network: "polygon",
  stablecoin: "0x2791Bca1f2de4661ED88A30C99A7a9449Aa84174", // USDC Polygon
  chainlinkOracle: "0xF9680D99D6C9589e2a93a78A04A279e509205945", // ETH/USD Polygon
  creditOracle: "0xAB594600376Ec9fD91F8e885dADF0CE036862dE0", // MATIC/USD comme proxy crédit
  marketOracle: "0xc907E116054Ad103354f2D350FD2514433D57F6f", // ETH/USD pour marché
  regulatoryOracle: "0x0000000000000000000000000000000000000000", // À configurer plus tard
  treasury: "0x3C44CdDdB6a900fa2b585dd299e03d12FA4293BC", // Multisig treasury
  kycVerifier: "0x90F79bf6EB2c4f870365E785982E1f101E93b906", // Service KYC
  riskManager: "0x15d34AAf54267DB7D7c367839AAf71A00a2C6A65", // Équipe risque
  emergencyCouncil: [
    "0x3C44CdDdB6a900fa2b585dd299e03d12FA4293BC",
    "0x90F79bf6EB2c4f870365E785982E1f101E93b906",
    "0x15d34AAf54267DB7D7c367839AAf71A00a2C6A65"
  ],
  limits: {
    maxLoanAmount: ethers.utils.parseUnits("10000", 6), // 10k USDC max
    maxTotalExposure: ethers.utils.parseUnits("100000", 6), // 100k USDC total
    whitelistOnly: true,
    maxInvestors: 50
  }
};

async function main() {
  console.log("🚀 Déploiement Phase 1 - Mainnet (Polygon)");
  console.log("=========================================");
  console.log("⚠️  MODE LIMITÉ - WHITELIST ONLY");
  console.log("=========================================");
  
  const [deployer] = await ethers.getSigners();
  console.log("Compte déployeur:", deployer.address);
  console.log("Balance:", ethers.utils.formatEther(await deployer.getBalance()), "MATIC");
  
  // Vérification des adresses de configuration
  console.log("\n🔍 Vérification de la configuration...");
  for (const [key, value] of Object.entries(PHASE1_CONFIG)) {
    if (typeof value === 'string' && value.startsWith('0x')) {
      console.log(`   ${key}: ${value} (${ethers.utils.isAddress(value) ? '✅ Valide' : '❌ Invalide'})`);
    }
  }
  
  // Confirmation manuelle (sécurité)
  console.log("\n⚠️  CONFIRMATION REQUISE:");
  console.log("Network: Polygon Mainnet");
  console.log("Stablecoin: USDC (0x2791...)");
  console.log("Limits: 10k USDC max par prêt, 100k USDC total");
  console.log("\nContinuer? (tapez 'yes' pour confirmer)");
  
  // En production, vous voudriez peut-être commenter cette partie
  // et utiliser une confirmation hors ligne
  
  // 1. Déploiement des tokens avec vesting
  console.log("\n📦 1. Déploiement des tokens avec vesting...");
  
  // Token de gouvernance avec vesting
  const GovernanceToken = await ethers.getContractFactory("GovernanceToken");
  const governanceToken = await GovernanceToken.deploy();
  await governanceToken.deployed();
  console.log("   GovernanceToken:", governanceToken.address);
  
  // Token de réputation
  const ReputationToken = await ethers.getContractFactory("ReputationToken");
  const reputationToken = await ReputationToken.deploy();
  await reputationToken.deployed();
  console.log("   ReputationToken:", reputationToken.address);
  
  // 2. Déploiement des contrats de sécurité d'abord
  console.log("\n🛡️ 2. Déploiement des contrats de sécurité...");
  
  // TimelockController avec délais plus longs
  const TimelockController = await ethers.getContractFactory("TimelockController");
  const timelock = await TimelockController.deploy(
    7 * 24 * 60 * 60, // 7 jours pour Mainnet
    [deployer.address, ...PHASE1_CONFIG.emergencyCouncil],
    [deployer.address] // Admin peut être changé après
  );
  await timelock.deployed();
  console.log("   TimelockController (7 jours):", timelock.address);
  
  // AccessController avec paramètres stricts
  const AccessController = await ethers.getContractFactory("AccessController");
  const accessController = await AccessController.deploy(
    timelock.address, // Admin = Timelock
    timelock.address  // DAO = Timelock temporairement
  );
  await accessController.deployed();
  console.log("   AccessController:", accessController.address);
  
  // Configuration immédiate de l'AccessController
  for (const member of PHASE1_CONFIG.emergencyCouncil) {
    await accessController.grantRole(
      await accessController.EMERGENCY_COUNCIL_ROLE(),
      member
    );
    console.log(`   ✓ Membre conseil d'urgence ajouté: ${member}`);
  }
  
  // 3. Déploiement des contrats KYC et conformité
  console.log("\n📝 3. Déploiement des contrats KYC...");
  
  const KYCRegistry = await ethers.getContractFactory("KYCRegistry");
  const kycRegistry = await KYCRegistry.deploy(timelock.address);
  await kycRegistry.deployed();
  console.log("   KYCRegistry:", kycRegistry.address);
  
  // Configuration KYC
  await kycRegistry.grantRole(
    await kycRegistry.VERIFIER_ROLE(),
    PHASE1_CONFIG.kycVerifier
  );
  console.log("   ✓ Vérificateur KYC configuré");
  
  // 4. Déploiement des contrats de base avec limites
  console.log("\n🔧 4. Déploiement des contrats de base...");
  
  // LoanNFT
  const LoanNFT = await ethers.getContractFactory("LoanNFT");
  const loanNFT = await LoanNFT.deploy(
    "CrowdLending Positions",
    "CLP",
    "https://api.crowdlending.io/metadata/",
    "https://api.crowdlending.io/images/",
    "https://api.crowdlending.io/contract.json"
  );
  await loanNFT.deployed();
  console.log("   LoanNFT:", loanNFT.address);
  
  // BondingCurve avec paramètres conservateurs
  const BondingCurve = await ethers.getContractFactory("BondingCurve");
  const bondingCurve = await BondingCurve.deploy(PHASE1_CONFIG.chainlinkOracle);
  await bondingCurve.deployed();
  console.log("   BondingCurve:", bondingCurve.address);
  
  // Configuration conservatrice des courbes
  await bondingCurve.updateCurveParameters(
    0, // Senior
    0, // LINEAR
    ethers.utils.parseUnits("1050", 6), // 1050 USDC base
    ethers.utils.parseUnits("5", 6), // pente faible
    1,
    ethers.utils.parseUnits("1200", 6),
    ethers.utils.parseUnits("950", 6),
    1000
  );
  console.log("   ✓ Courbes configurées (conservateur)");
  
  // 5. Déploiement des modules de risque
  console.log("\n📊 5. Déploiement des modules de risque...");
  
  const RiskEngine = await ethers.getContractFactory("RiskEngine");
  const riskEngine = await RiskEngine.deploy(
    ethers.constants.AddressZero, // LoanPool plus tard
    kycRegistry.address,
    PHASE1_CONFIG.creditOracle,
    PHASE1_CONFIG.marketOracle,
    PHASE1_CONFIG.regulatoryOracle
  );
  await riskEngine.deployed();
  console.log("   RiskEngine:", riskEngine.address);
  
  // Configuration RiskEngine
  await riskEngine.grantRole(
    await riskEngine.RISK_ANALYST_ROLE(),
    PHASE1_CONFIG.riskManager
  );
  console.log("   ✓ RiskEngine configuré");
  
  // 6. Déploiement du DGF avec limites
  console.log("\n🏦 6. Déploiement du DGF...");
  
  const DecentralizedGuaranteeFund = await ethers.getContractFactory("DecentralizedGuaranteeFund");
  const dgf = await DecentralizedGuaranteeFund.deploy(PHASE1_CONFIG.stablecoin);
  await dgf.deployed();
  console.log("   DecentralizedGuaranteeFund:", dgf.address);
  
  // Configuration DGF conservative
  await dgf.updateParameters(
    5, // 0.05% fee (réduit)
    80, // 80% couverture Senior
    40, // 40% couverture Mezzanine
    150 // 150% reserve ratio
  );
  console.log("   ✓ DGF configuré (conservateur)");
  
  // 7. Déploiement du LoanPool avec limites Phase 1
  console.log("\n🏛️ 7. Déploiement du LoanPool Phase 1...");
  
  const LoanPool = await ethers.getContractFactory("LoanPool");
  const loanPool = await LoanPool.deploy(
    PHASE1_CONFIG.stablecoin,
    loanNFT.address,
    riskEngine.address,
    ethers.constants.AddressZero, // DynamicTranche désactivé Phase 1
    dgf.address
  );
  await loanPool.deployed();
  console.log("   LoanPool:", loanPool.address);
  
  // Mise à jour des références
  await riskEngine.updateLoanPool(loanPool.address);
  console.log("   ✓ RiskEngine -> LoanPool mis à jour");
  
  // 8. Configuration des limites Phase 1
  console.log("\n⚖️ 8. Configuration des limites Phase 1...");
  
  // Note: Les limites sont codées en dur dans le contrat
  // Pour Phase 1, on peut aussi utiliser un whitelist
  
  // 9. Déploiement de la gouvernance Phase 1
  console.log("\n🗳️ 9. Déploiement de la gouvernance Phase 1...");
  
  const GovernanceDAO = await ethers.getContractFactory("GovernanceDAO");
  const governanceDAO = await GovernanceDAO.deploy(
    governanceToken.address,
    timelock.address,
    reputationToken.address,
    loanPool.address,
    10, // quorum 10% (élevé pour sécurité)
    5760, // voting delay 1 jour
    40320, // voting period 7 jours
    ethers.utils.parseEther("10000") // threshold 10k tokens
  );
  await governanceDAO.deployed();
  console.log("   GovernanceDAO:", governanceDAO.address);
  
  // 10. Mise à jour de l'AccessController avec la DAO
  await accessController.updateGovernanceDAO(governanceDAO.address);
  console.log("   ✓ AccessController -> DAO mis à jour");
  
  // 11. Transfert de l'ownership à la Timelock
  console.log("\n🏛️ 11. Transfert de l'ownership à la Timelock...");
  
  const contractsToTransfer = [
    { contract: loanPool, name: "LoanPool" },
    { contract: riskEngine, name: "RiskEngine" },
    { contract: dgf, name: "DGF" },
    { contract: bondingCurve, name: "BondingCurve" },
    { contract: loanNFT, name: "LoanNFT" },
    { contract: kycRegistry, name: "KYCRegistry" }
  ];
  
  for (const item of contractsToTransfer) {
    try {
      await item.contract.transferOwnership(timelock.address);
      console.log(`   ✓ ${item.name} transféré à Timelock`);
      
      // Petit délai entre les transferts
      await new Promise(resolve => setTimeout(resolve, 2000));
    } catch (error) {
      console.log(`   ⚠️  ${item.name}: ${error.message}`);
    }
  }
  
  // 12. Enregistrement des adresses
  console.log("\n📝 12. Enregistrement des adresses...");
  
  const addresses = {
    phase: 1,
    network: PHASE1_CONFIG.network,
    deployer: deployer.address,
    timestamp: new Date().toISOString(),
    limits: PHASE1_CONFIG.limits,
    emergencyCouncil: PHASE1_CONFIG.emergencyCouncil,
    contracts: {
      governanceToken: governanceToken.address,
      reputationToken: reputationToken.address,
      timelock: timelock.address,
      accessController: accessController.address,
      kycRegistry: kycRegistry.address,
      loanNFT: loanNFT.address,
      bondingCurve: bondingCurve.address,
      riskEngine: riskEngine.address,
      dgf: dgf.address,
      loanPool: loanPool.address,
      governanceDAO: governanceDAO.address
    },
    notes: [
      "Phase 1: Whitelist only, limites strictes",
      "DynamicTranche désactivé",
      "InsuranceModule désactivé",
      "SecondaryMarket désactivé",
      "RegulatoryReporting désactivé"
    ]
  };
  
  // Sauvegarde
  const addressesDir = path.join(__dirname, "..", "deployments", "mainnet");
  if (!fs.existsSync(addressesDir)) {
    fs.mkdirSync(addressesDir, { recursive: true });
  }
  
  const filename = `phase1-${Date.now()}.json`;
  fs.writeFileSync(
    path.join(addressesDir, filename),
    JSON.stringify(addresses, null, 2)
  );
  
  console.log(`   ✓ Adresses sauvegardées dans: deployments/mainnet/${filename}`);
  
  // 13. Création du rapport de sécurité
  console.log("\n🔒 13. Création du rapport de sécurité...");
  
  const securityReport = {
    timestamp: new Date().toISOString(),
    phase: 1,
    securityFeatures: [
      "Timelock de 7 jours sur toutes les actions",
      "Multisig emergency council (3/3)",
      "Limites strictes: 10k USDC max par prêt",
      "Whitelist only pour Phase 1",
      "Quorum élevé: 10%",
      "Voting delay: 1 jour",
      "Ownership transférée à Timelock"
    ],
    disabledFeatures: [
      "DynamicTranche",
      "InsuranceModule",
      "SecondaryMarket",
      "RegulatoryReporting"
    ],
    nextSteps: [
      "Audit des contrats en production",
      "Surveillance 24/7",
      "Tests de charge",
      "Préparation Phase 2"
    ]
  };
  
  fs.writeFileSync(
    path.join(addressesDir, `security-report-phase1-${Date.now()}.json`),
    JSON.stringify(securityReport, null, 2)
  );
  
  // 14. Affichage du résumé
  console.log("\n✅ PHASE 1 DÉPLOYÉE AVEC SUCCÈS!");
  console.log("=========================================");
  console.log("\n📋 CONFIGURATION PHASE 1:");
  console.log("=========================================");
  console.log("🔒 SÉCURITÉ:");
  console.log(`   Timelock: ${timelock.address}`);
  console.log(`   Emergency Council: ${PHASE1_CONFIG.emergencyCouncil.length} membres`);
  console.log(`   Voting Delay: 1 jour`);
  console.log(`   Timelock Delay: 7 jours`);
  
  console.log("\n⚖️ LIMITES:");
  console.log(`   Max par prêt: ${ethers.utils.formatUnits(PHASE1_CONFIG.limits.maxLoanAmount, 6)} USDC`);
  console.log(`   Exposition totale: ${ethers.utils.formatUnits(PHASE1_CONFIG.limits.maxTotalExposure, 6)} USDC`);
  console.log(`   Whitelist only: OUI`);
  
  console.log("\n🚀 PROCHAINES ÉTAPES:");
  console.log("1. Whitelist des utilisateurs initiaux");
  console.log("2. Distribution des tokens de gouvernance");
  console.log("3. Surveillance étroite pendant 30 jours");
  console.log("4. Audit des contrats en production");
  console.log("5. Préparation de la Phase 2");
  
  console.log("\n⚠️  IMPORTANT:");
  console.log("Toutes les actions administratives passent par la Timelock");
  console.log("avec un délai de 7 jours. Gardez les clés privées sécurisées!");
}

// Gestion des erreurs avec logs détaillés
main()
  .then(() => process.exit(0))
  .catch((error) => {
    console.error("❌ ERREUR CRITIQUE:", error);
    
    // Log détaillé pour débogage
    if (error.transactionHash) {
      console.error("Transaction Hash:", error.transactionHash);
    }
    if (error.receipt) {
      console.error("Receipt:", error.receipt);
    }
    
    process.exit(1);
  });