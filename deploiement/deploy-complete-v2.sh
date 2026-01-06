#!/bin/bash
# deploy-complete-v2.sh

echo "🚀 Déploiement complet de l'architecture V2"

# Étape 1: Déploiement des contrats de sécurité
echo "📦 Déploiement des contrats de sécurité..."
docker-compose -f docker-compose.deployment-v2.yml up -d hardhat
sleep 10
npx hardhat run scripts/deploy-security-v2.js --network localhost

# Étape 2: Déploiement des contrats principaux
echo "🏗️  Déploiement des contrats principaux..."
npx hardhat run scripts/deploy-all-v2.js --network localhost

# Étape 3: Déploiement des contrats de conformité
echo "📋 Déploiement des contrats de conformité..."
npx hardhat run scripts/deploy-regulatory-v2.js --network localhost

# Étape 4: Configuration des proxies
echo "🔄 Configuration des proxies de mise à jour..."
npx hardhat run scripts/setup-proxies-v2.js --network localhost

# Étape 5: Lancement du monitoring
echo "📊 Lancement du monitoring..."
docker-compose -f docker-compose.monitoring-v2.yml up -d

# Étape 6: Vérification et tests
echo "🧪 Exécution des tests..."
npx hardhat test test-v2-complete.js
npx hardhat test test-security-v2.js

# Étape 7: Génération de la documentation
echo "📚 Génération de la documentation..."
npx hardhat docgen

echo "✅ Déploiement V2 terminé avec succès!"
echo "📊 Dashboard Grafana: http://localhost:3000"
echo "🔍 Prometheus: http://localhost:9090"
echo "📈 Kibana: http://localhost:5601"