pragma solidity 0.7.6;

import "@openzeppelin/contracts/proxy/TransparentUpgradeableProxy.sol";
import "@openzeppelin/contracts-upgradeable/proxy/Initializable.sol";
import "./3rdParty/interfaces/INXMMaster.sol";
import {IFAStakingData as StakingData} from "./../phase2/vaults/IFAStakingData.sol";
import {IFAVaultStaking as VaultStaking} from "./../phase2/vaults/IFAVaultStaking.sol";

contract ITrustVaultFactoryV2 is Initializable {
  
  address[] internal _VaultProxies;
  mapping (address => bool) internal _AdminList;
  mapping (address => bool) internal _TrustedSigners;
  mapping(address => bool) internal _VaultStatus;
  address internal _roundDataImplementationAddress; // Deprecated
  address internal _stakeDataImplementationAddress; // Deprecated
  address internal _stakingDataAddress; // Deprecated
  address internal _burnAddress; // Deprecated
  address internal _governanceDistributionAddress; // Deprecated
  address internal _governanceTokenAddress; // Deprecated
  address internal _stakingCalculationAddress; // Deprecated
  mapping (address => address) internal _vaultStakingAddress;
  /*
   * RD => RoundDataImplementation
   * IFARD => IFA RoundDataImplementation
   * SD => StakingData
   * IFASD => IFA StakingData
   * SI => StakeDataImplementation
   * IFASI => IFA StakeDataImplementation
   * GT => GovernanceToken
   * SC => StakingCalculation
   * IFASC => IFA StakingCalculation
   * BD => BurnData
   * IFABD => IFABurnData
   * GD => GovernanceDistribution
   * INXM = iNXM Address
   */
  mapping(bytes5 => address) internal _ContractAddressList;

  function initializeAddresses(
      address admin, 
      address trustedSigner, 
      address roundDataImplementationAddress, 
      address stakeDataImplementationAddress, 
      address governanceTokenAddress,
      address stakingCalculationAddress
    ) initializer external {
    require(admin != address(0));
    _AdminList[admin] = true;
    _AdminList[msg.sender] = true;
    _TrustedSigners[trustedSigner] = true;
    _roundDataImplementationAddress = roundDataImplementationAddress;
    _stakeDataImplementationAddress = stakeDataImplementationAddress;
    _governanceTokenAddress = governanceTokenAddress;
    _stakingCalculationAddress = stakingCalculationAddress;
  }

  modifier onlyAdmin() {
    require(_AdminList[msg.sender] == true, "Not Factory Admin");
    _;
  }

  function createVault(
    address contractAddress, 
    address vaultStakingContractAddress,
    bytes memory data,
    bool isStrategyVault
  ) external onlyAdmin {
    TransparentUpgradeableProxy proxy = new TransparentUpgradeableProxy(contractAddress, msg.sender, data );
    require(address(proxy) != address(0));
    bytes memory vaultStakingData = abi.encodeWithSelector(
        VaultStaking.initialize.selector,                       
        address(this), 
        address(proxy),
        isStrategyVault
    );
    TransparentUpgradeableProxy vaultStakingProxy = new TransparentUpgradeableProxy(vaultStakingContractAddress, msg.sender, vaultStakingData );
    _VaultProxies.push(address(proxy));
    _VaultStatus[address(proxy)] = true;
    _vaultStakingAddress[address(proxy)] = address(vaultStakingProxy);
    StakingData stakingDataContract = StakingData(getContractAddress("IFASD"));
    stakingDataContract.addVault(address(proxy));
  }

  function getVaultaddresses() external view returns (address[] memory vaults, bool[] memory status) {

    vaults = _VaultProxies;
    status = new bool[](vaults.length);

    for(uint i = 0; i < vaults.length; i++){
      status[i] = _VaultStatus[vaults[i]];
    }

    return (vaults, status);
  }

  function pauseVault(address vaultAddress) external onlyAdmin {
    _VaultStatus[vaultAddress] = false;
  }

  function unPauseVault(address vaultAddress) external onlyAdmin {
    _VaultStatus[vaultAddress] = true;
  }

  function addAdminAddress(address newAddress) external onlyAdmin {
      require(_AdminList[newAddress] == false, "Already Admin");
      _AdminList[newAddress] = true;
  }

  /**
    * @dev revoke admin
    */
  function revokeAdminAddress(address newAddress) external onlyAdmin {
      require(msg.sender != newAddress);
      _AdminList[newAddress] = false;
  }

  function addTrustedSigner(address newAddress) external onlyAdmin{
      require(_TrustedSigners[newAddress] == false);
      _TrustedSigners[newAddress] = true;
  }

  function isTrustedSignerAddress(address account) external view returns (bool) {
      return _TrustedSigners[account] == true;
  }

  function requireTrustedSigner(address account) external view returns (bool) {
      require(_TrustedSigners[account] == true, "NTS");
      return true;
  }

  function getRoundDataImplementationAddress() external view returns(address){
      return getContractAddress("RD");
  }

  function getStakeDataImplementationAddress() external view returns(address){
      return getContractAddress("SI");
  }

  function getStakingDataAddress() public view returns(address){
      return getContractAddress("SD");
  }

  function isStakingDataAddress(address addressToCheck) external view returns (bool) {
      return getStakingDataAddress() == addressToCheck
              || getContractAddress("IFASD") == addressToCheck;
  }

  function getBurnAddress() public view returns(address){
      return getContractAddress("BD");
  }

  function isBurnAddress(address addressToCheck) external view returns (bool) {
      return getBurnAddress() == addressToCheck
              || getContractAddress("IFABD") == addressToCheck;
  }

  function getGovernanceDistributionAddress() external view returns(address){
      return getContractAddress("GD");
  }

  function getGovernanceTokenAddress() external view returns(address){
      return getContractAddress("GT");
  }

  function getStakingCalculationsAddress() external view returns(address){
      return getContractAddress("SC");
  }

  function getVaultStakingAddress(address vault) external view returns(address){
      return _vaultStakingAddress[vault];
  }

  function isValidVaultStakingAddress(address vault, address vaultStakingAddress) external view returns(bool){
      return _vaultStakingAddress[vault] == vaultStakingAddress && isActiveVault(vault);
  }
  
  function getNexusPoolAddress() external view returns(address payable){
    return INxmMaster(getContractAddress("INXM")).getLatestAddress("PS");
  }

  function updateContractAddress(bytes5 key, address newAddress) public onlyAdmin {
      _ContractAddressList[key] = newAddress;
  }

  function getContractAddress(bytes5 key) public view returns (address) {
      return _ContractAddressList[key];
  }

  /**
    * @dev revoke admin
    */
  function revokeTrustedSigner(address newAddress) external onlyAdmin {
      require(msg.sender != newAddress);
      _TrustedSigners[newAddress] = false;
  }

  function isAddressTrustedSigner(address signerAddress) external view returns (bool) {
      return _TrustedSigners[signerAddress];
  }

  function isAdmin() external view returns (bool) {
      return isAddressAdmin(msg.sender);
  }

  function isAddressAdmin(address account) public view returns (bool) {
      return _AdminList[account] == true;
  }

  function isActiveVault(address vaultAddress) public view returns (bool) {
    return _VaultStatus[vaultAddress] == true;
  }  

  /*
   * RD => RoundDataImplementation
   * IFARD => IFA RoundDataImplementation
   * SD => StakeData
   * IFASD => IFA StakeData
   * SI => StakeDataImplementation
   * IFASI => IFA StakeDataImplementation
   * GT => GovernanceToken
   * SC => StakingCalculation
   * IFASC => IFA StakingCalculation
   * BD => BurnData
   * IFABD => IFABurnData
   * GD => GovernanceDistribution
   * INXM = iNXM Address
   */
  function setAddresses(address IFARD, address IFASD, address IFASI, address IFASC, address IFABD, address INXM) external onlyAdmin {
      require(_roundDataImplementationAddress != address(0)); // only to be called once

      updateContractAddress("RD", _roundDataImplementationAddress);
      updateContractAddress("SD", _stakingDataAddress);
      updateContractAddress("SI", _stakeDataImplementationAddress);
      updateContractAddress("GT", _governanceTokenAddress);
      updateContractAddress("SC", _stakingCalculationAddress);
      updateContractAddress("BD", _burnAddress);
      updateContractAddress("GD", _governanceDistributionAddress);

      _roundDataImplementationAddress = address(0);
      _stakingDataAddress = address(0);
      _stakeDataImplementationAddress = address(0);
      _governanceTokenAddress = address(0);
      _stakingCalculationAddress = address(0);
      _burnAddress = address(0);
      _governanceDistributionAddress = address(0);

      updateContractAddress("IFARD", IFARD);
      updateContractAddress("IFASD", IFASD);
      updateContractAddress("IFASI", IFASI);
      updateContractAddress("IFASC", IFASC);
      updateContractAddress("IFABD", IFABD);
      updateContractAddress("INXM", INXM);
  }
}