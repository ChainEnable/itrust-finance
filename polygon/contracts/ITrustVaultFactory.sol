// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.4;

import "@openzeppelin/contracts/proxy/transparent/TransparentUpgradeableProxy.sol";
import "@openzeppelin/contracts-upgradeable/proxy/utils/Initializable.sol";

contract ITrustVaultFactory is Initializable {
  
  address[] internal _vaultProxies; // Array of vault proxies
  mapping (address => bool) internal _adminList; // mapping of account admin flags
  mapping (address => bool) internal _trustedSigners; // mapping of trusted signer flags
  mapping(address => bool) internal _vaultStatus; // mapping of vault status flags
  mapping (address => address) internal _vaultStakingAddress; // mapping of vault staking addresses
  /*
   * @dev mapping of key => contract addresses
   *
   * TIDAL => Tidal sell address
   * RS => Round Staking contract
   * RM => Round Manager Address
   * BM => Burn Manager address
   * GT => governance token
   */
  mapping(bytes5 => address) internal _ContractAddressList;

  /**
   * @dev initialize
   *
   * @param admin default admin address
   * @param trustedSigner default trusted signer address
   */
  function initialize (
      address admin, 
      address trustedSigner
    ) initializer external {
    require(admin != address(0));
    _adminList[admin] = true;
    _adminList[msg.sender] = true;
    _trustedSigners[trustedSigner] = true;
  }

  /**
   * @dev modifier to only allow msg senders with the correct admin flag
   *      access
   */
  modifier onlyAdmin() {
    require(_adminList[msg.sender] == true, "Not Factory Admin");
    _;
  }

  /**
   * @dev Creates a new instance of a vault for the supplies implementation address
   *
   * @param contractAddress implementation contract address
   * @param data data to initialize the vault
   */
  function createVault(
    address contractAddress,
    bytes memory data
  ) external onlyAdmin {
    TransparentUpgradeableProxy proxy = new TransparentUpgradeableProxy(contractAddress, msg.sender, data );
    require(address(proxy) != address(0), "HMM");
    _vaultProxies.push(address(proxy));
    _vaultStatus[address(proxy)] = true;
  }

  /**
   * @dev Returns an array of vault addresses along with the statuses
   *
   * @return vaults address[]
   * @return status bool[]
   */
  function getVaultaddresses() external view returns (address[] memory vaults, bool[] memory status) {

    vaults = _vaultProxies;
    status = new bool[](vaults.length);

    for(uint i = 0; i < vaults.length; i++){
      status[i] = _vaultStatus[vaults[i]];
    }

    return (vaults, status);
  }

  /**
   * @dev Admin only function to pause a vault
   *
   * @param vaultAddress address of vault to pause
   */
  function pauseVault(address vaultAddress) external onlyAdmin {
    _vaultStatus[vaultAddress] = false;
  }

  /**
   * @dev Admin only function to unpause a vault
   *
   * @param vaultAddress address of vault to unpause
   */
  function unPauseVault(address vaultAddress) external onlyAdmin {
    _vaultStatus[vaultAddress] = true;
  }

  /**
   * @dev Admin only function to add a new admin to the list of admins
   *
   * @param newAddress address to add
   */
  function addAdminAddress(address newAddress) external onlyAdmin {
      require(_adminList[newAddress] == false, "Already Admin");
      _adminList[newAddress] = true;
  }

  /**
   * @dev Admin only function to remove an admin from the list of admins
   *
   * @param newAddress address to remove
   */
  function revokeAdminAddress(address newAddress) external onlyAdmin {
      require(msg.sender != newAddress);
      _adminList[newAddress] = false;
  }

  /**
   * @dev Admin only function to add a new trusted signer to the list of trusted signers
   *
   * @param newAddress address to add
   */
  function addTrustedSigner(address newAddress) external onlyAdmin{
      require(_trustedSigners[newAddress] == false);
      _trustedSigners[newAddress] = true;
  }

  /**
   * @dev Ensures the supplied address is a trusted signer
   *
   * @param account address to remove
   */
  function requireTrustedSigner(address account) external view returns (bool) {
      require(_trustedSigners[account] == true, "NTS");
      return true;
  }

  /**
   * @dev Admin only function to remove a trusted signer from the list of trusted signers
   *
   * @param newAddress address to remove
   */
  function revokeTrustedSigner(address newAddress) external onlyAdmin {
      require(msg.sender != newAddress);
      _trustedSigners[newAddress] = false;
  }

  /**
   * @dev Admin only function to update the contract address for a given key
   *
   * @param key key to update
   * @param newAddress address to be set against the key
   */
  function updateContractAddress(bytes5 key, address newAddress) public onlyAdmin {
      _ContractAddressList[key] = newAddress;
  }

  /**
   * @dev Returns the contract address for the given key
   *
   * @param key key to lookup
   * @return address address for supplied key
   */
  function getContractAddress(bytes5 key) public view returns (address) {
      return _ContractAddressList[key];
  }

  /**
   * @dev Checks if supplied key and contract address match
   *
   * @param addressToCheck address to compare
   * @param key key to compare
   * @return bool result of the lookup
   */
  function isContractAddress(address addressToCheck, bytes5 key) public view returns (bool) {
      return _ContractAddressList[key] == addressToCheck;
  }

  /**
   * @dev Checks if the supplied address is a trusted signer
   *
   * @param signerAddress address to check
   * @return bool result of the check
   */
  function isAddressTrustedSigner(address signerAddress) external view returns (bool) {
      return _trustedSigners[signerAddress];
  }

  /**
   * @dev Checks if the supplied address is an admin
   *
   * @param account address to check
   * @return bool result of the check
   */
  function isAddressAdmin(address account) public view returns (bool) {
      return _adminList[account] == true;
  }

  /**
   * @dev Checks if the supplied vault address is active
   *
   * @param vaultAddress address to check
   * @return bool result of the check
   */
  function isActiveVault(address vaultAddress) public view returns (bool) {
    return _vaultStatus[vaultAddress] == true;
  }  

}