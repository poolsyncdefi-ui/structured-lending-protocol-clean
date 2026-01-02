// RegulatoryReporting.sol
// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import "@openzeppelin/contracts/access/AccessControl.sol";
import "@openzeppelin/contracts/utils/cryptography/ECDSA.sol";

contract RegulatoryReporting is AccessControl {
    using ECDSA for bytes32;
    
    // Standards réglementaires
    enum ReportType {
        TRANSACTION_REPORT,    // Rapport de transaction
        SUSPICIOUS_ACTIVITY,   // Activité suspecte
        TAX_REPORT,           // Rapport fiscal
        SANCTIONS_SCREENING,  // Vérification des sanctions
        PEP_SCREENING,        // Vérification des PEP
        RISK_ASSESSMENT,      // Évaluation des risques
        ANNUAL_COMPLIANCE,    // Conformité annuelle
        AUDIT_TRAIL          // Piste d'audit
    }
    
    enum Jurisdiction {
        EU_MICA,              // UE - MiCA
        US_SEC,               // USA - SEC
        US_CFTC,              // USA - CFTC
        UK_FCA,               // UK - FCA
        SG_MAS,               // Singapore - MAS
        CH_HKMA,              // Hong Kong - HKMA
        JP_FSA,               // Japan - FSA
        AU_ASIC,              // Australia - ASIC
        CH_FINMA              // Switzerland - FINMA
    }
    
    // Structure de rapport
    struct RegulatoryReport {
        uint256 reportId;
        ReportType reportType;
        Jurisdiction jurisdiction;
        string referenceNumber;
        uint256 periodStart;
        uint256 periodEnd;
        bytes32 dataHash;     // Hash des données sur IPFS/Arweave
        address generatedBy;
        uint256 generatedAt;
        address submittedBy;
        uint256 submittedAt;
        string submissionId;  // ID de soumission externe
        bool isVerified;
        bytes auditorSignature;
        ReportStatus status;
    }
    
    // Structure de donnée réglementaire
    struct RegulatoryData {
        address entity;
        string entityType;    // "BORROWER", "LENDER", "INSURER", etc.
        string countryCode;
        uint256 riskScore;
        uint256 totalVolume;
        uint256 transactionCount;
        uint256 suspiciousCount;
        uint256 lastUpdated;
    }
    
    // Variables
    mapping(uint256 => RegulatoryReport) public reports;
    mapping(address => RegulatoryData) public entityData;
    mapping(Jurisdiction => uint256) public jurisdictionRequirements;
    mapping(string => bool) public submittedReports; // referenceNumber => submitted
    
    uint256 public reportCounter;
    uint256 public reportingInterval = 90 days;
    uint256 public thresholdAmount = 10000 * 1e18; // Seuil de reporting
    
    // Adresses autorisées
    address public auditorAddress;
    address public regulatorAddress;
    
    // Rôles
    bytes32 public constant COMPLIANCE_OFFICER = keccak256("COMPLIANCE_OFFICER");
    bytes32 public constant AUDITOR = keccak256("AUDITOR");
    bytes32 public constant REGULATOR = keccak256("REGULATOR");
    
    // Événements
    event ReportGenerated(
        uint256 indexed reportId,
        ReportType reportType,
        Jurisdiction jurisdiction,
        address indexed generatedBy,
        uint256 timestamp
    );
    
    event ReportSubmitted(
        uint256 indexed reportId,
        string referenceNumber,
        address indexed submittedBy,
        uint256 timestamp
    );
    
    event ReportVerified(
        uint256 indexed reportId,
        address indexed auditor,
        uint256 timestamp
    );
    
    event SuspiciousActivityReported(
        address indexed entity,
        string activityType,
        uint256 amount,
        address indexed reporter,
        uint256 timestamp
    );
    
    event RegulatoryDataUpdated(
        address indexed entity,
        string entityType,
        uint256 riskScore,
        uint256 timestamp
    );
    
    constructor(address _auditor, address _regulator) {
        _grantRole(DEFAULT_ADMIN_ROLE, msg.sender);
        _grantRole(COMPLIANCE_OFFICER, msg.sender);
        
        auditorAddress = _auditor;
        regulatorAddress = _regulator;
        
        _grantRole(AUDITOR, _auditor);
        _grantRole(REGULATOR, _regulator);
        
        // Initialiser les exigences par juridiction
        _initializeJurisdictionRequirements();
    }
    
    // Générer un rapport réglementaire
    function generateReport(
        ReportType reportType,
        Jurisdiction jurisdiction,
        uint256 periodStart,
        uint256 periodEnd,
        bytes32 dataHash,
        string memory referenceNumber
    ) public onlyRole(COMPLIANCE_OFFICER) returns (uint256) {
        require(periodStart < periodEnd, "Invalid period");
        require(!submittedReports[referenceNumber], "Reference number already used");
        
        uint256 reportId = ++reportCounter;
        
        reports[reportId] = RegulatoryReport({
            reportId: reportId,
            reportType: reportType,
            jurisdiction: jurisdiction,
            referenceNumber: referenceNumber,
            periodStart: periodStart,
            periodEnd: periodEnd,
            dataHash: dataHash,
            generatedBy: msg.sender,
            generatedAt: block.timestamp,
            submittedBy: address(0),
            submittedAt: 0,
            submissionId: "",
            isVerified: false,
            auditorSignature: "",
            status: ReportStatus.GENERATED
        });
        
        submittedReports[referenceNumber] = true;
        
        emit ReportGenerated(reportId, reportType, jurisdiction, msg.sender, block.timestamp);
        
        return reportId;
    }
    
    // Soumettre un rapport à un régulateur
    function submitReport(
        uint256 reportId,
        string memory submissionId,
        bytes memory regulatorSignature
    ) external onlyRole(COMPLIANCE_OFFICER) {
        RegulatoryReport storage report = reports[reportId];
        require(report.status == ReportStatus.GENERATED, "Report not in generated state");
        
        // Vérifier la signature du régulateur
        _validateRegulatorSignature(reportId, submissionId, regulatorSignature);
        
        report.submittedBy = msg.sender;
        report.submittedAt = block.timestamp;
        report.submissionId = submissionId;
        report.status = ReportStatus.SUBMITTED;
        
        emit ReportSubmitted(reportId, submissionId, msg.sender, block.timestamp);
    }
    
    // Rapporter une activité suspecte
    function reportSuspiciousActivity(
        address entity,
        string memory activityType,
        uint256 amount,
        string memory description,
        bytes memory evidenceHash
    ) external onlyRole(COMPLIANCE_OFFICER) {
        // Mettre à jour les données de l'entité
        RegulatoryData storage data = entityData[entity];
        data.suspiciousCount++;
        data.riskScore = _calculateRiskScore(data);
        data.lastUpdated = block.timestamp;
        
        // Générer un rapport automatique
        bytes32 dataHash = keccak256(abi.encodePacked(
            entity,
            activityType,
            amount,
            description,
            evidenceHash
        ));
        
        generateReport(
            ReportType.SUSPICIOUS_ACTIVITY,
            _getEntityJurisdiction(entity),
            block.timestamp - 1 days,
            block.timestamp,
            dataHash,
            string(abi.encodePacked("SAR-", _toString(block.timestamp)))
        );
        
        emit SuspiciousActivityReported(
            entity,
            activityType,
            amount,
            msg.sender,
            block.timestamp
        );
    }
    
    // Mettre à jour les données réglementaires d'une entité
    function updateEntityData(
        address entity,
        string memory entityType,
        string memory countryCode,
        uint256 totalVolume,
        uint256 transactionCount
    ) external onlyRole(COMPLIANCE_OFFICER) {
        RegulatoryData storage data = entityData[entity];
        
        data.entity = entity;
        data.entityType = entityType;
        data.countryCode = countryCode;
        data.totalVolume = totalVolume;
        data.transactionCount = transactionCount;
        data.riskScore = _calculateRiskScore(data);
        data.lastUpdated = block.timestamp;
        
        // Vérifier si un rapport est nécessaire
        _checkReportingRequirements(entity, totalVolume);
        
        emit RegulatoryDataUpdated(entity, entityType, data.riskScore, block.timestamp);
    }
    
    // Vérifier et générer des rapports automatiques
    function checkAndGenerateReports() external onlyRole(COMPLIANCE_OFFICER) {
        uint256 currentPeriod = block.timestamp / reportingInterval;
        uint256 lastReportedPeriod = _getLastReportedPeriod();
        
        if (currentPeriod > lastReportedPeriod) {
            // Générer les rapports périodiques
            _generatePeriodicReports(currentPeriod);
        }
    }
    
    // Fonctions internes
    function _initializeJurisdictionRequirements() private {
        jurisdictionRequirements[Jurisdiction.EU_MICA] = 30 days;
        jurisdictionRequirements[Jurisdiction.US_SEC] = 90 days;
        jurisdictionRequirements[Jurisdiction.UK_FCA] = 30 days;
        jurisdictionRequirements[Jurisdiction.SG_MAS] = 90 days;
        // ... autres juridictions
    }
    
    function _validateRegulatorSignature(
        uint256 reportId,
        string memory submissionId,
        bytes memory signature
    ) private view {
        bytes32 messageHash = keccak256(abi.encodePacked(
            reportId,
            submissionId,
            block.chainid,
            address(this),
            "REGULATOR_SUBMISSION"
        ));
        
        bytes32 ethSignedMessageHash = messageHash.toEthSignedMessageHash();
        address recovered = ethSignedMessageHash.recover(signature);
        
        require(recovered == regulatorAddress, "Invalid regulator signature");
    }
    
    function _calculateRiskScore(RegulatoryData memory data) private pure returns (uint256) {
        uint256 score = 0;
        
        // Facteur volume
        if (data.totalVolume > 1000000 * 1e18) score += 300;
        else if (data.totalVolume > 100000 * 1e18) score += 200;
        else if (data.totalVolume > 10000 * 1e18) score += 100;
        
        // Facteur transactions suspectes
        score += data.suspiciousCount * 100;
        
        // Facteur pays (simplifié)
        if (keccak256(bytes(data.countryCode)) == keccak256(bytes("US"))) score += 50;
        else if (keccak256(bytes(data.countryCode)) == keccak256(bytes("UK"))) score += 50;
        else score += 100;
        
        return score > 1000 ? 1000 : score;
    }
    
    function _getEntityJurisdiction(address entity) private view returns (Jurisdiction) {
        RegulatoryData memory data = entityData[entity];
        
        // Logique simplifiée pour déterminer la juridiction
        if (keccak256(bytes(data.countryCode)) == keccak256(bytes("US"))) {
            return Jurisdiction.US_SEC;
        } else if (keccak256(bytes(data.countryCode)) == keccak256(bytes("UK"))) {
            return Jurisdiction.UK_FCA;
        } else if (keccak256(bytes(data.countryCode)) == keccak256(bytes("SG"))) {
            return Jurisdiction.SG_MAS;
        } else {
            return Jurisdiction.EU_MICA; // Par défaut
        }
    }
    
    function _checkReportingRequirements(address entity, uint256 volume) private {
        if (volume >= thresholdAmount) {
            // Générer un rapport de transaction important
            generateReport(
                ReportType.TRANSACTION_REPORT,
                _getEntityJurisdiction(entity),
                block.timestamp - 1 days,
                block.timestamp,
                keccak256(abi.encodePacked(entity, volume)),
                string(abi.encodePacked("LTR-", _toString(block.timestamp)))
            );
        }
    }
    
    function _generatePeriodicReports(uint256 period) private {
        // Générer les rapports pour toutes les juridictions
        for (uint8 i = 0; i <= uint8(type(Jurisdiction).max); i++) {
            Jurisdiction jurisdiction = Jurisdiction(i);
            
            generateReport(
                ReportType.ANNUAL_COMPLIANCE,
                jurisdiction,
                period * reportingInterval,
                (period + 1) * reportingInterval,
                keccak256(abi.encodePacked(period, jurisdiction)),
                string(abi.encodePacked("PERIODIC-", _toString(period), "-", _toString(i)))
            );
        }
    }
    
    function _getLastReportedPeriod() private view returns (uint256) {
        // À implémenter: récupérer la dernière période reportée
        return 0;
    }
    
    function _toString(uint256 value) private pure returns (string memory) {
        if (value == 0) return "0";
        
        uint256 temp = value;
        uint256 digits;
        while (temp != 0) {
            digits++;
            temp /= 10;
        }
        
        bytes memory buffer = new bytes(digits);
        while (value != 0) {
            digits -= 1;
            buffer[digits] = bytes1(uint8(48 + uint256(value % 10)));
            value /= 10;
        }
        
        return string(buffer);
    }
    
    // Getters
    function getEntityRiskScore(address entity) external view returns (uint256) {
        return entityData[entity].riskScore;
    }
    
    function getPendingReports() external view returns (uint256[] memory) {
        uint256 count = 0;
        
        // Compter les rapports en attente
        for (uint256 i = 1; i <= reportCounter; i++) {
            if (reports[i].status == ReportStatus.GENERATED) {
                count++;
            }
        }
        
        // Collecter les IDs
        uint256[] memory pending = new uint256[](count);
        uint256 index = 0;
        
        for (uint256 i = 1; i <= reportCounter; i++) {
            if (reports[i].status == ReportStatus.GENERATED) {
                pending[index] = i;
                index++;
            }
        }
        
        return pending;
    }
    
    function getJurisdictionReportCount(Jurisdiction jurisdiction) 
        external 
        view 
        returns (uint256) 
    {
        uint256 count = 0;
        
        for (uint256 i = 1; i <= reportCounter; i++) {
            if (reports[i].jurisdiction == jurisdiction) {
                count++;
            }
        }
        
        return count;
    }
    
    // Enums et statuts
    enum ReportStatus {
        GENERATED,
        SUBMITTED,
        VERIFIED,
        REJECTED,
        ARCHIVED
    }
}