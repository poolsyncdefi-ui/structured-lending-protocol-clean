# Structured Lending Protocol v0.5

DeFi lending protocol with dynamic tranches, risk management, and governance.

## 🏗️ Architecture

### Core Contracts
- `LoanPool.sol` - Main lending pool
- `RiskEngine.sol` - Risk assessment engine  
- `BondingCurve.sol` - Dynamic pricing
- `DynamicTranche.sol` - Tranche management

### Governance
- `GovernanceDAO.sol` - DAO governance
- `ReputationToken.sol` - Reputation system

### Security
- `AccessController.sol` - Role-based access
- `KYCRegistry.sol` - KYC compliance
- `EmergencyExecutor.sol` - Emergency procedures

## 🚀 Quick Start

```bash
# Install dependencies
npm install

# Run tests
npx hardhat test

# Deploy to testnet
npx hardhat run scripts/deploy.js --network testnet