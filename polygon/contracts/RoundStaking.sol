// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.4;
pragma abicoder v2;

import "@openzeppelin/contracts-upgradeable/proxy/utils/Initializable.sol";
import "./BaseContract.sol";
import "./libraries/VaultLib.sol";

contract RoundStaking is BaseContract {

    /**
     * @dev Initialize 
     *
     * @param itrustVaultFactory itrust vault factory address
     */
    function initialize(
        address itrustVaultFactory
    ) 
        initializer 
        external 
    {
        _itrustVaultFactory = itrustVaultFactory;
    }

    /**
     * @dev Returns the starting week for an account, 0 indicates the account has never staked
     *
     * @param vault vualt address
     * @param account account address
     */
    function getAccountStartWeek(address vault, address account) external view returns (uint256 startWeek) {        
        startWeek = _vaultAccountStakings[vault][account].length == 0 
            ? 0 
            : _vaultAccountStakings[vault][account][0].week;
    }

    /**
     * @dev Transfers the amount from one accounts staking to another, this is used to ensure stakes are
     *      transferred when ITV are transferred
     *
     * @param from from address
     * @param to to address
     * @param amount amount to transfer
     * @param category tidal vault category
     */
    function transferStake(address from, address to, uint256 amount, uint8 category) external {

        _requireActiveVault();

        uint256 week = _tidalContract().getCurrentWeek();

        uint256 lastIndex = _vaultAccountStakings[_msgSender()][from].length - 1;

        (uint256 currentUnstakedAmount,) = unstakedAmount(_msgSender(), from, category);
        
        // Available will always be last stake amount - pending (last index could be a future stake) then we need to sub and unstaking requests not claimed
        uint256 availableToTransfer = 
            _vaultAccountStakings[_msgSender()][from][lastIndex].amount  
                - _vaultAccountPendingStakes[_msgSender()][from][week] // pending amount
                - currentUnstakingAmount(_msgSender(), from, category)
                - currentUnstakedAmount;

        require(availableToTransfer >= amount);

        _createFutureStakes(_msgSender(), from);
        _createFutureStakes(_msgSender(), to);

        _removeStakeForAccount(_msgSender(), from, amount, amount, 0, 0);
        _addStakeForAccount(_msgSender(), to, amount, amount, 0, 0);
    }

    /**
     * @dev Creates a stake for an account, this will appear in the pending stakes until
     *      the next epoc
     *
     * @param account account address
     * @param amount value to create
     */
    function createStake(address account, uint256 amount) external {

        _requireActiveVault();

        uint256 week = _tidalContract().getCurrentWeek();

        _createFutureStakes(_msgSender(), account);

        _vaultAccountPendingStakes[_msgSender()][account][week] = _vaultAccountPendingStakes[_msgSender()][account][week] + amount;

        _addStakeForAccount(_msgSender(), account, 0, amount, 0, amount);
    }

    /**
     * @dev Removes a stake for an account
     *
     * @param account account address
     * @param amount value to remove
     */
    function removeStake(address account, uint256 amount) external {

        _requireActiveVault();
        require(_vaultAccountStakings[_msgSender()][account].length > 0);

        _createFutureStakes(_msgSender(), account);

        _removeStakeForAccount(_msgSender(), account, amount, amount, amount, amount);

    }

    /**
     * @dev Removes a pending stake for an account, this takes effect immediately 
     *
     * @param account account address
     * @param amount value to remove
     */
    function removePendingStake(address account, uint256 amount) external {

        _requireActiveVault();
        require(_vaultAccountStakings[_msgSender()][account].length > 0);

        uint256 week = _tidalContract().getCurrentWeek();

        require(_vaultAccountPendingStakes[_msgSender()][account][week] >= amount);

        _createFutureStakes(_msgSender(), account);

        _vaultAccountPendingStakes[_msgSender()][account][week] = _vaultAccountPendingStakes[_msgSender()][account][week] - amount;

        // Check if we have any existing stakes or we have the next week, if not create it 
        _removeStakeForAccount(_msgSender(), account, 0, amount, 0, amount);

    }

    /**
     * @dev Starts the unstaking process 
     *
     * @param account account address
     * @param amount value to unstake
     * @param category tidal category
     */
    function startUnstake(address account, uint256 amount, uint8 category) external {

        _requireActiveVault();
        require(_vaultAccountStakings[_msgSender()][account].length > 0);

        uint256 week = _tidalContract().getCurrentWeek();
        uint256 lastIndex = _vaultAccountStakings[_msgSender()][account].length - 1;

        (uint256 currentUnstakedAmount,) = unstakedAmount(_msgSender(), account, category);
        
        // Available will always be last stake amount - pending (last index could be a future stake) 
        // then we need to sub and unstaking requests not claimed
        uint256 availableToUnstake = 
            _vaultAccountStakings[_msgSender()][account][lastIndex].amount  
                - _vaultAccountPendingStakes[_msgSender()][account][week] // pending amount
                - currentUnstakingAmount(_msgSender(), account, category)
                - currentUnstakedAmount;

        require(availableToUnstake >= amount);

        uint256 unstakingsLength = _vaultAccountUnstakings[_msgSender()][account].length;

        if(unstakingsLength == 0){
            _vaultAccountUnstakings[_msgSender()][account].push(    
                VaultLib.EpochData(
                    { week: 0, amount: 0 }
                )
            );
            unstakingsLength++;
        }

        if(_vaultAccountUnstakings[_msgSender()][account][unstakingsLength - 1].week < week + 2){
            _vaultAccountUnstakings[_msgSender()][account].push(
                VaultLib.EpochData(
                    { week: week + 2, amount: amount }
                )
            );
        } else {
            _vaultAccountUnstakings[_msgSender()][account][unstakingsLength - 1].amount = _vaultAccountUnstakings[_msgSender()][account][unstakingsLength - 1].amount + amount;
        }

    }

    /**
     * @dev Sets the last unstaked index for an account 
     *
     * @param account account address
     * @param index new index value
     */
    function setLastUnstakedIndex(address account, uint256 index) external {
        _requireActiveVault();
        _vaultAccountUnstakingIndex[_msgSender()][account] = index;
    }

    /**
     * @dev Removes an amount from unstake requests, this can be used in the burn
     *      process when not enough tokens are available
     *
     * @param account account address
     * @param amount value to remove 
     * @param category tidal category
     */
    function removeFromUnstakes(address account, uint256 amount, uint8 category) external {

        _requireActiveVault();
        uint256 currentlyUnstaking = currentUnstakingAmount(_msgSender(), account, category);
        require(currentlyUnstaking >= amount);

        uint256 week = _tidalContract().getCurrentWeek();
        uint256 unstakingsLength = _vaultAccountUnstakings[_msgSender()][account].length;
        uint256 limit = unstakingsLength - (_vaultAccountUnstakingIndex[_msgSender()][account] + 1);

        // go from current week and loop through all unstaked, always start at the begining as this can be used to clear down once withdrawn
        for (uint256 offset = 0; offset < limit; offset++) {

            // If we have removed enough or we no longer have future unstakes
            if (amount == 0 || _vaultAccountUnstakings[_msgSender()][account][unstakingsLength - offset].week <= week) break;

            uint256 toUnstake = 
                _vaultAccountUnstakings[_msgSender()][account][unstakingsLength - offset].amount >= amount
                    ? amount
                    : _vaultAccountUnstakings[_msgSender()][account][unstakingsLength - offset].amount;

            _vaultAccountUnstakings[_msgSender()][account][unstakingsLength - offset].amount = _vaultAccountUnstakings[_msgSender()][account][unstakingsLength - offset].amount - toUnstake;
            amount = amount - toUnstake;
        }
        
        require(amount == 0);
    }

    /**
     * @dev Returns a pending stake amount for a given vault and account
     *
     * @param vault vault address
     * @param account account address
     * @return pendingStake uint256 pending stake amount
     */
    function pendingStakeAmount(address vault, address account) public view returns(uint256 pendingStake) {
        uint256 week = _tidalContract().getCurrentWeek();
        pendingStake = _vaultAccountPendingStakes[vault][account][week];
        return pendingStake;
    }

    /**
     * @dev Returns the unstaked amount for a given vault and account
     *
     * @param vault vault address
     * @param account account address
     * @param category tidal category
     * @return amount uint256 unstaked amount
     * @return index uint256 unstaked index
     */
    function unstakedAmount(
        address vault, 
        address account, 
        uint8 category
    ) 
        public 
        view 
        returns(
            uint256 amount, 
            uint256 index
        ) 
    {
        ITidalFinance tidalContract = _tidalContract();
        uint256 week = tidalContract.getCurrentWeek();

        uint256 unstakingsLength = _vaultAccountUnstakings[vault][account].length;
        uint256 lastUnstakeedIndex = _vaultAccountUnstakingIndex[vault][account];

        if(unstakingsLength > 0){
            for(uint256 x = unstakingsLength - 1; x > lastUnstakeedIndex; x--){

                if(_vaultAccountUnstakings[vault][account][x].week > week) continue;

                (,, bool ready) = tidalContract.withdrawRequestMap(vault, _vaultAccountUnstakings[vault][account][x].week, category);

                if(!ready) continue;

                amount = amount + _vaultAccountUnstakings[vault][account][x].amount;

                if(index == 0){
                    index = x;
                }
            }
        }

        return (amount, index);
    }

    /**
     * @dev Returns the staked amount for a given vault and account
     *
     * @param vault vault address
     * @param account account address
     * @param category tidal category
     * @return stakeAmount uint256 staked amount
     */
    function currentStakedAmount(
        address vault, 
        address account, 
        uint8 category
    ) 
        external 
        view 
        returns(
            uint256 stakeAmount
        ) 
    {

        uint256 week = _tidalContract().getCurrentWeek();
        (uint256 currentUnstakedAmount,) = unstakedAmount(vault, account, category);

        stakeAmount = _vaultAccountStakings[vault][account].length == 0 
            ? 0
            : _vaultAccountStakings[vault][account][_vaultAccountStakings[vault][account].length - 1].amount  
                    - _vaultAccountPendingStakes[vault][account][week]
                    - currentUnstakedAmount;

        return (stakeAmount);
    }

    /**
     * @dev Returns the unstaking amount for a given vault and account
     *
     * @param vault vault address
     * @param account account address
     * @param category tidal category
     * @return uint256 unstaking amount
     */
    function currentUnstakingAmount(
        address vault, 
        address account, 
        uint8 category
    ) 
        public 
        view 
        returns(
            uint256
        ) 
    {

        ITidalFinance tidalContract = _tidalContract();
        uint256 week = tidalContract.getCurrentWeek();

        uint256 unstakingsLength = _vaultAccountUnstakings[vault][account].length;
        uint256 amount = 0;

        for(uint256 x = unstakingsLength; x > 0; x--){

            if(_vaultAccountUnstakings[vault][account][x - 1].week < week) { // Nothing less than the current week
                 break;
            } else if (_vaultAccountUnstakings[vault][account][x - 1].week == week) { // If the current week we only want to continue with stakes that are not ready
                (,, bool ready) = tidalContract.withdrawRequestMap(vault, _vaultAccountUnstakings[vault][account][x - 1].week, category);
                if (ready) continue;
            } 
            
            amount = amount + _vaultAccountUnstakings[vault][account][x - 1].amount;
        }

        return amount;

    }

    /**
     * @dev Returns the unstake requests for a given vault and account
     *
     * @param vault vault address
     * @param account account address
     * @return unstakingRequests VaultLib.EpochData[] array of unstaking requests
     */
    function getUnstakeRequests(
        address vault, 
        address account
    ) 
        external 
        view 
        returns(
            VaultLib.EpochData[] memory unstakingRequests
        ) 
    {
        unstakingRequests = _vaultAccountUnstakings[vault][account];
        return (unstakingRequests);
    }

    /**
     * @dev Returns the number of accounts staking in a specific vault
     *
     * @param vault vault address
     * @return uint256 number of staking addresses
     */
    function getNumberOfStakingAddressesForVault(address vault) external view returns(uint256) {
        return _vaultStakerAddresses[vault].length;
    }

    /**
     * @dev Returns the total supply for a given vault and week
     *
     * @param vault vault address
     * @param week week
     * @return uint256 total supply
     */
    function getTotalSupplyForAccountWeek(address vault, uint256 week) external view returns(uint256) {

        uint256 stakingsLength = _vaultStakings[vault].length;

        if(stakingsLength == 0 || _vaultStakings[vault][0].week > week) return 0;

        uint index = stakingsLength - 1;

        while(_vaultStakings[vault][index].week > week){
            index--;
        }

        return _vaultStakings[vault][index].amount;
    }

    /**
     * @dev Returns the holdings and address for an account index and week for a specific vault
     *
     * @param vault vault address
     * @param accountIndex account index (used to lookup account address)
     * @param week week
     * @return uint256 holdings
     * @return address address
     */
    function getHoldingsForIndexAndWeekForVault(
        address vault, 
        uint256 accountIndex, 
        uint256 week
    ) 
        public 
        view 
        returns(
            uint256, 
            address
        ) 
    {

        address account = _vaultStakerAddresses[vault][accountIndex];

        uint256 stakingsLength = _vaultAccountStakings[vault][account].length;

        if(stakingsLength == 0 || _vaultAccountStakings[vault][account][0].week > week) return (0, account);

        uint index = stakingsLength - 1;

        while(_vaultAccountStakings[vault][account][index].week > week){
            index--;
        }

        return (_vaultAccountStakings[vault][account][index].amount, account);
    }

    /**
     * @dev Returns the holdings for an account for a specific vault
     *
     * @param vault vault address
     * @param account account address
     * @param week week
     * @return amount uint256 holdings
     */
    function getHoldingsForVaultAccountWeek(
        address vault, 
        address account, 
        uint256 week
    ) 
        external 
        view 
        returns (
            uint256 amount
        ) 
    {
        for(uint256 x = 0; x < _vaultStakerAddresses[vault].length; x++) {
            if(_vaultStakerAddresses[vault][x] == account) {
                
                (amount,) = getHoldingsForIndexAndWeekForVault(vault, x, week);
            }
                 

        }
    }

    /**
     * @dev Ensures msg sender is an active vault 
     *
     */
    function _requireActiveVault() internal view {
        require(_itrustVaultFactoryContract().isActiveVault(_msgSender()));
    }

    /**
     * @dev Removes a stake from an account, this essentially adjusts the future stake values so as time passes
     *      the account stakes adjust 
     *
     * @param vault vault address
     * @param account account address
     * @param weekAmount amount to remove for week
     * @param futureAmount amount to withdraw for future week
     * @param vaultWeekAmount amount to remove for vault
     * @param vaultFutureAmount amount to withdraw for future
     */
    function _removeStakeForAccount(
        address vault, 
        address account, 
        uint256 weekAmount, 
        uint256 futureAmount, 
        uint256 vaultWeekAmount, 
        uint256 vaultFutureAmount
    ) 
        internal 
    {
        uint256 lastIndex = _vaultAccountStakings[vault][account].length - 1;
        _vaultAccountStakings[vault][account][lastIndex].amount = _vaultAccountStakings[vault][account][lastIndex].amount - futureAmount;
        _vaultAccountStakings[vault][account][lastIndex - 1].amount = _vaultAccountStakings[vault][account][lastIndex - 1].amount - weekAmount;

        lastIndex = _vaultStakings[vault].length - 1;
        _vaultStakings[vault][lastIndex].amount = _vaultStakings[vault][lastIndex].amount - vaultFutureAmount;
        _vaultStakings[vault][lastIndex - 1].amount = _vaultStakings[vault][lastIndex - 1].amount - vaultWeekAmount;
    }

    /**
     * @dev Adds a stake for an account, this essentially adjusts the future stake values so as time passes
     *      the account stakes adjust 
     *
     * @param vault vault address
     * @param account account address
     * @param weekAmount amount to add for 
     * @param futureAmount amount to add for future 
     * @param vaultWeekAmount amount to add for vault
     * @param vaultFutureAmount amount to add for future
     */
    function _addStakeForAccount(
        address vault, 
        address account, 
        uint256 weekAmount, 
        uint256 futureAmount, 
        uint256 vaultWeekAmount, 
        uint256 vaultFutureAmount
    ) 
        internal 
    {
        uint256 lastIndex = _vaultAccountStakings[vault][account].length - 1;
        _vaultAccountStakings[vault][account][lastIndex].amount = _vaultAccountStakings[vault][account][lastIndex].amount + futureAmount;
        _vaultAccountStakings[vault][account][lastIndex - 1].amount = _vaultAccountStakings[vault][account][lastIndex - 1].amount + weekAmount;

        lastIndex = _vaultStakings[vault].length - 1;
        _vaultStakings[vault][lastIndex].amount = _vaultStakings[vault][lastIndex].amount + vaultFutureAmount;
        _vaultStakings[vault][lastIndex - 1].amount = _vaultStakings[vault][lastIndex - 1].amount + vaultWeekAmount;
    }

    /**
     * @dev Ensures the future stakes exists so we can be confident the last two indexes are future epocs 
     *
     * @param vault vault address
     * @param account account address
     */
    function _createFutureStakes(address vault, address account) internal {

        uint256 week = _tidalContract().getCurrentWeek();
        
        uint256 stakingLength = _vaultAccountStakings[vault][account].length;

        if(stakingLength == 0){
            _vaultStakerAddresses[vault].push(account);
        }

        // Check if we have the next week, if not create it 
        if(stakingLength == 0 || _vaultAccountStakings[vault][account][stakingLength - 1].week < week){
            _vaultAccountStakings[vault][account].push(
                VaultLib.EpochData(
                    { 
                        week: week, 
                        amount: stakingLength == 0 ? 0 : _vaultAccountStakings[vault][account][stakingLength - 1].amount 
                    }
                )
            );

            stakingLength++;
        }

        if(_vaultAccountStakings[vault][account][stakingLength - 1].week < week + 1){
            _vaultAccountStakings[vault][account].push(
                VaultLib.EpochData(
                    { 
                        week: week + 1, 
                        amount: stakingLength == 0 ? 0 : _vaultAccountStakings[vault][account][stakingLength - 1].amount 
                    }
                )
            );
        }

        // Same as above just for the vault

        stakingLength = _vaultStakings[vault].length;

        if(stakingLength == 0 || _vaultStakings[vault][stakingLength - 1].week < week){
            _vaultStakings[vault].push(
                VaultLib.EpochData(
                    { 
                        week: week, 
                        amount: stakingLength == 0 ? 0 : _vaultStakings[vault][stakingLength - 1].amount 
                    }
                )
            );

            stakingLength++;
        }

        if(_vaultStakings[vault][stakingLength - 1].week < week + 1){
            _vaultStakings[vault].push(
                VaultLib.EpochData(
                    { 
                        week: week + 1, 
                        amount: stakingLength == 0 ? 0 : _vaultStakings[vault][stakingLength - 1].amount 
                    }
                )
            );
        }
    }

}