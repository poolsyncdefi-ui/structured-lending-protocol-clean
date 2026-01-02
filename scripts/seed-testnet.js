// scripts/seed-testnet.js
const hre = require("hardhat");
const { ethers } = hre;

async function main() {
  console.log("🌱 Peuplement du protocole avec des données de test...\n");
  
  const [deployer] = await ethers.getSigners();
  console.log(`Utilisateur: ${deployer.address}`);
  
  // Adresses des contrats (à remplacer après déploiement)
  const LOAN_POOL_ADDRESS = "0x...";
  const STABLECOIN_ADDRESS = "0x...";
  
  const LoanPool = await ethers.getContractFactory("LoanPool");
  const loanPool = LoanPool.attach(LOAN_POOL_ADDRESS);
  
  const Stablecoin = await ethers.getContractFactory("MockERC20");
  const stablecoin = Stablecoin.attach(STABLECOIN_ADDRESS);
  
  // Données de test
  const testPools = [
    {
      name: "Ferme Solaire Normandie",
      description: "Installation de panneaux solaires sur 5 hectares",
      amount: ethers.parseEther("50000"),
      duration: 180 * 24 * 60 * 60, // 180 jours
      region: "Europe",
      ecological: true,
      domain: "Renewable Energy",
      ipfs: "QmVFqK123..."
    },
    {
      name: "Startup AgriTech Bretagne",
      description: "Développement de serres connectées",
      amount: ethers.parseEther("25000"),
      duration: 120 * 24 * 60 * 60,
      region: "Europe",
      ecological: true,
      domain: "Agriculture",
      ipfs: "QmVFqK456..."
    },
    {
      name: "Rénovation Immeuble Lyon",
      description: "Rénovation énergétique d'un immeuble de 20 appartements",
      amount: ethers.parseEther("150000"),
      duration: 240 * 24 * 60 * 60,
      region: "Europe",
      ecological: true,
      domain: "Real Estate",
      ipfs: "QmVFqK789..."
    },
    {
      name: "Atelier Vélo Électrique Paris",
      description: "Création d'un atelier de réparation et vente de vélos électriques",
      amount: ethers.parseEther("15000"),
      duration: 90 * 24 * 60 * 60,
      region: "Europe",
      ecological: true,
      domain: "Manufacturing",
      ipfs: "QmVFqK012..."
    }
  ];
  
  const testInvestments = [
    { poolIndex: 0, amount: ethers.parseEther("10000") },
    { poolIndex: 0, amount: ethers.parseEther("15000") },
    { poolIndex: 1, amount: ethers.parseEther("5000") },
    { poolIndex: 1, amount: ethers.parseEther("7000") },
    { poolIndex: 2, amount: ethers.parseEther("30000") },
    { poolIndex: 3, amount: ethers.parseEther("5000") }
  ];
  
  // 1. Créer les pools
  console.log("1. Création des pools de test...");
  for (let i = 0; i < testPools.length; i++) {
    const pool = testPools[i];
    
    console.log(`   Pool ${i}: ${pool.name}`);
    console.log(`   Montant: ${ethers.formatEther(pool.amount)} tokens`);
    
    try {
      const tx = await loanPool.createPool(
        pool.name,
        pool.description,
        pool.amount,
        pool.duration,
        pool.region,
        pool.ecological,
        pool.domain,
        pool.ipfs
      );
      await tx.wait();
      
      // Activer le pool
      await loanPool.activatePool(i);
      console.log(`   ✅ Pool ${i} créé et activé\n`);
    } catch (error) {
      console.log(`   ❌ Erreur sur pool ${i}:`, error.message);
    }
    
    // Petite pause entre les transactions
    await new Promise(resolve => setTimeout(resolve, 2000));
  }
  
  // 2. Simuler des investissements
  console.log("\n2. Simulation d'investissements...");
  
  // Créer des investisseurs test
  const testInvestors = [];
  for (let i = 0; i < 5; i++) {
    const investor = ethers.Wallet.createRandom().connect(ethers.provider);
    testInvestors.push(investor);
    
    // Funding avec stablecoin test
    await stablecoin.mint(investor.address, ethers.parseEther("50000"));
    await stablecoin.connect(investor).approve(LOAN_POOL_ADDRESS, ethers.parseEther("50000"));
    
    console.log(`   Investisseur ${i}: ${investor.address.slice(0, 10)}...`);
  }
  
  // Répartir les investissements
  let investmentCount = 0;
  for (const investment of testInvestments) {
    const investor = testInvestors[investmentCount % testInvestors.length];
    
    console.log(`   Investissement ${investmentCount}: ${ethers.formatEther(investment.amount)} dans pool ${investment.poolIndex}`);
    
    try {
      const tx = await loanPool.connect(investor).invest(
        investment.poolIndex,
        investment.amount
      );
      await tx.wait();
      console.log(`   ✅ Investissement ${investmentCount} réussi`);
    } catch (error) {
      console.log(`   ❌ Erreur:`, error.message);
    }
    
    investmentCount++;
    await new Promise(resolve => setTimeout(resolve, 1000));
  }
  
  // 3. Vérifier l'état final
  console.log("\n3. État final des pools:");
  
  for (let i = 0; i < testPools.length; i++) {
    const pool = await loanPool.getPoolDetails(i);
    const percentage = (Number(pool.collectedAmount) / Number(pool.targetAmount) * 100).toFixed(1);
    
    console.log(`   Pool ${i} - ${pool.projectName}:`);
    console.log(`     Collecté: ${ethers.formatEther(pool.collectedAmount)} / ${ethers.formatEther(pool.targetAmount)} (${percentage}%)`);
    console.log(`     Taux dynamique: ${pool.dynamicInterestRate / 100}%`);
    console.log(`     Statut: ${getStatusName(pool.status)}\n`);
  }
  
  // 4. Créer une offre spéciale
  console.log("\n4. Création d'une offre spéciale...");
  
  const SpecialOfferManager = await ethers.getContractFactory("SpecialOfferManager");
  const specialOfferManager = SpecialOfferManager.attach("0x..."); // Adresse du manager
  
  try {
    const tx = await specialOfferManager.createOffer(
      1, // SEASONAL
      "Offre Printemps Écologique",
      "Bonus pour tous les projets écologiques ce printemps",
      150, // 1.5% bonus
      30 * 24 * 60 * 60, // 30 jours
      ethers.parseEther("50000"), // 50,000 max bonus
      [0, 1, 2, 3] // Tous les pools
    );
    await tx.wait();
    console.log("   ✅ Offre spéciale créée");
  } catch (error) {
    console.log("   ❌ Erreur création offre:", error.message);
  }
  
  console.log("\n" + "=".repeat(60));
  console.log("✅ PEUPLEMENT TERMINÉ !");
  console.log("=".repeat(60));
  console.log("\n📊 Résumé:");
  console.log(`• ${testPools.length} pools créés`);
  console.log(`• ${testInvestments.length} investissements simulés`);
  console.log(`• ${testInvestors.length} investisseurs test`);
  console.log("\n🌐 Pour tester:");
  console.log(`1. Accéder à LoanPool: ${LOAN_POOL_ADDRESS}`);
  console.log(`2. Vérifier sur Etherscan`);
  console.log(`3. Tester avec le frontend`);
}

function getStatusName(statusCode) {
  const statuses = [
    "CREATION", "ACTIVE", "FUNDED", "ONGOING", 
    "COMPLETED", "DEFAULTED", "LIQUIDATED", "CANCELLED"
  ];
  return statuses[statusCode] || "INCONNU";
}

main().catch((error) => {
  console.error(error);
  process.exitCode = 1;
});