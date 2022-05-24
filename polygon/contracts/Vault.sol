// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.4;

import "@openzeppelin/contracts-upgradeable/token/ERC20/ERC20Upgradeable.sol";
import "@openzeppelin/contracts-upgradeable/token/ERC20/utils/SafeERC20Upgradeable.sol";
import "../interfaces/ITidalFinance.sol";
import "../interfaces/ITidalRegistry.sol";
import "./ITrustVaultFactory.sol";
import "./RoundStaking.sol";
import "./RoundManager.sol";

contract Vault is  
    ERC20Upgradeable 
{
    using SafeERC20Upgradeable for ERC20Upgradeable;

    uint8 internal constant FALSE = 0;
    uint8 internal constant TRUE = 1;

    bool public isStrategy; // Defines if a vault is stratey or index
    
    uint8 internal _locked; // Flag used to protect against reentrant
    uint8 internal _category; // Category the vault is staking in

    uint internal _rewardCommission; // Commission taken out of rewards
    uint8 internal _decimals; // Token precision
    address internal _iTrustFactoryAddress; // Factory address
    address internal _withdrawTokenAddress; // Token address used to return deposited tokens
    address payable internal _treasuryAddress; // Treasury address
    mapping(address => bool) internal _depositTokens; // Tokens that can be deposited into the vault
    mapping(address => mapping(string => bool)) internal _usedNonces; // Used nonces to prevent replay attacks 

    /**
     * @dev Stake event 
     * 
     * Emitted when a stake has occurred
     */
    event Stake(
        address indexed account, 
        address indexed tokenAddress, 
        uint256 indexed week, 
        uint amount, 
        uint balance, 
        uint totalStaked
    );

    /**
     * @dev WithdrawPending event 
     * 
     * Emitted when a pending stake has been withdrawn
     */
    event WithdrawPending(
        address indexed account, 
        address indexed tokenAddress, 
        uint256 indexed week, 
        uint amount, 
        uint balance, 
        uint totalStaked
    );

    /**
     * @dev Unstake event 
     * 
     * Emitted when an unstake request has been made
     */
    event Unstake(
        address indexed  account, 
        uint256 indexed week, 
        uint amount, 
        uint balance, 
        uint totalStaked
    );

    /**
     * @dev TransferITV event 
     * 
     * Emitted when a transfer of ITV tokens as occurred
     */
    event TransferITV(
        address indexed  fromAccount, 
        address indexed toAccount, 
        uint256 indexed week,
        uint amount, 
        uint fromBalance, 
        uint fromTotalStaked,
        uint toBalance, 
        uint toTotalStaked
    );
    
    /**
     * @dev Initialize 
     *
     * @param tokenName token name
     * @param tokenSymbol token symbol
     * @param decimalPlaces decimal places
     * @param commission  treasury commission
     * @param treasuryAddress treasury address
     * @param category tidal staking category
     * @param withdrawTokenAddress withdraw token address
     * @param isStrategy_ is strategy
     * @param depositTokenAddress deposit token address 
     */
    function initialize(
        string memory tokenName,
        string memory tokenSymbol,
        uint8 decimalPlaces,
        uint commission,
        address treasuryAddress,
        uint8 category,
        address withdrawTokenAddress,
        bool isStrategy_,
        address depositTokenAddress
    ) 
        initializer 
        external 
    {
        require(depositTokenAddress != address(0));
        __ERC20_init(tokenName, tokenSymbol); 
        _decimals = decimalPlaces;
        _locked = FALSE;
        _iTrustFactoryAddress = _msgSender();
        _rewardCommission = commission;
        _treasuryAddress = payable(treasuryAddress);
        _category = category;
        _withdrawTokenAddress = withdrawTokenAddress;
        isStrategy = isStrategy_;
        _depositTokens[depositTokenAddress] = true;
    }

    /**
     * @dev required to be allow for receiving ETH claim payouts
     */
    receive() external payable {}

    /**
    * @dev Admin only function to set a new commission rate
    *
    * @param newCommission new commission rate
    */
    function setCommission(uint256 newCommission) external {
        _onlyAdmin();
        _rewardCommission = newCommission;
    }

    /**
    * @dev Admin only function to get the commission rate
    *
    * @return uint256 reward commission
    */
    function getCommission() external view returns(uint256) {
        return _rewardCommission;
    }

    /**
    * @dev Admin only function to set a new treasury address
    *
    * @param newTreasury treasury address
    */
    function setTreasury(address newTreasury) external {
        _onlyAdmin();
        _treasuryAddress = payable(newTreasury);
    }

    /**
    * @dev Returns the precision of the vault token
    *
    * @return uint8 decimal places
    */
    function decimals() public view virtual override returns (uint8) {
        return _decimals;
    }

    /**
    * @dev Admin only function to deposit into tidal and it not effect the stakes
    *
    * @param token deposit token address
    * @param value deposit amount
    */
    function ownerDeposit(address token, uint256 value) external {
        _valueCheck(value);
        _nonReentrant();
        _validDepositToken(token);
        _onlyAdminOrTrustedSigner();
        _lock();
        

        ERC20Upgradeable depositToken = ERC20Upgradeable(token);

        depositToken.approve(ITrustVaultFactory(_iTrustFactoryAddress).getContractAddress("TIDAL"), value);
        depositToken.safeTransferFrom(_msgSender(), address(this), value);

        _tidalContract().deposit(_category, value);
        
        _unlock();
    }

    /**
    * @dev Deposit function to increase the staking amount for an account
    *
    * @param token deposit token address
    * @param value deposit value
    */
    function deposit(address token, uint256 value) external {
        _valueCheck(value);
        _nonReentrant();
        _validDepositToken(token);
        requireActiveVault();
        _lock();
        
        ERC20Upgradeable depositToken = ERC20Upgradeable(token);
        depositToken.approve(ITrustVaultFactory(_iTrustFactoryAddress).getContractAddress("TIDAL"), value);
        depositToken.safeTransferFrom(_msgSender(), address(this), value);

        _tidalContract().deposit(_category, value);
        _roundStakingContract().createStake(_msgSender(), value);

        _mint(
            _msgSender(),
            value
        );

        emit Stake(
            _msgSender(), 
            token, 
            _tidalContract().getCurrentWeek(), 
            value, 
            balanceOf(_msgSender()), 
            _roundStakingContract().currentStakedAmount(address(this), _msgSender(), _category)
        );

        _unlock();
    }

    /**
    * @dev Withdraws an amount of pending tokens to the sender
    *
    * @param value withdraw amount
    */
    function withdrawPending(uint256 value) external {
        _valueCheck(value);
        _nonReentrant();
        requireActiveVault();
        _lock();
        
        RoundStaking roundStakingContract = _roundStakingContract();

        uint256 pendingAmount = roundStakingContract.pendingStakeAmount(address(this), _msgSender());
        
        require(pendingAmount >= value);

        roundStakingContract.removePendingStake(_msgSender(), value);

        _tidalContract().reduceDeposit(_category, value);

        ERC20Upgradeable(_withdrawTokenAddress).transfer(_msgSender(), value);

        _burn(
            _msgSender(),
            value
        );

        emit WithdrawPending(
            _msgSender(), 
            _withdrawTokenAddress, 
            _tidalContract().getCurrentWeek(), 
            value, 
            balanceOf(_msgSender()), 
            _roundStakingContract().currentStakedAmount(address(this), _msgSender(), _category)
        );

        _unlock();
    }

    /** 
    * @dev Starts the unstake process for reducing a staked amount for an account
    *
    * @param value amount to unstake
    */
    function startUnstake(uint256 value) external {
        _valueCheck(value);
        _nonReentrant();
        requireActiveVault();
        _lock();

        _roundStakingContract().startUnstake(_msgSender(), value, _category);

        ITidalFinance tidalFinanceContract = _tidalContract();

        uint256 currentUnstakeWeek = tidalFinanceContract.getUnlockWeek();
        (uint256 currentUnstakingAmount,,) = tidalFinanceContract.withdrawRequestMap(address(this), currentUnstakeWeek, _category);

        tidalFinanceContract.withdraw(_category, value + currentUnstakingAmount);

        emit Unstake(
            _msgSender(), 
            tidalFinanceContract.getCurrentWeek(), 
            value,
            balanceOf(_msgSender()), 
            _roundStakingContract().currentStakedAmount(address(this), _msgSender(), _category)
        );

        _unlock();
    }

    /**
    * @dev Withdraws all unstaked tokens to the sender
    *
    */
    function withdrawUnstaked() external {
        _nonReentrant();
        requireActiveVault();
        _lock();
        
        RoundStaking roundStakingContract = _roundStakingContract();

        (uint256 amount, uint256 index) = roundStakingContract.unstakedAmount(
            address(this), 
            _msgSender(), 
            _category
        );

        require(amount > 0);

        roundStakingContract.removeStake(_msgSender(), amount);
        roundStakingContract.setLastUnstakedIndex(_msgSender(), index);

        _burn(
            _msgSender(),
            amount
        );

        ERC20Upgradeable(_withdrawTokenAddress).transfer(_msgSender(), amount);

        _unlock();
    }


    /**
    * @dev Admin or trusted signer only function that is used to update the basket
    *      items for the current vault
    *
    * @param basketIndexes array of basket indexes to pass onto tidal
    */
    function changeBasket(uint16[] calldata basketIndexes) external {
        _onlyAdminOrTrustedSigner();
        _tidalContract().changeBasket(_category, basketIndexes);
    }

    /**
    * @dev Called by the round manager to claim the reward tokens from the tidal contract
    *
    * @param premiumAmount premium reward amount
    * @param bonusAmount bonus reward amount
    */
    function endRoundClaim(uint256 premiumAmount, uint256 bonusAmount) 
        external 
        returns (
            uint premiumCommission, 
            uint bonusCommission
        ) 
    {
        require(_msgSender() == ITrustVaultFactory(_iTrustFactoryAddress).getContractAddress("RM"));
        _tidalContract().claimPremium();
        _tidalContract().claimBonus();

        bonusCommission =  (bonusAmount * _rewardCommission) / 10000;
        premiumCommission =  (premiumAmount * _rewardCommission) / 10000;
        
        ITidalRegistry registry = ITidalRegistry(_tidalContract().registry());

        ERC20Upgradeable(registry.baseToken()).transfer(_treasuryAddress, premiumCommission);
        ERC20Upgradeable(registry.tidalToken()).transfer(_treasuryAddress, bonusCommission);
        
    }

    /**
    * @dev Called by the burn manager contract to burn tokens for a specific account
    *
    * @param account account address
    * @param tokensToBurn number of tokens to burn
    */
    function burnTokensForAccount(address account, uint tokensToBurn) external returns(bool) {
        _nonReentrant();
        require(
            ITrustVaultFactory(_iTrustFactoryAddress).isContractAddress(_msgSender(), "BM")
        );
        _valueCheck(tokensToBurn);
        _lock();

        RoundStaking roundStakingContract = _roundStakingContract();

        uint256 balance = balanceOf(account);
        uint256 totalUnstaking = roundStakingContract.currentUnstakingAmount(address(this), account, _category);
        uint256 balanceAfterBurn = balance - tokensToBurn;
        roundStakingContract.removeStake(account, tokensToBurn);

        // Check if there is enough after unstaking, if not we need to remove from the unstaking requests
        if(balanceAfterBurn < totalUnstaking){
            roundStakingContract.removeFromUnstakes(account, balanceAfterBurn - totalUnstaking, _category);
        }

         _burn(account, tokensToBurn);
        
        _unlock();
        return true;
    }

    /**
     * @dev Called by the burn manager contract to burn tokens for a specific account
     *
     * @param bonusAmount bonus token amount to withdraw
     * @param premiumAmount premium token amount to withdraw
     * @param itgAmount itg token amount to withdraw
     * @param nonce unique nonce
     * @param sig data signature
     */
    function withdrawRewards(
        uint bonusAmount, 
        uint premiumAmount, 
        uint itgAmount, 
        string memory nonce, 
        bytes memory sig
    ) 
        external 
        returns (bool) 
    {
        require(!_usedNonces[_msgSender()][nonce]);
        _nonReentrant();
        _lock();
       
        bytes32 abiBytes = keccak256(
            abi.encodePacked(
                _msgSender(),
                premiumAmount, 
                bonusAmount, 
                itgAmount, 
                nonce, 
                address(this)
            )
        );

        bytes32 message = VaultLib.prefixed(abiBytes);

        address signer = VaultLib.recoverSigner(message, sig);

        ITrustVaultFactory(_iTrustFactoryAddress).requireTrustedSigner(signer);

       
        // require(_getStakingDataContract().withdrawRewards(_msgSender(), tokens, rewards));
        _usedNonces[_msgSender()][nonce] = true;

        RoundManager roundManager = RoundManager(
            ITrustVaultFactory(_iTrustFactoryAddress).getContractAddress("RM")
        );

        roundManager.claimAccountRewards(address(this), _msgSender(), bonusAmount, premiumAmount, itgAmount);

        ITidalRegistry registry = ITidalRegistry(_tidalContract().registry());
        if(premiumAmount > 0)
            ERC20Upgradeable(registry.baseToken()).transfer(_msgSender(), premiumAmount);
        if(bonusAmount > 0)
            ERC20Upgradeable(registry.tidalToken()).transfer(_msgSender(), bonusAmount);
        if(itgAmount > 0)
            roundManager.claimItgAmount(itgAmount, _msgSender());
     
        _unlock();
        return true;
    }
    

    

    /**
     * Private functions
     */

     /**
     * @dev Moves tokens `amount` from `sender` to `recipient`.
     *
     * This is internal function is equivalent to {transfer}, and can be used to
     * e.g. implement automatic token fees, slashing mechanisms, etc.
     *
     * Emits a {Transfer} event.
     *
     * Requirements:
     *
     * - `sender` cannot be the zero address.
     * - `recipient` cannot be the zero address.
     * - `sender` must have a balance of at least `amount`.
     */
    function _transfer(address sender, address recipient, uint256 amount) internal override {

        RoundStaking roundStakingContract = _roundStakingContract();

        roundStakingContract.transferStake(sender, recipient, amount, _category);
        
        super._transfer(sender, recipient, amount);

        emit TransferITV(
            sender,
            recipient,
            _tidalContract().getCurrentWeek(),
            amount,            
            balanceOf(sender),
            roundStakingContract.currentStakedAmount(address(this), sender, _category),
            balanceOf(recipient),
            roundStakingContract.currentStakedAmount(address(this), recipient, _category)
        );           

    }


    /**
     * @dev Checks the supplied value is not equal to 0
     *
     * @param value value to check against
     */
    function _valueCheck(uint value) internal pure {
        require(value != 0);
    }

    /**
     * @dev Locks the contract for the reentrant protection
     *
     */
    function _lock() internal {
        _locked = TRUE;
    }

    /**
     * @dev Unlocks the contract for the reentrant protection
     *
     */
    function _unlock() internal {
        _locked = FALSE;
    }

    /**
     * @dev Ensures the supplied token is a valid token
     *
     * @param token deposit token address to check
     */
    function _validDepositToken(address token) internal view {
        require(_depositTokens[token]);
    }

    /**
     * @dev Ensures message sender is a trusted admin account
     *
     */
    function _onlyAdmin() internal view {
        require(
            ITrustVaultFactory(_iTrustFactoryAddress).isAddressAdmin(_msgSender())
        );
    }

    /**
     * @dev Ensures message sender is a trusted signer or admin account
     *
     */
    function _onlyAdminOrTrustedSigner() internal view {
        ITrustVaultFactory vaultFactory = ITrustVaultFactory(_iTrustFactoryAddress);
        require(
            vaultFactory.isAddressAdmin(_msgSender()) || vaultFactory.isAddressTrustedSigner(_msgSender())
        );
    }

    /**
     * @dev Ensures the locked flag is false to protect against reentrant
     *
     */
    function _nonReentrant() internal view {
        require(_locked == FALSE);
    }  

    /**
     * @dev Returns an instance of the tidal contract
     *
     * @return ITidalFinance tidal finance contract
     */
    function _tidalContract() internal view returns(ITidalFinance) {
        return ITidalFinance(ITrustVaultFactory(_iTrustFactoryAddress).getContractAddress("TIDAL"));
    }

    /**
     * @dev Returns an instance of the round staking contract
     *
     * @return RoundStaking round staking contract
     */
    function _roundStakingContract() internal view returns(RoundStaking) {
        return RoundStaking(ITrustVaultFactory(_iTrustFactoryAddress).getContractAddress("RS"));
    }

    /**
     * @dev Checks the current vault is active
     *
     * @return bool status of the vault
     */
    function isVaultActive() public view returns (bool) {
        return ITrustVaultFactory(_iTrustFactoryAddress).isActiveVault(address(this)) && !_tidalContract().isCategoryLocked(address(this), _category);
    }

    /**
     * @dev Ensures the current vault is active
     *
     */
    function requireActiveVault() internal view {
        require(isVaultActive());
    }
}