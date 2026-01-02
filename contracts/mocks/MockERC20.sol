// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import "@openzeppelin/contracts/token/ERC20/ERC20.sol";

/**
 * @title MockERC20 - Token ERC20 mock pour tests
 * @notice Version simplifiée d'un stablecoin (USDC, DAI) pour tests locaux et testnet
 * @dev Inclut des fonctions spéciales pour le testing (mint, burn, etc.)
 */
contract MockERC20 is ERC20 {
    // Propriétaire du contrat (peut mint/burn)
    address public owner;
    
    // Décimals par défaut (18 comme ETH, ou 6 comme USDC)
    uint8 private _decimals;
    
    // Événements spéciaux pour tests
    event Minted(address indexed to, uint256 amount);
    event Burned(address indexed from, uint256 amount);
    event OwnershipTransferred(address indexed previousOwner, address indexed newOwner);
    
    /**
     * @notice Constructeur du MockERC20
     * @param name Nom du token (ex: "Mock USDC")
     * @param symbol Symbole (ex: "mUSDC")
     * @param decimals_ Nombre de décimales (6 pour USDC, 18 pour DAI)
     */
    constructor(
        string memory name,
        string memory symbol,
        uint8 decimals_
    ) ERC20(name, symbol) {
        owner = msg.sender;
        _decimals = decimals_;
        
        // Mint initial pour le déployeur
        _mint(msg.sender, 1000000 * 10 ** decimals_);
    }
    
    /**
     * @notice Retourne le nombre de décimales
     */
    function decimals() public view virtual override returns (uint8) {
        return _decimals;
    }
    
    /**
     * @notice Mint de nouveaux tokens (seulement owner)
     * @dev Pour simuler des faucets ou des dépôts
     */
    function mint(address to, uint256 amount) external {
        require(msg.sender == owner, "MockERC20: Only owner can mint");
        require(to != address(0), "MockERC20: Mint to zero address");
        
        _mint(to, amount);
        emit Minted(to, amount);
    }
    
    /**
     * @notice Burn des tokens (seulement owner)
     * @dev Pour nettoyer ou simuler des frais
     */
    function burn(address from, uint256 amount) external {
        require(msg.sender == owner, "MockERC20: Only owner can burn");
        require(from != address(0), "MockERC20: Burn from zero address");
        
        _burn(from, amount);
        emit Burned(from, amount);
    }
    
    /**
     * @notice Mint avec approval automatique
     * @dev Utile pour les tests d'intégration
     */
    function mintAndApprove(address to, uint256 amount, address spender) external {
        require(msg.sender == owner, "MockERC20: Only owner");
        
        _mint(to, amount);
        _approve(to, spender, amount);
        
        emit Minted(to, amount);
    }
    
    /**
     * @notice Transfère la propriété
     */
    function transferOwnership(address newOwner) external {
        require(msg.sender == owner, "MockERC20: Only owner");
        require(newOwner != address(0), "MockERC20: New owner is zero address");
        
        emit OwnershipTransferred(owner, newOwner);
        owner = newOwner;
    }
    
    /**
     * @notice Donne des tokens à plusieurs adresses
     * @dev Pour peupler plusieurs comptes de test rapidement
     */
    function batchMint(address[] calldata recipients, uint256[] calldata amounts) external {
        require(msg.sender == owner, "MockERC20: Only owner");
        require(recipients.length == amounts.length, "MockERC20: Arrays length mismatch");
        
        for (uint256 i = 0; i < recipients.length; i++) {
            require(recipients[i] != address(0), "MockERC20: Zero address in batch");
            _mint(recipients[i], amounts[i]);
            emit Minted(recipients[i], amounts[i]);
        }
    }
    
    /**
     * @notice Simule un transfert depuis une autre adresse (pour tests)
     * @dev Permet de tester les transferFrom sans avoir à faire approve
     */
    function transferFromSimulated(
        address sender,
        address recipient,
        uint256 amount
    ) external returns (bool) {
        require(msg.sender == owner, "MockERC20: Only owner");
        
        _transfer(sender, recipient, amount);
        return true;
    }
    
    /**
     * @notice Augmente l'allowance sans avoir à la mettre à 0 d'abord
     * @dev Contourne le problème d'approve de certains tokens
     */
    function increaseAllowance(address spender, uint256 addedValue) external returns (bool) {
        address owner_ = _msgSender();
        _approve(owner_, spender, allowance(owner_, spender) + addedValue);
        return true;
    }
    
    /**
     * @notice Donne des tokens avec différents décimals pour tests
     * @dev Utile pour tester la compatibilité avec différents stablecoins
     */
    function getMockTokens(
        uint8 decimalsType,
        uint256 amount
    ) external pure returns (uint256) {
        if (decimalsType == 6) {
            // USDC style: 6 decimals
            return amount * 10 ** 6;
        } else if (decimalsType == 18) {
            // DAI/ETH style: 18 decimals
            return amount * 10 ** 18;
        } else {
            revert("MockERC20: Unsupported decimals");
        }
    }
}