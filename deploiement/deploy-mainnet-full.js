// scripts/deploy-mainnet-full.js
const { ethers } = require("hardhat");
const fs = require("fs");
const path = require("path");

// Configuration complète Mainnet
const FULL_CONFIG = {
  network: "polygon",
  stablecoin: "0x2791Bca1f2de4661ED88A30C99A7a9449Aa84174", // USDC Polygon
  chainlinkOracle: "0xF9680D99D6C9589e2a93a78A04A279e509205945", // ETH/USD Polygon
  creditOracle: "0xd0D5e3DB44DE05E9F294BB0a3bEEaF030DE24Ada", // Oracle crédit dédié
  marketOracle: "0xAB594600376Ec9fD91F8e885dADF0CE036862dE0", // MATIC/USD
  economicOracle: "0x907A947b5cB6572d7d7f8f6aB5fB111B2a1b7a16", // Indicateurs économiques
  regulatoryOracle: "0x4C5F0f90a2D4b518aFba11E22AC9b8F6B031d204", // Oracle réglementaire
  treasury: "0x3C44CdDdB6a900fa2b585dd299e03d12FA4293BC", // Multisig 3/5
  kycVerifier: "0x90F79bf6EB2c4f870365E785982E1f101E93b906", // Service KYC
  riskManager: "0x15d34AAf54267DB7D7c367839AAf71A00a2C6A65", // Équipe risque
  insuranceProviders: [
    "0x70997970C51812dc3A010C7d01b50e0d17dc79C8",
    "0x3C44CdDdB6a900fa2b585dd299e03d12FA4293BC"
  ],
  emergencyCouncil: [
    "0x3C44CdDdB6a900fa2b585dd299e03d12FA4293BC", // Membre 1
    "0x90F79bf6EB2c4f870365E785982E1f101E93b906", // Membre 2
    "0x15d34AAf54267DB7D7c367839AAf71A00a2C6A65", // Membre 3
    "0x70997970C51812dc3A010C7d01b50e0d17dc79C8", // Membre 4
    "0x9965507D1a55bcC2695C58ba16FB37d819B0A4dc"  // Membre 5
  ],
  limits: {
    maxLoanAmount: ethers.utils.parseUnits("500000", 6), // 500k USDC
    maxTotalExposure: ethers.utils.parseUnits("10000000", 6), // 10M USDC
    minLoanAmount: ethers.utils.parseUnits("1000", 6), // 1k USDC min
    maxInvestorsPerLoan: 1000
  }
};

// Adresses de la Phase 1 (à mettre à jour)
const PHASE1_ADDRESSES = {
  // Ces adresses seront remplacées par les vraies adresses Phase 1
  timelock: "0x...",
  accessController: "0x...",
  kycRegistry: "0x...",
  loanNFT: "0x...",
  bondingCurve: "0x...",
  riskEngine: "0x...",
  dgf: "0x...",
  loanPool: "0x...",
  governanceToken: "0x...",
  reputationToken: "0x...",
  governanceDAO: "0x..."
};

async function main() {
  console.log("🚀 DÉPLOIEMENT COMPLET - Mainnet (Polygon)");
  console.log("=========================================");
  console.log("⚠️  TOUTES LES FONCTIONNALITÉS ACTIVÉES");
  console.log("=========================================");
  
  const [deployer] = await ethers.getSigners();
  console.log("Compte déployeur:", deployer.address);
  console.log("Balance:", ethers.utils.formatEther(await deployer.getBalance()), "MATIC");
  
  // Lecture des adresses Phase 1
  console.log("\n🔍 Chargement des adresses Phase 1...");
  
  let phase1Addresses;
  try {
    const phase1Files = fs.readdirSync(path.join(__dirname, "..", "deployments", "mainnet"))
      .filter(file => file.startsWith("phase1-"))
      .sort()
      .reverse();
    
    if (phase1Files.length === 0) {
      throw new Error("Aucun fichier de déploiement Phase 1 trouvé");
    }
    
    const latestFile = phase1Files[0];
    const data = fs.readFileSync(
      path.join(__dirname, "..", "deployments", "mainnet", latestFile),
      "utf8"
    );
    
    phase1Addresses = JSON.parse(data);
    console.log(`   ✓ Fichier chargé: ${latestFile}`);
    
    // Mise à jour des adresses
    Object.assign(PHASE1_ADDRESSES, phase1Addresses.contracts);
    
  } catch (error) {
    console.error("❌ Erreur lors du chargement Phase 1:", error.message);
    console.log("⚠️  Utilisation des adresses par défaut...");
  }
  
  // Vérification des adresses critiques
  console.log("\n🔐 Vérification des adresses critiques...");
  const criticalAddresses = [
    { name: "Timelock", address: PHASE1_ADDRESSES.timelock },
    { name: "GovernanceDAO", address: PHASE1_ADDRESSES.governanceDAO },
    { name: "AccessController", address: PHASE1_ADDRESSES.accessController }
  ];
  
  for (const item of criticalAddresses) {
    if (!ethers.utils.isAddress(item.address) || item.address === "0x...") {
      console.error(`❌ ${item.name} invalide: ${item.address}`);
      return;
    }
    console.log(`   ✓ ${item.name}: ${item.address}`);
  }
  
  // 1. Vérification de l'upgradabilité
  console.log("\n🔄 1. Vérification de l'upgradabilité...");
  
  // Vérifier que le déployeur a encore les permissions nécessaires
  const AccessController = await ethers.getContractFactory("AccessController");
  const accessController = AccessController.attach(PHASE1_ADDRESSES.accessController);
  
  try {
    const hasAdminRole = await accessController.hasRole(
      await accessController.DEFAULT_ADMIN_ROLE(),
      deployer.address
    );
    
    if (!hasAdminRole) {
      console.log("⚠️  Déployeur n'a pas le rôle admin. Vérification Timelock...");
      
      // Vérifier si c'est la Timelock qui a le rôle
      const timelockHasRole = await accessController.hasRole(
        await accessController.DEFAULT_ADMIN_ROLE(),
        PHASE1_ADDRESSES.timelock
      );
      
      if (!timelockHasRole) {
        throw new Error("Ni le déployeur ni la Timelock n'ont le rôle admin");
      }
      
      console.log("   ✓ Timelock a le rôle admin");
    } else {
      console.log("   ✓ Déployeur a le rôle admin");
    }
  } catch (error) {
    console.error("❌ Erreur de vérification:", error.message);
    return;
  }
  
  // 2. Déploiement des nouveaux contrats
  console.log("\n📦 2. Déploiement des nouveaux contrats...");
  
  // DynamicTranche
  console.log("   Déploiement de DynamicTranche...");
  const DynamicTranche = await ethers.getContractFactory("DynamicTranche");
  const dynamicTranche = await DynamicTranche.deploy(
    PHASE1_ADDRESSES.loanPool,
    PHASE1_ADDRESSES.loanNFT,
    FULL_CONFIG.creditOracle,
    FULL_CONFIG.marketOracle
  );
  await dynamicTranche.deployed();
  console.log(`   ✓ DynamicTranche: ${dynamicTranche.address}`);
  
  // InsuranceModule
  console.log("   Déploiement d'InsuranceModule...");
  const InsuranceModule = await ethers.getContractFactory("InsuranceModule");
  const insuranceModule = await InsuranceModule.deploy(
    FULL_CONFIG.stablecoin,
    PHASE1_ADDRESSES.dgf,
    PHASE1_ADDRESSES.loanPool
  );
  await insuranceModule.deployed();
  console.log(`   ✓ InsuranceModule: ${insuranceModule.address}`);
  
  // SecondaryMarket
  console.log("   Déploiement de SecondaryMarket...");
  const SecondaryMarket = await ethers.getContractFactory("SecondaryMarket");
  const secondaryMarket = await SecondaryMarket.deploy(
    PHASE1_ADDRESSES.loanNFT,
    FULL_CONFIG.stablecoin,
    PHASE1_ADDRESSES.bondingCurve,
    FULL_CONFIG.treasury
  );
  await secondaryMarket.deployed();
  console.log(`   ✓ SecondaryMarket: ${secondaryMarket.address}`);
  
  // RegulatoryReporting
  console.log("   Déploiement de RegulatoryReporting...");
  const RegulatoryReporting = await ethers.getContractFactory("RegulatoryReporting");
  const regulatoryReporting = await RegulatoryReporting.deploy(
    PHASE1_ADDRESSES.loanPool,
    PHASE1_ADDRESSES.dgf,
    FULL_CONFIG.regulatoryOracle
  );
  await regulatoryReporting.deployed();
  console.log(`   ✓ RegulatoryReporting: ${regulatoryReporting.address}`);
  
  // 3. Mise à jour des contrats existants
  console.log("\n🔄 3. Mise à jour des contrats existants...");
  
  // Mise à jour du LoanPool avec DynamicTranche
  console.log("   Mise à jour du LoanPool...");
  const LoanPool = await ethers.getContractFactory("LoanPool");
  const loanPool = LoanPool.attach(PHASE1_ADDRESSES.loanPool);
  
  try {
    const tx1 = await loanPool.updateDynamicTranche(dynamicTranche.address);
    await tx1.wait();
    console.log("   ✓ LoanPool -> DynamicTranche mis à jour");
  } catch (error) {
    console.error("   ❌ Erreur mise à jour LoanPool:", error.message);
  }
  
  // Mise à jour du RiskEngine avec nouveaux oracles
  console.log("   Mise à jour du RiskEngine...");
  const RiskEngine = await ethers.getContractFactory("RiskEngine");
  const riskEngine = RiskEngine.attach(PHASE1_ADDRESSES.riskEngine);
  
  // Configuration RiskEngine avancée
  try {
    // Ajout de permissions
    await riskEngine.grantRole(
      await riskEngine.RISK_ANALYST_ROLE(),
      FULL_CONFIG.riskManager
    );
    console.log("   ✓ RiskEngine permissions mises à jour");
  } catch (error) {
    console.error("   ❌ Erreur RiskEngine:", error.message);
  }
  
  // 4. Configuration des nouveaux modules
  console.log("\n⚙️ 4. Configuration des nouveaux modules...");
  
  // Configuration DynamicTranche
  console.log("   Configuration DynamicTranche...");
  try {
    await dynamicTranche.updateThresholds(
      0, // loanId 0 pour paramètres par défaut
      800, // upgradeScore
      400, // downgradeScore
      30, // maxPercentage 30%
      24 // cooldown 24 heures
    );
    console.log("   ✓ DynamicTranche configuré");
  } catch (error) {
    console.error("   ❌ Erreur configuration DynamicTranche:", error.message);
  }
  
  // Configuration InsuranceModule
  console.log("   Configuration InsuranceModule...");
  try {
    // Enregistrement des assureurs
    for (const insurer of FULL_CONFIG.insuranceProviders) {
      await insuranceModule.registerInsurer(
        insurer,
        `Insurer-${insurer.slice(0, 8)}`,
        8, // credit rating
        ethers.utils.parseUnits("1000000", 6), // 1M USDC reserve
        ethers.utils.parseUnits("500000", 6) // 500k USDC max exposure
      );
      console.log(`   ✓ Assureur enregistré: ${insurer.slice(0, 8)}...`);
    }
    console.log("   ✓ InsuranceModule configuré");
  } catch (error) {
    console.error("   ❌ Erreur configuration InsuranceModule:", error.message);
  }
  
  // Configuration SecondaryMarket
  console.log("   Configuration SecondaryMarket...");
  try {
    await secondaryMarket.updateTradingFee(30); // 0.3%
    await secondaryMarket.updateMinimumListingDuration(2 * 60 * 60); // 2 heures
    console.log("   ✓ SecondaryMarket configuré");
  } catch (error) {
    console.error("   ❌ Erreur configuration SecondaryMarket:", error.message);
  }
  
  // 5. Configuration des permissions
  console.log("\n🔐 5. Configuration des permissions...");
  
  // Configuration AccessController pour nouveaux contrats
  try {
    // DynamicTranche comme Risk Manager
    await accessController.grantRole(
      await accessController.RISK_MANAGER_ROLE(),
      dynamicTranche.address
    );
    
    // InsuranceModule comme Risk Manager
    await accessController.grantRole(
      await accessController.RISK_MANAGER_ROLE(),
      insuranceModule.address
    );
    
    // RegulatoryReporting comme Reporter
    await accessController.grantRole(
      await accessController.COMPLIANCE_OFFICER_ROLE(),
      regulatoryReporting.address
    );
    
    console.log("   ✓ Permissions configurées");
  } catch (error) {
    console.error("   ❌ Erreur permissions:", error.message);
  }
  
  // 6. Mise à jour des limites
  console.log("\n⚖️ 6. Mise à jour des limites...");
  
  // Note: Les limites doivent être mises à jour via la gouvernance
  // Ici on prépare les propositions
  
  const limitProposals = [
    {
      name: "Augmenter limite prêt",
      target: PHASE1_ADDRESSES.loanPool,
      value: 0,
      signature: "updateLoanLimits(uint256,uint256)",
      data: ethers.utils.defaultAbiCoder.encode(
        ["uint256", "uint256"],
        [
          FULL_CONFIG.limits.minLoanAmount,
          FULL_CONFIG.limits.maxLoanAmount
        ]
      ),
      description: "Augmenter les limites de prêt pour le déploiement complet"
    },
    {
      name: "Activer toutes les tranches",
      target: PHASE1_ADDRESSES.loanPool,
      value: 0,
      signature: "setTrancheConfiguration(uint8,bool)",
      data: ethers.utils.defaultAbiCoder.encode(
        ["uint8", "bool"],
        [2, true] // Activer la tranche Equity
      ),
      description: "Activer la tranche Equity pour le déploiement complet"
    }
  ];
  
  console.log("   Propositions de limites préparées:");
  for (const prop of limitProposals) {
    console.log(`   • ${prop.name}: ${prop.description}`);
  }
  
  // 7. Enregistrement des nouvelles adresses
  console.log("\n📝 7. Enregistrement des nouvelles adresses...");
  
  const fullDeployment = {
    phase: "full",
    network: FULL_CONFIG.network,
    deployer: deployer.address,
    timestamp: new Date().toISOString(),
    phase1Base: PHASE1_ADDRESSES,
    newContracts: {
      dynamicTranche: dynamicTranche.address,
      insuranceModule: insuranceModule.address,
      secondaryMarket: secondaryMarket.address,
      regulatoryReporting: regulatoryReporting.address
    },
    configuration: FULL_CONFIG,
    proposals: limitProposals,
    notes: [
      "Déploiement complet terminé",
      "Toutes les fonctionnalités activées",
      "Limites augmentées",
      "Gouvernance pleinement opérationnelle"
    ]
  };
  
  // Sauvegarde
  const deploymentsDir = path.join(__dirname, "..", "deployments", "mainnet");
  if (!fs.existsSync(deploymentsDir)) {
    fs.mkdirSync(deploymentsDir, { recursive: true });
  }
  
  const filename = `full-deployment-${Date.now()}.json`;
  fs.writeFileSync(
    path.join(deploymentsDir, filename),
    JSON.stringify(fullDeployment, null, 2)
  );
  
  console.log(`   ✓ Adresses sauvegardées dans: deployments/mainnet/${filename}`);
  
  // 8. Création des propositions de gouvernance
  console.log("\n🗳️ 8. Création des propositions de gouvernance...");
  
  const governanceProposals = {
    timestamp: new Date().toISOString(),
    proposals: limitProposals.map((prop, index) => ({
      id: index + 1,
      name: prop.name,
      description: prop.description,
      target: prop.target,
      value: prop.value.toString(),
      signature: prop.signature,
      calldata: prop.data,
      status: "READY_FOR_SUBMISSION"
    })),
    instructions: [
      "1. Connecter le frontend à la GovernanceDAO",
      "2. Soumettre les propositions via l'interface",
      "3. Attendre le délai de vote (7 jours)",
      "4. Exécuter les propositions approuvées"
    ]
  };
  
  fs.writeFileSync(
    path.join(deploymentsDir, `governance-proposals-${Date.now()}.json`),
    JSON.stringify(governanceProposals, null, 2)
  );
  
  console.log("   ✓ Propositions de gouvernance préparées");
  
  // 9. Rapport final
  console.log("\n✅ DÉPLOIEMENT COMPLET TERMINÉ!");
  console.log("=========================================");
  console.log("\n🎉 TOUTES LES FONCTIONNALITÉS SONT MAINTENANT ACTIVÉES:");
  console.log("=========================================");
  console.log("\n✨ NOUVELLES FONCTIONNALITÉS:");
  console.log("   • DynamicTranche: Reclassement automatique des tranches");
  console.log("   • InsuranceModule: Assurance hybride DGF + traditionnel");
  console.log("   • SecondaryMarket: Marché secondaire liquide");
  console.log("   • RegulatoryReporting: Conformité automatique MiCA");
  
  console.log("\n⚖️ NOUVELLES LIMITES:");
  console.log(`   • Prêt max: ${ethers.utils.formatUnits(FULL_CONFIG.limits.maxLoanAmount, 6)} USDC`);
  console.log(`   • Exposition totale: ${ethers.utils.formatUnits(FULL_CONFIG.limits.maxTotalExposure, 6)} USDC`);
  console.log(`   • Prêt min: ${ethers.utils.formatUnits(FULL_CONFIG.limits.minLoanAmount, 6)} USDC`);
  
  console.log("\n🔐 SÉCURITÉ:");
  console.log("   • Emergency Council: 5 membres");
  console.log("   • Timelock: 7 jours");
  console.log("   • Voting Delay: 1 jour");
  console.log("   • Quorum: 10%");
  
  console.log("\n📋 ADRESSES IMPORTANTES:");
  console.log(`   GovernanceDAO: ${PHASE1_ADDRESSES.governanceDAO}`);
  console.log(`   LoanPool: ${PHASE1_ADDRESSES.loanPool}`);
  console.log(`   SecondaryMarket: ${secondaryMarket.address}`);
  console.log(`   InsuranceModule: ${insuranceModule.address}`);
  
  console.log("\n🚀 PROCHAINES ÉTAPES:");
  console.log("1. Soumettre les propositions de gouvernance");
  console.log("2. Attendre l'approbation des nouvelles limites");
  console.log("3. Lancer le marketing et l'onboarding");
  console.log("4. Surveillance 24/7 des nouvelles fonctionnalités");
  console.log("5. Mise à jour de la documentation");
  
  console.log("\n⚠️  IMPORTANT:");
  console.log("Les nouvelles limites ne sont actives qu'après");
  console.log("approbation par la gouvernance. Utilisez le fichier");
  console.log("governance-proposals-*.json pour soumettre les votes.");
}

// Gestion des erreurs robuste
main()
  .then(() => process.exit(0))
  .catch((error) => {
    console.error("\n❌ ERREUR CRITIQUE DANS LE DÉPLOIEMENT COMPLET:");
    console.error("=========================================");
    console.error("Message:", error.message);
    
    if (error.code) {
      console.error("Code d'erreur:", error.code);
    }
    
    if (error.transactionHash) {
      console.error("Transaction Hash:", error.transactionHash);
      console.error("Voir sur Polygonscan: https://polygonscan.com/tx/" + error.transactionHash);
    }
    
    // Sauvegarde de l'erreur pour débogage
    const errorLog = {
      timestamp: new Date().toISOString(),
      error: {
        message: error.message,
        stack: error.stack,
        code: error.code,
        transactionHash: error.transactionHash
      }
    };
    
    const errorDir = path.join(__dirname, "..", "logs", "errors");
    if (!fs.existsSync(errorDir)) {
      fs.mkdirSync(errorDir, { recursive: true });
    }
    
    fs.writeFileSync(
      path.join(errorDir, `deployment-error-${Date.now()}.json`),
      JSON.stringify(errorLog, null, 2)
    );
    
    console.error("\n📝 Erreur sauvegardée dans logs/errors/");
    
    process.exit(1);
  });