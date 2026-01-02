# 1. Installation des dépendances
npm install

# 2. Compilation des contrats
npx hardhat compile

# 3. Tests
npx hardhat test
npx hardhat coverage

# 4. Déploiement Testnet
npx hardhat run scripts/deploy-testnet.js --network polygonMumbai

# 5. Déploiement Phase 1 Mainnet
npx hardhat run scripts/deploy-mainnet-phase1.js --network polygon

# 6. Déploiement Complet Mainnet (après Phase 1)
npx hardhat run scripts/deploy-mainnet-full.js --network polygon

# 7. Vérification sur Polygonscan
npx hardhat verify --network polygon 0xCONTRACT_ADDRESS "Constructor Arg 1" "Arg 2"