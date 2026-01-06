// scripts/create-test-pool.js
const hre = require("hardhat");

async function main() {
  console.log("🆕 Création d'un pool de test...\n");
  
  // Charger les adresses depuis le déploiement
  const addresses = require('../deployment-addresses.json');
  
  // Récupérer le déployeur
  const [deployer] = await hre.ethers.getSigners();
  
  // Attacher au LoanPool
  const LoanPool = await hre.ethers.getContractFactory("LoanPool");
  const loanPool = LoanPool.attach(addresses.loanPool);
  
  // 1. Créer un pool écologique
  console.log("1. Création d'un pool écologique...");
  const tx = await loanPool.createPool(
    "🌱 Ferme Solaire Test",
    "Installation de panneaux solaires pour une ferme en Normandie. Projet 100% écologique.",
    hre.ethers.parseUnits("50000", 6), // 50,000 USDC
    90 * 24 * 60 * 60, // 90 jours
    "Europe",
    true, // Écologique
    "Renewable Energy",
    "QmTestHash123456789" // Hash IPFS fictif
  );
  
  const receipt = await tx.wait();
  console.log(`   ✅ Pool créé ! ID: 0`);
  console.log(`   Transaction: ${receipt.hash}`);
  
  // 2. Activer le pool
  console.log("\n2. Activation du pool...");
  const tx2 = await loanPool.activatePool(0);
  await tx2.wait();
  console.log("   ✅ Pool activé !");
  
  // 3. Vérifier les détails du pool
  console.log("\n3. Détails du pool créé:");
  const pool = await loanPool.getPoolDetails(0);
  
  console.log("   ═══════════════════════════════════");
  console.log(`   Nom: ${pool.projectName}`);
  console.log(`   Emprunteur: ${pool.borrower}`);
  console.log(`   Montant cible: ${hre.ethers.formatUnits(pool.targetAmount, 6)} USDC`);
  console.log(`   Taux de base: ${pool.baseInterestRate / 100}%`);
  console.log(`   Taux dynamique: ${pool.dynamicInterestRate / 100}%`);
  console.log(`   Région: ${pool.region}`);
  console.log(`   Écologique: ${pool.isEcological ? 'OUI' : 'NON'}`);
  console.log(`   Secteur: ${pool.activityDomain}`);
  console.log(`   Statut: ${getStatusName(pool.status)}`);
  console.log("   ═══════════════════════════════════");
  
  console.log("\n🎯 POUR TESTER:");
  console.log("1. Pour investir dans ce pool:");
  console.log(`   await loanPool.invest(0, hre.ethers.parseUnits("1000", 6));`);
  console.log("\n2. Pour voir le taux dynamique:");
  console.log(`   await loanPool.getDynamicRate(0);`);
  console.log("\n3. Pour voir les détails:");
  console.log(`   await loanPool.getPoolDetails(0);`);
}

function getStatusName(statusCode) {
  const statuses = [
    "CREATION", "ACTIVE", "FUNDED", "ONGOING", 
    "COMPLETED", "DEFAULTED", "LIQUIDATED", "CANCELLED"
  ];
  return statuses[statusCode] || `INCONNU (${statusCode})`;
}

main().catch((error) => {
  console.error("❌ Erreur:", error);
  process.exitCode = 1;
});