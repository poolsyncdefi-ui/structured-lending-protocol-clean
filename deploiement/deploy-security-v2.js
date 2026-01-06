// deploy-security-v2.js
const hre = require("hardhat");
const fs = require("fs");
const path = require("path");

async function main() {
  const [deployer] = await hre.ethers.getSigners();
  
  console.log("🔒 Déploiement des contrats de sécurité V2 avec l'adresse:", deployer.address);
  
  // 1. Déploiement de l'AccessControllerV2
  console.log("\n1. Déploiement de l'AccessControllerV2...");
  const AccessControllerV2 = await hre.ethers.getContractFactory("AccessControllerV2");
  const accessController = await AccessControllerV2.deploy();
  await accessController.deployed();
  console.log("✅ AccessControllerV2 déployé à:", accessController.address);
  
  // 2. Déploiement de KYCRegistryV2
  console.log("\n2. Déploiement de KYCRegistryV2...");
  const KYCRegistryV2 = await hre.ethers.getContractFactory("KYCRegistryV2");
  const kycRegistry = await KYCRegistryV2.deploy(accessController.address);
  await kycRegistry.deployed();
  console.log("✅ KYCRegistryV2 déployé à:", kycRegistry.address);
  
  // 3. Déploiement de EmergencyExecutorV2
  console.log("\n3. Déploiement de EmergencyExecutorV2...");
  const EmergencyExecutorV2 = await hre.ethers.getContractFactory("EmergencyExecutorV2");
  const emergencyExecutor = await EmergencyExecutorV2.deploy(accessController.address);
  await emergencyExecutor.deployed();
  console.log("✅ EmergencyExecutorV2 déployé à:", emergencyExecutor.address);
  
  // Configuration des rôles dans AccessController
  console.log("\n🔧 Configuration des rôles...");
  
  // Initialisation des rôles système
  await accessController.initializeRoles();
  
  // Attribution des rôles KYC
  await accessController.grantRoleWithApproval(
    await kycRegistry.KYC_VERIFIER(),
    kycRegistry.address,
    [] // Signatures vides pour test
  );
  
  await accessController.grantRoleWithApproval(
    await kycRegistry.KYC_AUDITOR(),
    kycRegistry.address,
    []
  );
  
  await accessController.grantRoleWithApproval(
    await kycRegistry.SANCTION_MANAGER(),
    kycRegistry.address,
    []
  );
  
  // Attribution des rôles Emergency
  await accessController.grantRoleWithApproval(
    await emergencyExecutor.EMERGENCY_PROPOSER(),
    emergencyExecutor.address,
    []
  );
  
  await accessController.grantRoleWithApproval(
    await emergencyExecutor.EMERGENCY_APPROVER(),
    emergencyExecutor.address,
    []
  );
  
  await accessController.grantRoleWithApproval(
    await emergencyExecutor.EMERGENCY_EXECUTOR(),
    emergencyExecutor.address,
    []
  );
  
  // Enregistrement des contrats dans AccessController
  console.log("\n📋 Enregistrement des contrats...");
  
  await accessController.registerContract(
    "KYCRegistryV2",
    kycRegistry.address,
    "1.0.0",
    "ipfs://QmKYCConfig"
  );
  
  await accessController.registerContract(
    "EmergencyExecutorV2",
    emergencyExecutor.address,
    "1.0.0",
    "ipfs://QmEmergencyConfig"
  );
  
  // Sauvegarde des adresses
  const addresses = {
    accessControllerV2: accessController.address,
    kycRegistryV2: kycRegistry.address,
    emergencyExecutorV2: emergencyExecutor.address,
    deployer: deployer.address
  };
  
  const addressesDir = path.join(__dirname, "..", "deployed", "security-v2");
  if (!fs.existsSync(addressesDir)) {
    fs.mkdirSync(addressesDir, { recursive: true });
  }
  
  fs.writeFileSync(
    path.join(addressesDir, "addresses.json"),
    JSON.stringify(addresses, null, 2)
  );
  
  // Génération d'un fichier de test
  const testConfig = `
module.exports = {
  accessController: "${accessController.address}",
  kycRegistry: "${kycRegistry.address}",
  emergencyExecutor: "${emergencyExecutor.address}",
  
  // Rôles
  roles: {
    SUPER_ADMIN: "${await accessController.SUPER_ADMIN()}",
    SECURITY_ADMIN: "${await accessController.SECURITY_ADMIN()}",
    KYC_VERIFIER: "${await kycRegistry.KYC_VERIFIER()}",
    EMERGENCY_EXECUTOR: "${await emergencyExecutor.EMERGENCY_EXECUTOR()}"
  }
};
  `.trim();
  
  fs.writeFileSync(
    path.join(addressesDir, "test-config.js"),
    testConfig
  );
  
  console.log("\n🎉 Déploiement des contrats de sécurité V2 terminé!");
  console.log("\n📊 RÉSUMÉ:");
  console.log("=================================");
  console.log(`AccessControllerV2: ${accessController.address}`);
  console.log(`KYCRegistryV2: ${kycRegistry.address}`);
  console.log(`EmergencyExecutorV2: ${emergencyExecutor.address}`);
  console.log("=================================");
  console.log("\n📁 Fichiers générés:");
  console.log(`- ${path.join(addressesDir, "addresses.json")}`);
  console.log(`- ${path.join(addressesDir, "test-config.js")}`);
}

main()
  .then(() => process.exit(0))
  .catch((error) => {
    console.error("❌ Erreur lors du déploiement:", error);
    process.exit(1);
  });