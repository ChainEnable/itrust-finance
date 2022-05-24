// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.4;

import "@openzeppelin/contracts-upgradeable/token/ERC20/ERC20Upgradeable.sol";
import "@openzeppelin/contracts-upgradeable/token/ERC20/utils/SafeERC20Upgradeable.sol";
import "@openzeppelin/contracts-upgradeable/utils/ContextUpgradeable.sol";
import "@openzeppelin/contracts-upgradeable/proxy/utils/Initializable.sol";
import "../interfaces/ITidalFinance.sol";
import "./ITrustVaultFactory.sol";
import "./RoundStaking.sol";
import "./ITrustVaultFactory.sol";
import "./Vault.sol";
import "../interfaces/ITidalFinance.sol";
import "../interfaces/ITidalRegistry.sol";
import "./libraries/VaultLib.sol";

contract RoundManager is 
    Initializable, 
    ContextUpgradeable 
{
    uint256 public _weeklyItgAmount; // amount of itg to distribute for each epoch
    address internal _iTrustFactoryAddress; // address of factory contract
    mapping(address => uint) public vaultStartWeek; // maps vault to first week

    // vault => week => Round
    mapping(address => mapping(uint => VaultLib.Round)) public vaultWeekRoundData; // maps round data to a weeek and vault
    // vault => week
    mapping(address => uint ) public vaultWeek; //maps current staking week to vault
    //vault => account => ClaimedReward[]
    mapping(address => mapping(address => VaultLib.ClaimedReward[])) public vaultAccountRewardData; // used when calculating user rewards
 
    /** 
     * Initialize
     *
     * @param iTrustFactoryAddress address of factory contract
     * @param weeklyItgAmount_ amount of itg to distribute each week
     */
    function initialize(
        address iTrustFactoryAddress,
        uint256 weeklyItgAmount_
    ) initializer external {
        _iTrustFactoryAddress = iTrustFactoryAddress;
        _weeklyItgAmount = weeklyItgAmount_;
    }

    /**
     * setItgAmount 
     * sets itgAmount to be distributed
     * @param newAmount - itg amount for distribution
     */
    function setItgAmount(uint256 newAmount) external {
        _onlyAdminOrTrustedSigner();
        require(_weeklyItgAmount == 0, "ITG already set");
        _weeklyItgAmount = newAmount;        
    }

    /**
     * CanEndRound 
     * determines if end round is able to run
     * @param vaultAddress - which vault to check
     * @return true if round can be ended
     */
    function canEndRound(address vaultAddress) external view returns (bool) {
        uint256 tidalWeek = _tidalContract().getCurrentWeek();
        (uint256 tidalVaultWeek,, ) = _tidalContract().userInfo(vaultAddress);
        return  ((tidalWeek > vaultWeek[vaultAddress]) && (tidalWeek == tidalVaultWeek));
    }

    /**
     * calculateItgForVaultAndWeek 
     *  Calculates ITG distribution amount for a vault and week
     *
     * @param vaultAddress - vault to calculate for
     * @param week - week to calculate for
     * @return itg amount of itg to be distributed for vault for week
     */
    function calculateItgForVaultAndWeek(address vaultAddress, uint256 week) public view returns (uint256 itg) {
        uint totalSupplyForVault = 0;
        uint totalSupplyForAllVaults = 0; 
        (address[] memory vaults, bool[] memory status) = _itrustVaultFactoryContract().getVaultaddresses();
        for(uint16 x = 0; x < vaults.length; x++) {
            if(status[x]){
                uint vaultStaking = _roundStakingContract().getTotalSupplyForAccountWeek(vaults[x], week);
                if ( vaults[x] == vaultAddress) {
                    totalSupplyForVault = vaultStaking;
                } 
                totalSupplyForAllVaults = totalSupplyForAllVaults + vaultStaking;
            }            
        }

        itg =  totalSupplyForAllVaults > 0 && _weeklyItgAmount > 0
            ? (VaultLib.divider(
                    totalSupplyForVault,
                    totalSupplyForAllVaults,
                    18) * _weeklyItgAmount) / 10**18
            : 0;
    }    

    /**
     * endRound 
     *  ends the current round and claims rewards from tidal ready for distribution
     *
     * @param vaultAddress - vault to calculate for
     */

    function endRound(address payable vaultAddress) external {
        _onlyAdminOrTrustedSigner();
        uint tidalWeek = _tidalContract().getCurrentWeek();
        uint vaultWeek_ = vaultWeek[vaultAddress] == 0 ? tidalWeek -1 : vaultWeek[vaultAddress];
        require(_itrustVaultFactoryContract().isActiveVault(vaultAddress), "Vault Inactive or Unknown");
        require(tidalWeek > vaultWeek_, "Not Ready To End Round");

        if(vaultStartWeek[vaultAddress] == 0){
            vaultStartWeek[vaultAddress] = vaultWeek_;
        }
        
        (, uint256 premium, uint256 bonus) = _tidalContract().userInfo(vaultAddress);
        (uint premiumCommission, uint bonusCommission) = Vault(vaultAddress).endRoundClaim(premium, bonus);
        uint totalSupply = _roundStakingContract().getTotalSupplyForAccountWeek(
                vaultAddress, 
                vaultWeek_);

        ITidalRegistry registry = ITidalRegistry(_tidalContract().registry());
        uint256 itgAmount = calculateItgForVaultAndWeek(vaultAddress, vaultWeek_);
        VaultLib.Round memory roundData = VaultLib.Round({
            totalSupplyForRound: totalSupply,
            premium: VaultLib.TokenRoundData({
                amount: premium - premiumCommission, 
                commissionAmount: premiumCommission, 
                tokenPerStaking: totalSupply > 0 ? VaultLib.divider(premium - premiumCommission, totalSupply, ERC20Upgradeable(registry.baseToken()).decimals()) : 0
            }),
            bonus: VaultLib.TokenRoundData({
                amount: bonus - bonusCommission, 
                commissionAmount: bonusCommission, 
                tokenPerStaking: totalSupply > 0 ? VaultLib.divider(bonus - bonusCommission, totalSupply, ERC20Upgradeable(registry.tidalToken()).decimals()) : 0
            }),
            itg: VaultLib.TokenRoundData({
                amount: itgAmount,
                commissionAmount: 0,
                tokenPerStaking: totalSupply > 0 ? VaultLib.divider(itgAmount, totalSupply, 18) : 0
            })
        });
        
        vaultWeekRoundData[vaultAddress][vaultWeek_] = roundData;
        vaultWeek[vaultAddress] = tidalWeek; 
    }

    /**
     * getRoundData 
     *  view function to get round data for a specific week
     *
     * @param vaultAddress - vault to calculate for
     * @param week - which week to retrieve
     *
     * @return premiumAmount
     * @return premiumCommission
     * @return premiumPerStaking
     * @return bonusAmount
     * @return bonusCommission
     * @return bonusPerStaking
     * @return itgAmount
     * @return itgPerStaking
     * @return totalSupplyForRound
     */
    function getRoundData(
        address vaultAddress,
        uint256 week
    ) 
    external 
    view 
    returns(
        uint256 premiumAmount,
        uint256 premiumCommission,
        uint256 premiumPerStaking,
        uint256 bonusAmount,
        uint256 bonusCommission,
        uint256 bonusPerStaking,
        uint256 itgAmount,
        uint256 itgPerStaking,
        uint256 totalSupplyForRound
    )
    {
        VaultLib.Round memory round = vaultWeekRoundData[vaultAddress][week];
        premiumAmount = round.premium.amount;
        premiumCommission = round.premium.commissionAmount;
        premiumPerStaking = round.premium.tokenPerStaking;
        bonusAmount = round.bonus.amount;
        bonusCommission = round.bonus.commissionAmount;
        bonusPerStaking = round.bonus.tokenPerStaking;
        itgAmount = round.itg.amount;
        itgPerStaking = round.itg.tokenPerStaking;
        totalSupplyForRound = round.totalSupplyForRound;
        

    }       

    /**
     * calculateRewards 
     * calculate user account rewards
     *
     * @param vaultAddress - address of vault to get rewards
     * @param account - user acocunt
     *
     * @return premium uint256 amount of usdc
     * @return bonus uint256 amount of tidal token
     * @return itg uint256 amount of itg
    
     */
    function calculateRewards(address vaultAddress, address account) external view returns (uint256 premium, uint256 bonus, uint256 itg) {
        return _calulateUserRewards(vaultAddress, account);
    }
    
    /**
     * calculateUserRewards 
     * calculate user account rewards for calling user
     *
     * @param vaultAddress - address of vault to get rewards
     *
     * @return premium uint256 amount of usdc
     * @return bonus uint256 amount of tidal token
     * @return itg uint256 amount of itg
    
     */
    function calculateUserRewards(address vaultAddress) external view returns (uint256 premium, uint256 bonus, uint256 itg) {
        return _calulateUserRewards(vaultAddress, _msgSender());
    }

    /**
        @dev private function for calculating user rewads
    */
    function _calulateUserRewards(address vaultAddress, address account) private view returns (uint256 premium, uint256 bonus, uint256 itg) {
        RoundStaking roundStakingContract = _roundStakingContract();
        uint256 startWeek = 
            vaultAccountRewardData[vaultAddress][account].length == 0 ? 
                roundStakingContract.getAccountStartWeek(vaultAddress, account) : 
                vaultAccountRewardData[vaultAddress][account][vaultAccountRewardData[vaultAddress][account].length-1].lastClaimedWeek;

        if(startWeek == 0 || vaultWeek[vaultAddress] == startWeek) {            
            return (0,0,0);
        } 

        uint256 premiumTokenDecimals =  ERC20Upgradeable(ITidalRegistry(_tidalContract().registry()).baseToken()).decimals();
        uint256 bonusTokenDecimals =  ERC20Upgradeable(ITidalRegistry(_tidalContract().registry()).tidalToken()).decimals();
        while(startWeek < vaultWeek[vaultAddress]) {
            uint256 userStakingForWeek = roundStakingContract.getHoldingsForVaultAccountWeek(vaultAddress, account, startWeek);
            VaultLib.Round memory roundData = vaultWeekRoundData[vaultAddress][startWeek];

            bonus = roundData.bonus.amount > 0 && roundData.totalSupplyForRound > 0 ? bonus + 
                ( (VaultLib.divider(
                    userStakingForWeek,
                    roundData.totalSupplyForRound,
                    bonusTokenDecimals) * roundData.bonus.amount) / 10**bonusTokenDecimals )
                : bonus;

            premium = roundData.premium.amount > 0 && roundData.totalSupplyForRound > 0 ? premium + 
                ( (VaultLib.divider(
                    userStakingForWeek,
                    roundData.totalSupplyForRound,
                    premiumTokenDecimals) * roundData.premium.amount) / 10**premiumTokenDecimals )
                : premium;

            itg = roundData.itg.amount > 0 && roundData.totalSupplyForRound > 0 ? itg  + ( (VaultLib.divider(
                    userStakingForWeek,
                    roundData.totalSupplyForRound,
                    18) * roundData.itg.amount) / 1 ether )
                : itg;
            startWeek++;
        }
    }

    /**
     * claimItgAmount
     * transfer itg from this contract to address
     * can only be called by an active vault
     * 
     * @dev values come from signed message from api account
     * @param itgAmount amount of itg to send
     * @param to address to send itg
     */
    function claimItgAmount(uint256 itgAmount, address to) external {
        ITrustVaultFactory factory = ITrustVaultFactory(_iTrustFactoryAddress);
        require(factory.isActiveVault(_msgSender()));
        ERC20Upgradeable(factory.getContractAddress("GT")).transfer(to, itgAmount);
    }

    /**
     * claimAccountRewards
     * records data on rewards claimed by user
     * can only be called by an active vault
     * 
     * @dev values come from signed message from api account
     * @param vault vault ot claim for
     * @param account user account
     * @param bonusAmount amount of tidal token claimed
     * @param premiumAmount amount of usdc claimed
     * @param itgAmount amount of itg claimed
     */
    function claimAccountRewards(address vault, address account, uint256 bonusAmount, uint256 premiumAmount, uint256 itgAmount ) external {
        vaultAccountRewardData[vault][account].push(
            VaultLib.ClaimedReward({
                premiumAmount: premiumAmount,
                bonusAmount: bonusAmount,
                itgAmount: itgAmount,
                lastClaimedWeek: vaultWeek[vault] })
        );
    }

    /**
     * @dev returns instance of itrust vault factory contract
     */
    function _itrustVaultFactoryContract() internal view returns(ITrustVaultFactory) {
        return ITrustVaultFactory(_iTrustFactoryAddress);
    }

    /**
     * @dev returns instance of round staking contract
     */
    function _roundStakingContract() internal view returns(RoundStaking) {
        return RoundStaking(ITrustVaultFactory(_iTrustFactoryAddress).getContractAddress("RS"));
    }
    
    /**
     * @dev returns instance of tidal contract
     */
    function _tidalContract() internal view returns(ITidalFinance) {
        return ITidalFinance(_itrustVaultFactoryContract().getContractAddress("TIDAL"));
    }

    
    /**
     * @dev in place of modifier to save space, requires message sender is 
     * admin address or trusted signer address
     */
    function _onlyAdminOrTrustedSigner() internal view {
        ITrustVaultFactory vaultFactory = ITrustVaultFactory(_iTrustFactoryAddress);
        require(
            vaultFactory.isAddressAdmin(_msgSender()) || vaultFactory.isAddressTrustedSigner(_msgSender()),
            "NTA"
        );
    }
            
}