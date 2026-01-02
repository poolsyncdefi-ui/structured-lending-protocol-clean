# 1. Configuration initiale
npm init -y
npm install --save-dev hardhat @nomiclabs/hardhat-ethers ethers
npm install @openzeppelin/contracts @chainlink/contracts

# 2. Structure de projet
contracts/
├── core/
│   ├── LoanPool.sol
│   └── LoanNFT.sol
├── risk/
│   ├── RiskEngine.sol
│   └── DynamicTranche.sol
├── insurance/
│   ├── InsuranceModule.sol
│   └── DecentralizedGuaranteeFund.sol
└── governance/
    ├── GovernanceDAO.sol
    └── AccessController.sol

# 3. Tests unitaires
test/
├── unit/
│   ├── LoanPool.test.js
│   └── RiskEngine.test.js
└── integration/
    └── FullWorkflow.test.js