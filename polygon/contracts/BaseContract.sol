// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.4;

import "@openzeppelin/contracts-upgradeable/utils/ContextUpgradeable.sol";
import "@openzeppelin/contracts-upgradeable/proxy/utils/Initializable.sol";
import "./ITrustVaultFactory.sol";
import "../interfaces/ITidalFinance.sol";
import "./libraries/VaultLib.sol";

abstract contract BaseContract is Initializable, ContextUpgradeable
{
 
    address internal _itrustVaultFactory; // itrust vault factory address
    mapping(address => mapping(address => VaultLib.EpochData[])) internal _vaultAccountStakings; // vault => account => stakings
    mapping(address => mapping(address => mapping(uint256 => uint256))) internal _vaultAccountPendingStakes; // vault => account => pending stakes
    mapping(address => mapping(address => VaultLib.EpochData[])) internal _vaultAccountUnstakings; // vault => account => unstakings
    mapping(address => mapping(address => uint256)) internal _vaultAccountUnstakingIndex;// vault => account => unstaking index
    mapping(address => VaultLib.EpochData[]) internal _vaultStakings; // vault => stakings
    mapping(address => mapping(uint256 => VaultLib.Round)) internal _roundData; //vault => week => Round
    mapping (address => address[]) internal _vaultStakerAddresses; //vault => staker addresses

    /**
     * @dev Returns the itrust vault factory contract instance
     *
     * @return ITrustVaultFactory itrust vault factory contract
     */
    function _itrustVaultFactoryContract() internal view returns(ITrustVaultFactory) {
        return ITrustVaultFactory(_itrustVaultFactory);
    }
    
    /**
     * @dev Returns the tidal finance contract instance
     *
     * @return ITidalFinance tidal finance contract
     */
    function _tidalContract() internal view returns(ITidalFinance) {
        return ITidalFinance(_itrustVaultFactoryContract().getContractAddress("TIDAL"));
    }

}