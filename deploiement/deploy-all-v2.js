// deploy-all-v2.js
const hre = require("hardhat");
const fs = require("fs");
const path = require("path");

async function main() {
  const [deployer] = await hre.ethers.getSigners();
  
  console.log("🚀 Déploiement des contrats V2 avec l'adresse:", deployer.address);
  console.log("💰 Balance:", hre.ethers.utils.formatEther(await deployer.getBalance()));
  
  // 1. Déploiement de l'AccessController
  console.log("\n1. Déploiement de l'AccessController...");
  const AccessController = await hre.ethers.getContractFactory("AccessController");
  const accessController = await AccessController.deploy();
  await accessController.deployed();
  console.log("✅ AccessController déployé à:", accessController.address);
  
  // 2. Déploiement de KYCRegistry
  console.log("\n2. Déploiement de KYCRegistry...");
  const KYCRegistry = await hre.ethers.getContractFactory("KYCRegistry");
  const kycRegistry = await KYCRegistry.deploy(accessController.address);
  await kycRegistry.deployed();
  console.log("✅ KYCRegistry déployé à:", kycRegistry.address);
  
  // 3. Déploiement de l'OracleAdapter
  console.log("\n3. Déploiement de l'OracleAdapter...");
  const OracleAdapter = await hre.ethers.getContractFactory("OracleAdapter");
  const oracleAdapter = await OracleAdapter.deploy();
  await oracleAdapter.deployed();
  console.log("✅ OracleAdapter déployé à:", oracleAdapter.address);
  
  // 4. Déploiement du RiskEngineV2
  console.log("\n4. Déploiement du RiskEngineV2...");
  const RiskEngineV2 = await hre.ethers.getContractFactory("RiskEngineV2");
  const riskEngine = await RiskEngineV2.deploy(
    oracleAdapter.address,
    kycRegistry.address
  );
  await riskEngine.deployed();
  console.log("✅ RiskEngineV2 déployé à:", riskEngine.address);
  
  // 5. Déploiement de LoanNFTV2
  console.log("\n5. Déploiement de LoanNFTV2...");
  const LoanNFTV2 = await hre.ethers.getContractFactory("LoanNFTV2");
  const loanNFT = await LoanNFTV2.deploy();
  await loanNFT.deployed();
  console.log("✅ LoanNFTV2 déployé à:", loanNFT.address);
  
  // 6. Déploiement de l'InsuranceModuleV2
  console.log("\n6. Déploiement de l'InsuranceModuleV2...");
  const InsuranceModuleV2 = await hre.ethers.getContractFactory("InsuranceModuleV2");
  const insuranceModule = await InsuranceModuleV2.deploy(accessController.address);
  await insuranceModule.deployed();
  console.log("✅ InsuranceModuleV2 déployé à:", insuranceModule.address);
  
  // 7. Déploiement de BondingCurveV2
  console.log("\n7. Déploiement de BondingCurveV2...");
  const BondingCurveV2 = await hre.ethers.getContractFactory("BondingCurveV2");
  const bondingCurve = await BondingCurveV2.deploy();
  await bondingCurve.deployed();
  console.log("✅ BondingCurveV2 déployé à:", bondingCurve.address);
  
  // 8. Déploiement de DynamicTranche
  console.log("\n8. Déploiement de DynamicTranche...");
  const DynamicTranche = await hre.ethers.getContractFactory("DynamicTranche");
  const dynamicTranche = await DynamicTranche.deploy(accessController.address);
  await dynamicTranche.deployed();
  console.log("✅ DynamicTranche déployé à:", dynamicTranche.address);
  
  // 9. Déploiement de SecondaryMarketV2
  console.log("\n9. Déploiement de SecondaryMarketV2...");
  const SecondaryMarketV2 = await hre.ethers.getContractFactory("SecondaryMarketV2");
  const secondaryMarket = await SecondaryMarketV2.deploy(
    loanNFT.address,
    "0xA0b86991c6218b36c1d19D4a2e9Eb0cE3606eB48", // USDC
    deployer.address
  );
  await secondaryMarket.deployed();
  console.log("✅ SecondaryMarketV2 déployé à:", secondaryMarket.address);
  
  // 10. Déploiement de LoanPoolV2
  console.log("\n10. Déploiement de LoanPoolV2...");
  const LoanPoolV2 = await hre.ethers.getContractFactory("LoanPoolV2");
  const loanPool = await LoanPoolV2.deploy(
    riskEngine.address,
    loanNFT.address,
    insuranceModule.address,
    bondingCurve.address,
    dynamicTranche.address,
    accessController.address
  );
  await loanPool.deployed();
  console.log("✅ LoanPoolV2 déployé à:", loanPool.address);
  
  // 11. Déploiement de ReputationTokenV2
  console.log("\n11. Déploiement de ReputationTokenV2...");
  const ReputationTokenV2 = await hre.ethers.getContractFactory("ReputationTokenV2");
  const reputationToken = await ReputationTokenV2.deploy();
  await reputationToken.deployed();
  console.log("✅ ReputationTokenV2 déployé à:", reputationToken.address);
  
  // 12. Déploiement de GovernanceDAOV2
  console.log("\n12. Déploiement de GovernanceDAOV2...");
  
  // Déploiement du TimelockController d'abord
  const TimelockController = await hre.ethers.getContractFactory("TimelockController");
  const timelock = await TimelockController.deploy(
    0, // Min delay
    [], // Proposers
    [], // Executors
    deployer.address // Admin
  );
  await timelock.deployed();
  console.log("   TimelockController déployé à:", timelock.address);
  
  // Déploiement du token de gouvernance
  const GovernanceToken = await hre.ethers.getContractFactory("GovernanceToken");
  const governanceToken = await GovernanceToken.deploy();
  await governanceToken.deployed();
  console.log("   GovernanceToken déployé à:", governanceToken.address);
  
  const GovernanceDAOV2 = await hre.ethers.getContractFactory("GovernanceDAOV2");
  const governanceDAO = await GovernanceDAOV2.deploy(
    governanceToken.address,
    timelock.address,
    reputationToken.address
  );
  await governanceDAO.deployed();
  console.log("✅ GovernanceDAOV2 déployé à:", governanceDAO.address);
  
  // 13. Déploiement de DecentralizedGuaranteeFundV2
  console.log("\n13. Déploiement de DecentralizedGuaranteeFundV2...");
  const DecentralizedGuaranteeFundV2 = await hre.ethers.getContractFactory("DecentralizedGuaranteeFundV2");
  const guaranteeFund = await DecentralizedGuaranteeFundV2.deploy(
    loanPool.address,
    "0xA0b86991c6218b36c1d19D4a2e9Eb0cE3606eB48" // USDC
  );
  await guaranteeFund.deployed();
  console.log("✅ DecentralizedGuaranteeFundV2 déployé à:", guaranteeFund.address);
  
  // 14. Déploiement de NotificationManagerV2
  console.log("\n14. Déploiement de NotificationManagerV2...");
  const NotificationManagerV2 = await hre.ethers.getContractFactory("NotificationManagerV2");
  const notificationManager = await NotificationManagerV2.deploy();
  await notificationManager.deployed();
  console.log("✅ NotificationManagerV2 déployé à:", notificationManager.address);
  
  // 15. Déploiement de FeeDistributorV2
  console.log("\n15. Déploiement de FeeDistributorV2...");
  const FeeDistributorV2 = await hre.ethers.getContractFactory("FeeDistributorV2");
  const feeDistributor = await FeeDistributorV2.deploy(
    "0xA0b86991c6218b36c1d19D4a2e9Eb0cE3606eB48" // USDC
  );
  await feeDistributor.deployed();
  console.log("✅ FeeDistributorV2 déployé à:", feeDistributor.address);
  
  // Configuration des autorisations
  console.log("\n🔧 Configuration des autorisations...");
  
  // Initialisation des rôles dans AccessController
  await accessController.initializeRoles();
  
  // Autorisation des contrats principaux
  await accessController.grantRole(loanPool.address, "LOAN_MANAGER");
  await accessController.grantRole(riskEngine.address, "RISK_MANAGER");
  await accessController.grantRole(insuranceModule.address, "INSURANCE_MANAGER");
  await accessController.grantRole(governanceDAO.address, "GOVERNANCE_MANAGER");
  await accessController.grantRole(guaranteeFund.address, "FUND_MANAGER");
  await accessController.grantRole(notificationManager.address, "NOTIFICATION_SENDER");
  await accessController.grantRole(feeDistributor.address, "FEE_COLLECTOR");
  
  // Configuration des dépendances entre contrats
  console.log("\n🔗 Configuration des dépendances...");
  
  // LoanNFT configuration
  await loanNFT.grantRole(await loanNFT.LOAN_MANAGER(), loanPool.address);
  await loanNFT.grantRole(await loanNFT.MARKET_MANAGER(), secondaryMarket.address);
  
  // InsuranceModule configuration
  await insuranceModule.setLoanPool(loanPool.address);
  
  // DynamicTranche configuration
  await dynamicTranche.setSecondaryMarket(secondaryMarket.address);
  
  // NotificationManager autorisation des expéditeurs
  await notificationManager.authorizeSender(loanPool.address);
  await notificationManager.authorizeSender(governanceDAO.address);
  await notificationManager.authorizeSender(secondaryMarket.address);
  
  // ReputationToken autorisation des minters
  await reputationToken.addReputationGranter(loanPool.address);
  await reputationToken.addReputationGranter(governanceDAO.address);
  
  // Enregistrement dans AccessController
  console.log("\n📋 Enregistrement des contrats...");
  
  await accessController.registerContract("LoanPoolV2", loanPool.address);
  await accessController.registerContract("RiskEngineV2", riskEngine.address);
  await accessController.registerContract("LoanNFTV2", loanNFT.address);
  await accessController.registerContract("InsuranceModuleV2", insuranceModule.address);
  await accessController.registerContract("GovernanceDAOV2", governanceDAO.address);
  await accessController.registerContract("GuaranteeFundV2", guaranteeFund.address);
  await accessController.registerContract("SecondaryMarketV2", secondaryMarket.address);
  await accessController.registerContract("NotificationManagerV2", notificationManager.address);
  await accessController.registerContract("FeeDistributorV2", feeDistributor.address);
  await accessController.registerContract("ReputationTokenV2", reputationToken.address);
  
  // Sauvegarde des adresses
  const addresses = {
    accessController: accessController.address,
    kycRegistry: kycRegistry.address,
    oracleAdapter: oracleAdapter.address,
    riskEngine: riskEngine.address,
    loanNFT: loanNFT.address,
    insuranceModule: insuranceModule.address,
    bondingCurve: bondingCurve.address,
    dynamicTranche: dynamicTranche.address,
    secondaryMarket: secondaryMarket.address,
    loanPool: loanPool.address,
    governanceDAO: governanceDAO.address,
    governanceToken: governanceToken.address,
    timelockController: timelock.address,
    reputationToken: reputationToken.address,
    guaranteeFund: guaranteeFund.address,
    notificationManager: notificationManager.address,
    feeDistributor: feeDistributor.address,
    deployer: deployer.address
  };
  
  const addressesDir = path.join(__dirname, "..", "deployed", "v2");
  if (!fs.existsSync(addressesDir)) {
    fs.mkdirSync(addressesDir, { recursive: true });
  }
  
  fs.writeFileSync(
    path.join(addressesDir, "addresses.json"),
    JSON.stringify(addresses, null, 2)
  );
  
  // Génération des fichiers d'environnement
  const envContent = `
REACT_APP_ACCESS_CONTROLLER_ADDRESS=${addresses.accessController}
REACT_APP_LOAN_POOL_V2_ADDRESS=${addresses.loanPool}
REACT_APP_RISK_ENGINE_V2_ADDRESS=${addresses.riskEngine}
REACT_APP_LOAN_NFT_V2_ADDRESS=${addresses.loanNFT}
REACT_APP_SECONDARY_MARKET_V2_ADDRESS=${addresses.secondaryMarket}
REACT_APP_GOVERNANCE_DAO_V2_ADDRESS=${addresses.governanceDAO}
REACT_APP_GOVERNANCE_TOKEN_ADDRESS=${addresses.governanceToken}
REACT_APP_REPUTATION_TOKEN_ADDRESS=${addresses.reputationToken}
REACT_APP_GUARANTEE_FUND_V2_ADDRESS=${addresses.guaranteeFund}
REACT_APP_NOTIFICATION_MANAGER_ADDRESS=${addresses.notificationManager}
REACT_APP_FEE_DISTRIBUTOR_ADDRESS=${addresses.feeDistributor}
REACT_APP_NETWORK_ID=1
REACT_APP_INFURA_ID=votre_infura_id
REACT_APP_APP_NAME="Structured Lending Protocol V2"
  `.trim();
  
  fs.writeFileSync(
    path.join(addressesDir, ".env.local"),
    envContent
  );
  
  // Génération d'un fichier de configuration pour les tests
  const configContent = `
module.exports = {
  addresses: ${JSON.stringify(addresses, null, 2)}
};
  `.trim();
  
  fs.writeFileSync(
    path.join(addressesDir, "config.js"),
    configContent
  );
  
  console.log("\n🎉 Déploiement V2 terminé avec succès!");
  console.log("\n📁 Adresses sauvegardées dans:", path.join(addressesDir, "addresses.json"));
  console.log("🌐 Fichier d'environnement généré");
  console.log("⚙️  Fichier de configuration généré");
  
  // Résumé des contrats déployés
  console.log("\n📊 RÉSUMÉ DES CONTRATS DÉPLOYÉS:");
  console.log("=================================");
  console.log(`AccessController: ${accessController.address}`);
  console.log(`LoanPoolV2: ${loanPool.address}`);
  console.log(`RiskEngineV2: ${riskEngine.address}`);
  console.log(`LoanNFTV2: ${loanNFT.address}`);
  console.log(`InsuranceModuleV2: ${insuranceModule.address}`);
  console.log(`GovernanceDAOV2: ${governanceDAO.address}`);
  console.log(`GuaranteeFundV2: ${guaranteeFund.address}`);
  console.log(`SecondaryMarketV2: ${secondaryMarket.address}`);
  console.log(`NotificationManagerV2: ${notificationManager.address}`);
  console.log(`FeeDistributorV2: ${feeDistributor.address}`);
  console.log(`ReputationTokenV2: ${reputationToken.address}`);
  console.log("=================================");
}

main()
  .then(() => process.exit(0))
  .catch((error) => {
    console.error("❌ Erreur lors du déploiement:", error);
    process.exit(1);
  });