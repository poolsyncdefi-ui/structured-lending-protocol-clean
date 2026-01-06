// Phase 1: Testnet
npx hardhat run scripts/deploy-testnet.js --network mumbai

// Phase 2: Mainnet avec limites
npx hardhat run scripts/deploy-mainnet-phase1.js --network polygon

// Phase 3: Pleine capacité
npx hardhat run scripts/deploy-mainnet-full.js --network polygon