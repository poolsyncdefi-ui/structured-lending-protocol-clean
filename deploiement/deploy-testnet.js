// scripts/deploy-testnet.js
const hre = require("hardhat");

async function main() {
  console.log("🚀 Déploiement du protocole PoolSync pour tests...\n");

  // Récupérer le déployeur
  const [deployer] = await hre.ethers.getSigners();
  console.log(`Déployeur: ${deployer.address}`);
  console.log(`Balance initiale: ${hre.ethers.formatEther(await deployer.provider.getBalance(deployer.address))} ETH\n`);

  // 1. Déployer le MockERC20 (stablecoin pour tests)
  console.log("1. Déploiement du MockERC20 (stablecoin de test)...");
  const MockERC20 = await hre.ethers.getContractFactory("MockERC20");
  const stablecoin = await MockERC20.deploy("Test USDC", "USDC", 6); // 6 décimales comme le vrai USDC
  await stablecoin.waitForDeployment();
  const stablecoinAddress = await stablecoin.getAddress();
  console.log(`   ✅ MockERC20 déployé à: ${stablecoinAddress}`);
  console.log(`   Symbole: ${await stablecoin.symbol()}`);
  console.log(`   Décimals: ${await stablecoin.decimals()}`);

  // 2. Déployer RiskEngine (avec adresses mock pour les oracles)
  console.log("\n2. Déploiement du RiskEngine...");
  const RiskEngine = await hre.ethers.getContractFactory("RiskEngine");
  
  // Créer des adresses mock pour les oracles (on utilise des adresses vides pour tests)
  const mockCreditOracle = "0x0000000000000000000000000000000000000001";
  const mockMarketOracle = "0x0000000000000000000000000000000000000002";
  
  const riskEngine = await RiskEngine.deploy(mockCreditOracle, mockMarketOracle);
  await riskEngine.waitForDeployment();
  const riskEngineAddress = await riskEngine.getAddress();
  console.log(`   ✅ RiskEngine déployé à: ${riskEngineAddress}`);

  // 3. Déployer LoanPool
  console.log("\n3. Déploiement du LoanPool...");
  const LoanPool = await hre.ethers.getContractFactory("LoanPool");
  
  // Utiliser l'adresse du déployeur comme feeCollector
  const feeCollector = deployer.address;
  
  const loanPool = await LoanPool.deploy(
    stablecoinAddress,
    riskEngineAddress,
    feeCollector
  );
  await loanPool.waitForDeployment();
  const loanPoolAddress = await loanPool.getAddress();
  console.log(`   ✅ LoanPool déployé à: ${loanPoolAddress}`);
  console.log(`   Fee Collector: ${feeCollector}`);

  // 4. Déployer CriteriaFilter
  console.log("\n4. Déploiement du CriteriaFilter...");
  const CriteriaFilter = await hre.ethers.getContractFactory("CriteriaFilter");
  const criteriaFilter = await CriteriaFilter.deploy(loanPoolAddress);
  await criteriaFilter.waitForDeployment();
  const criteriaFilterAddress = await criteriaFilter.getAddress();
  console.log(`   ✅ CriteriaFilter déployé à: ${criteriaFilterAddress}`);

  // 5. Déployer SpecialOfferManager
  console.log("\n5. Déploiement du SpecialOfferManager...");
  const SpecialOfferManager = await hre.ethers.getContractFactory("SpecialOfferManager");
  const specialOfferManager = await SpecialOfferManager.deploy();
  await specialOfferManager.waitForDeployment();
  const specialOfferManagerAddress = await specialOfferManager.getAddress();
  console.log(`   ✅ SpecialOfferManager déployé à: ${specialOfferManagerAddress}`);

  // 6. Configurer les modules dans LoanPool
  console.log("\n6. Configuration des modules dans LoanPool...");
  const tx1 = await loanPool.setExternalModules(
    riskEngineAddress,
    criteriaFilterAddress,
    specialOfferManagerAddress
  );
  await tx1.wait();
  console.log("   ✅ Modules configurés");

  // 7. Autoriser le déployeur à créer des pools
  console.log("\n7. Configuration des permissions...");
  const tx2 = await loanPool.authorizeCreator(deployer.address, true);
  await tx2.wait();
  console.log(`   ✅ ${deployer.address} autorisé à créer des pools`);

  // 8. Configurer les paramètres du protocole
  console.log("\n8. Configuration des paramètres du protocole...");
  const tx3 = await loanPool.updateProtocolParameters(
    50,      // 0.5% de frais (50 points de base)
    hre.ethers.parseUnits("100", 6),  // 100 USDC minimum
    hre.ethers.parseUnits("100000", 6), // 100,000 USDC maximum
    feeCollector
  );
  await tx3.wait();
  console.log("   ✅ Paramètres configurés");

  // 9. Déployer BondingCurve (optionnel pour tests initiaux)
  console.log("\n9. Déploiement du BondingCurve...");
  const BondingCurve = await hre.ethers.getContractFactory("BondingCurve");
  const bondingCurve = await BondingCurve.deploy();
  await bondingCurve.waitForDeployment();
  const bondingCurveAddress = await bondingCurve.getAddress();
  console.log(`   ✅ BondingCurve déployé à: ${bondingCurveAddress}`);

  // 10. Déployer DynamicTranche (optionnel pour tests initiaux)
  console.log("\n10. Déploiement du DynamicTranche...");
  const DynamicTranche = await hre.ethers.getContractFactory("DynamicTranche");
  const dynamicTranche = await DynamicTranche.deploy(
    0, // poolId 0 pour test
    loanPoolAddress,
    "PoolSync Tranche Token",
    "PSTT"
  );
  await dynamicTranche.waitForDeployment();
  const dynamicTrancheAddress = await dynamicTranche.getAddress();
  console.log(`   ✅ DynamicTranche déployé à: ${dynamicTrancheAddress}`);

  // 11. Préparer des tokens pour les tests
  console.log("\n11. Préparation des tokens de test...");
  
  // Créer quelques comptes de test
  const testAccounts = [];
  for (let i = 0; i < 3; i++) {
    const wallet = hre.ethers.Wallet.createRandom().connect(deployer.provider);
    testAccounts.push({
      address: wallet.address,
      privateKey: wallet.privateKey
    });
  }
  
  // Mint des tokens pour les comptes de test
  for (const account of testAccounts) {
    const mintAmount = hre.ethers.parseUnits("10000", 6); // 10,000 USDC
    await stablecoin.mint(account.address, mintAmount);
    console.log(`   💰 ${account.address.slice(0, 8)}... : ${hre.ethers.formatUnits(mintAmount, 6)} USDC mintés`);
  }
  
  // Mint aussi pour le déployeur
  await stablecoin.mint(deployer.address, hre.ethers.parseUnits("50000", 6));
  console.log(`   💰 ${deployer.address.slice(0, 8)}... : 50,000 USDC mintés`);

  // 12. Approve LoanPool pour dépenser les tokens
  console.log("\n12. Configuration des approvals...");
  for (const account of [...testAccounts, { address: deployer.address }]) {
    // Pour les testAccounts, on ne peut pas appeler approve directement
    // On utilise le déployeur pour les approuver
    const approveAmount = hre.ethers.parseUnits("100000", 6);
    await stablecoin.mintAndApprove(account.address, approveAmount, loanPoolAddress);
  }
  console.log("   ✅ Approvals configurés");

  console.log("\n" + "=".repeat(70));
  console.log("🎉 DÉPLOIEMENT COMPLET TERMINÉ !");
  console.log("=".repeat(70));
  
  console.log("\n📋 RÉCAPITULATIF DES ADRESSES:");
  console.log("═".repeat(70));
  console.log(`MockERC20 (USDC):         ${stablecoinAddress}`);
  console.log(`RiskEngine:               ${riskEngineAddress}`);
  console.log(`LoanPool:                 ${loanPoolAddress}`);
  console.log(`CriteriaFilter:           ${criteriaFilterAddress}`);
  console.log(`SpecialOfferManager:      ${specialOfferManagerAddress}`);
  console.log(`BondingCurve:             ${bondingCurveAddress}`);
  console.log(`DynamicTranche:           ${dynamicTrancheAddress}`);
  console.log(`Fee Collector:            ${feeCollector}`);
  
  console.log("\n👥 COMPTES DE TEST:");
  console.log("═".repeat(70));
  console.log(`Déployeur:                ${deployer.address}`);
  for (let i = 0; i < testAccounts.length; i++) {
    console.log(`Test Account ${i + 1}:         ${testAccounts[i].address}`);
  }
  
  console.log("\n🚀 POUR COMMENCER LES TESTS:");
  console.log("═".repeat(70));
  console.log("1. Exécutez les tests unitaires:");
  console.log("   npx hardhat test");
  console.log("\n2. Créez un premier pool de test:");
  console.log("   npx hardhat run scripts/create-test-pool.js");
  console.log("\n3. Pour interagir avec les contrats:");
  console.log(`   Utilisez l'adresse LoanPool: ${loanPoolAddress}`);
  
  console.log("\n💡 ASTUCES POUR LES TESTS:");
  console.log("═".repeat(70));
  console.log("• Tous les contrats utilisent le MockERC20 (6 décimales)");
  console.log("• Les comptes de test ont 10,000 USDC chacun");
  console.log("• Le déployeur a 50,000 USDC et peut créer des pools");
  console.log("• Les approvals sont déjà configurés pour LoanPool");

  // Sauvegarder les adresses dans un fichier pour référence
  const addresses = {
    stablecoin: stablecoinAddress,
    riskEngine: riskEngineAddress,
    loanPool: loanPoolAddress,
    criteriaFilter: criteriaFilterAddress,
    specialOfferManager: specialOfferManagerAddress,
    bondingCurve: bondingCurveAddress,
    dynamicTranche: dynamicTrancheAddress,
    feeCollector: feeCollector,
    testAccounts: testAccounts.map(a => a.address),
    deployer: deployer.address,
    network: hre.network.name,
    timestamp: new Date().toISOString()
  };

  const fs = require('fs');
  fs.writeFileSync(
    'deployment-addresses.json',
    JSON.stringify(addresses, null, 2)
  );
  
  console.log("\n📄 Les adresses ont été sauvegardées dans 'deployment-addresses.json'");
}

main().catch((error) => {
  console.error("❌ Erreur lors du déploiement:");
  console.error(error);
  process.exitCode = 1;
});