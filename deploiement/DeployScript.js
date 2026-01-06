const hre = require("hardhat");
const fs = require("fs");
const path = require("path");

async function main() {
  const [deployer] = await hre.ethers.getSigners();
  
  console.log("Déploiement avec l'adresse:", deployer.address);
  console.log("Balance:", (await deployer.getBalance()).toString());
  
  // Déploiement séquentiel
  console.log("\n1. Déploiement de l'AccessController...");
  const AccessController = await hre.ethers.getContractFactory("AccessController");
  const accessController = await AccessController.deploy();
  await accessController.deployed();
  console.log("AccessController déployé à:", accessController.address);
  
  console.log("\n2. Déploiement de KYCRegistry...");
  const KYCRegistry = await hre.ethers.getContractFactory("KYCRegistry");
  const kycRegistry = await KYCRegistry.deploy(accessController.address);
  await kycRegistry.deployed();
  console.log("KYCRegistry déployé à:", kycRegistry.address);
  
  console.log("\n3. Déploiement de l'OracleAdapter...");
  const OracleAdapter = await hre.ethers.getContractFactory("OracleAdapter");
  const oracleAdapter = await OracleAdapter.deploy();
  await oracleAdapter.deployed();
  console.log("OracleAdapter déployé à:", oracleAdapter.address);
  
  console.log("\n4. Déploiement du RiskEngine...");
  const RiskEngine = await hre.ethers.getContractFactory("RiskEngineV2");
  const riskEngine = await RiskEngine.deploy(
    oracleAdapter.address,
    kycRegistry.address
  );
  await riskEngine.deployed();
  console.log("RiskEngine déployé à:", riskEngine.address);
  
  console.log("\n5. Déploiement de LoanNFT...");
  const LoanNFT = await hre.ethers.getContractFactory("LoanNFT");
  const loanNFT = await LoanNFT.deploy();
  await loanNFT.deployed();
  console.log("LoanNFT déployé à:", loanNFT.address);
  
  console.log("\n6. Déploiement de l'InsuranceModule...");
  const InsuranceModule = await hre.ethers.getContractFactory("InsuranceModuleV2");
  const insuranceModule = await InsuranceModule.deploy(accessController.address);
  await insuranceModule.deployed();
  console.log("InsuranceModule déployé à:", insuranceModule.address);
  
  console.log("\n7. Déploiement de BondingCurve...");
  const BondingCurve = await hre.ethers.getContractFactory("BondingCurveV2");
  const bondingCurve = await BondingCurve.deploy();
  await bondingCurve.deployed();
  console.log("BondingCurve déployé à:", bondingCurve.address);
  
  console.log("\n8. Déploiement de DynamicTranche...");
  const DynamicTranche = await hre.ethers.getContractFactory("DynamicTranche");
  const dynamicTranche = await DynamicTranche.deploy(accessController.address);
  await dynamicTranche.deployed();
  console.log("DynamicTranche déployé à:", dynamicTranche.address);
  
  console.log("\n9. Déploiement du SecondaryMarket...");
  const SecondaryMarket = await hre.ethers.getContractFactory("SecondaryMarketV2");
  const secondaryMarket = await SecondaryMarket.deploy(
    loanNFT.address,
    "0xA0b86991c6218b36c1d19D4a2e9Eb0cE3606eB48", // USDC
    deployer.address
  );
  await secondaryMarket.deployed();
  console.log("SecondaryMarket déployé à:", secondaryMarket.address);
  
  console.log("\n10. Déploiement de LoanPool (contrat principal)...");
  const LoanPool = await hre.ethers.getContractFactory("LoanPoolV2");
  const loanPool = await LoanPool.deploy(
    riskEngine.address,
    loanNFT.address,
    insuranceModule.address,
    bondingCurve.address,
    dynamicTranche.address,
    accessController.address
  );
  await loanPool.deployed();
  console.log("LoanPool déployé à:", loanPool.address);
  
  console.log("\n11. Déploiement de GovernanceDAO...");
  const GovernanceDAO = await hre.ethers.getContractFactory("GovernanceDAO");
  const governanceDAO = await GovernanceDAO.deploy(
    loanPool.address,
    accessController.address
  );
  await governanceDAO.deployed();
  console.log("GovernanceDAO déployé à:", governanceDAO.address);
  
  console.log("\n12. Déploiement de DecentralizedGuaranteeFund...");
  const DecentralizedGuaranteeFund = await hre.ethers.getContractFactory("DecentralizedGuaranteeFund");
  const guaranteeFund = await DecentralizedGuaranteeFund.deploy(
    loanPool.address,
    accessController.address
  );
  await guaranteeFund.deployed();
  console.log("DecentralizedGuaranteeFund déployé à:", guaranteeFund.address);
  
  // Configuration des rôles et autorisations
  console.log("\n13. Configuration des autorisations...");
  
  // Rôles dans AccessController
  await accessController.initializeRoles();
  
  // Autoriser les contrats
  await accessController.grantRole(loanPool.address, "LOAN_MANAGER");
  await accessController.grantRole(riskEngine.address, "RISK_MANAGER");
  await accessController.grantRole(insuranceModule.address, "INSURANCE_MANAGER");
  await accessController.grantRole(governanceDAO.address, "GOVERNANCE_MANAGER");
  await accessController.grantRole(guaranteeFund.address, "FUND_MANAGER");
  
  // Configuration des contrats liés
  console.log("\n14. Configuration des dépendances...");
  
  await loanNFT.setLoanPool(loanPool.address);
  await insuranceModule.setLoanPool(loanPool.address);
  await dynamicTranche.setSecondaryMarket(secondaryMarket.address);
  
  // Enregistrement dans AccessController
  await accessController.registerContract("LoanPool", loanPool.address);
  await accessController.registerContract("RiskEngine", riskEngine.address);
  await accessController.registerContract("LoanNFT", loanNFT.address);
  await accessController.registerContract("InsuranceModule", insuranceModule.address);
  await accessController.registerContract("GovernanceDAO", governanceDAO.address);
  await accessController.registerContract("GuaranteeFund", guaranteeFund.address);
  await accessController.registerContract("SecondaryMarket", secondaryMarket.address);
  
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
    guaranteeFund: guaranteeFund.address,
    deployer: deployer.address
  };
  
  const addressesDir = path.join(__dirname, "..", "deployed");
  if (!fs.existsSync(addressesDir)) {
    fs.mkdirSync(addressesDir, { recursive: true });
  }
  
  fs.writeFileSync(
    path.join(addressesDir, "addresses.json"),
    JSON.stringify(addresses, null, 2)
  );
  
  console.log("\n✅ Déploiement terminé avec succès!");
  console.log("\n📄 Adresses sauvegardées dans:", path.join(addressesDir, "addresses.json"));
  
  // Génération d'un fichier d'environnement
  const envContent = `
REACT_APP_ACCESS_CONTROLLER_ADDRESS=${addresses.accessController}
REACT_APP_LOAN_POOL_ADDRESS=${addresses.loanPool}
REACT_APP_RISK_ENGINE_ADDRESS=${addresses.riskEngine}
REACT_APP_LOAN_NFT_ADDRESS=${addresses.loanNFT}
REACT_APP_SECONDARY_MARKET_ADDRESS=${addresses.secondaryMarket}
REACT_APP_GOVERNANCE_DAO_ADDRESS=${addresses.governanceDAO}
REACT_APP_NETWORK_ID=1
REACT_APP_INFURA_ID=votre_infura_id
  `.trim();
  
  fs.writeFileSync(
    path.join(addressesDir, ".env.local"),
    envContent
  );
  
  console.log("\n🌐 Fichier d'environnement généré");
}

main()
  .then(() => process.exit(0))
  .catch((error) => {
    console.error(error);
    process.exit(1);
  });