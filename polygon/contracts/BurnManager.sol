// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.4;
pragma abicoder v2;

import "@openzeppelin/contracts-upgradeable/utils/ContextUpgradeable.sol";
import "@openzeppelin/contracts-upgradeable/proxy/utils/Initializable.sol";

import "./ITrustVaultFactory.sol";
import "./Vault.sol";

contract BurnManager is Initializable, ContextUpgradeable
{

    // Burn status flags
    uint8 internal constant STATUS_IN_PROGRESS = 1;
    uint8 internal constant STATUS_COMPLETE = 2;

    /**
    * Burn data struct, used to hold the burn data for each vault
    */
    struct BurnData {
        uint256 burnStart;
        uint256 burnEnd;
        uint256 burnWeek; // week we want to burn the tokens for
        uint256 tokensToBurn;
        uint256 totalBurned;
        uint256 currentBurnIndex;
        uint256 perTokenToBurn;
        uint8 status;
        uint256 totalSupply;
        uint8 decimals;
    }

    address internal _iTrustFactoryAddress; // factory address
    mapping (address => BurnData) internal _burnData; // mapping of vault => burn data

    /**
     * @dev Start burn event
     *
     * Emitted when a burn has been started on a vault
     */
    event StartBurn(
        address indexed vault, 
        uint256 indexed burnWeek, 
        uint256 indexed burnStart, 
        uint256 burnAmount, 
        uint256 burnPerToken, 
        uint256 totalSupplyForDay
    );

    /**
     * @dev Stake burned event
     *
     * Emitted when a stake has been burned for an account
     */
    event StakeBurned(
        address indexed vault, 
        uint256 indexed burnStart, 
        address indexed account, 
        uint256 burned
    );

    /**
     * @dev End burn event
     *
     * Emitted when a burn has finished for a vault
     */
    event EndBurn(
        address indexed vault, 
        uint256 indexed burnWeek, 
        uint256 indexed burnStarty, 
        uint256 totalBurned, 
        uint256 endDate
    );

    /**
     * @dev Initialize
     *
     * @param iTrustFactoryAddress itrust vault factory address
     */
    function initialize(
        address iTrustFactoryAddress
    ) 
        initializer 
        external 
    {
        _iTrustFactoryAddress = iTrustFactoryAddress;
    }

    /**
     * @dev Returns a preview of the burn for the given params
     *
     * @param vaultAddress vault address
     * @param week week to start the burn for
     * @param tokensToBurn tokens to burn
     * @return burnRate uint256 the rate of burn for each token
     * @return totalSupplyForWeek uint256 total supply for the week being burned
     */
    function getBurnDataPreview(
        address payable vaultAddress, 
        uint256 week, 
        uint256 tokensToBurn
    ) 
        external 
        view 
        returns(
            uint256 burnRate, 
            uint256 totalSupplyForWeek
        ) 
    {
         _requireAdmin();
        RoundStaking roundStakingContract = _getRoundStaking();
        totalSupplyForWeek = roundStakingContract.getTotalSupplyForAccountWeek(vaultAddress, week);
        burnRate = _divider(tokensToBurn, totalSupplyForWeek, _getVault(vaultAddress).decimals());
        //tokensToBurn.div(totalSupplyForDay);

        if (burnRate < 1) {
            burnRate = 1;
        }

        return(burnRate, totalSupplyForWeek);
    }

    /**
     * @dev Returns the current return data
     *
     * @param vaultAddress vault address
     * @return burnStart uint256 timestamp when the burn was started
     * @return burnEnd uint256 timestamp when the burn has ended, 0 indicates it hasnt ended
     * @return burnWeek uint256 burn week
     * @return tokensToBurn uint256 total tokens to burn
     * @return totalBurned uint256 total tokens burned
     * @return currentBurnIndex uint256 current burn index (current account being burned)
     * @return perTokenToBurn uint256 per token burn rate
     * @return status uint8 status of the burn
     * @return totalSupply uint256 total supply for the burn week
     * @return decimals uint8 decimals for the burn
     */
    function getCurrentBurnData(
        address vaultAddress
    ) 
        external 
        view 
        returns(
            uint256 burnStart, 
            uint256 burnEnd, 
            uint256 burnWeek, 
            uint256 tokensToBurn, 
            uint256 totalBurned, 
            uint256 currentBurnIndex, 
            uint256 perTokenToBurn, 
            uint8 status, 
            uint256 totalSupply, 
            uint8 decimals
        ) 
    {
        _requireAdmin();

        burnStart = _burnData[vaultAddress].burnStart;
        burnEnd = _burnData[vaultAddress].burnEnd;
        burnWeek = _burnData[vaultAddress].burnWeek; // Date we want to burn the tokens for
        tokensToBurn = _burnData[vaultAddress].tokensToBurn;
        totalBurned = _burnData[vaultAddress].totalBurned;
        currentBurnIndex = _burnData[vaultAddress].currentBurnIndex;
        perTokenToBurn = _burnData[vaultAddress].perTokenToBurn;
        status = _burnData[vaultAddress].status;
        totalSupply= _burnData[vaultAddress].totalSupply;
        decimals = _burnData[vaultAddress].decimals;

        return(
            burnStart, 
            burnEnd, 
            burnWeek, 
            tokensToBurn, 
            totalBurned,  
            currentBurnIndex, 
            perTokenToBurn, 
            status, 
            totalSupply, 
            decimals
        );
    }

    /**
     * @dev Starts a burn for supplied vault and week
     *
     * @param vaultAddress vault address
     * @param burnWeek week to start the burn for
     * @param tokensToBurn tokens to burn
     */
    function startBurn(address payable vaultAddress, uint256 burnWeek, uint256 tokensToBurn) external {
        _requireAdmin();
        require(_burnData[vaultAddress].status != STATUS_IN_PROGRESS);

        RoundStaking roundStakingContract = _getRoundStaking();
        uint256 max = roundStakingContract.getNumberOfStakingAddressesForVault(vaultAddress);

        require(max != 0); // require at least one staking

        uint8 decimals = _getVault(vaultAddress).decimals();

        uint256 totalSupplyForWeek = roundStakingContract.getTotalSupplyForAccountWeek(vaultAddress, burnWeek);
        uint256 perTokenBurn = _divider(tokensToBurn, totalSupplyForWeek, decimals);

        if (perTokenBurn < 1) {
            perTokenBurn = 1;
        }

        _burnData[vaultAddress].status = STATUS_IN_PROGRESS;
        _burnData[vaultAddress].tokensToBurn = tokensToBurn;
        _burnData[vaultAddress].burnStart = block.timestamp;
        _burnData[vaultAddress].burnWeek = burnWeek;
        _burnData[vaultAddress].burnEnd = 0;
        _burnData[vaultAddress].currentBurnIndex = 0;
        _burnData[vaultAddress].totalBurned = 0;
        _burnData[vaultAddress].perTokenToBurn =  perTokenBurn;
        _burnData[vaultAddress].totalSupply =  totalSupplyForWeek;
        _burnData[vaultAddress].decimals =  decimals;

        emit StartBurn(
            vaultAddress, 
            burnWeek, 
            _burnData[vaultAddress].burnStart, 
            tokensToBurn, 
            _burnData[vaultAddress].perTokenToBurn, 
            totalSupplyForWeek
        );
    }

    /**
     * @dev Starts processing the accounts to burn tokens, this will be called multiple times until the burn ends
     *
     * @param vaultAddress vault address
     */
    function processBurn(address payable vaultAddress) external {
        _requireAdmin();
        require(_burnData[vaultAddress].status == STATUS_IN_PROGRESS);
        RoundStaking roundStakingContract = _getRoundStaking();
        Vault vaultContract = _getVault(vaultAddress);
        uint256 max = roundStakingContract.getNumberOfStakingAddressesForVault(vaultAddress);
        require(max > 0);

        uint256 counter = 0;
        uint256 totalBurned = _burnData[vaultAddress].totalBurned;
        uint256 currentIndex = _burnData[vaultAddress].currentBurnIndex;

        while(currentIndex <= max - 1 && counter < 100){
            ( uint256 addressHoldings, address indexAddress ) 
                = roundStakingContract.getHoldingsForIndexAndWeekForVault(
                    vaultAddress, 
                    currentIndex, 
                    _burnData[vaultAddress].burnWeek
                );
            
            // User had no stakings for the block
            if(addressHoldings == 0){
                currentIndex ++;
                counter ++;
                continue;
            }
            
            uint256 toBurn = _divider(
                addressHoldings, 
                _burnData[vaultAddress].totalSupply, 
                _burnData[vaultAddress].decimals
            ) * _burnData[vaultAddress].tokensToBurn;

            toBurn = toBurn / (10 ** _burnData[vaultAddress].decimals);

            // Burn at least one wei
            if(toBurn < 1){
                toBurn = 1;
            }

            uint256 currentBalance = vaultContract.balanceOf(indexAddress);

            //if the users balance is less then they have withdrawn and would have not been burned by nexus
            if(currentBalance < toBurn){
                toBurn = currentBalance;
            }

            require(vaultContract.burnTokensForAccount(indexAddress, toBurn));
            totalBurned = totalBurned + toBurn;
            emit StakeBurned(vaultAddress, _burnData[vaultAddress].burnStart, indexAddress, toBurn);
            currentIndex ++;
            counter ++;
        }

        _burnData[vaultAddress].totalBurned = totalBurned;
        _burnData[vaultAddress].currentBurnIndex = currentIndex;

        if(_burnData[vaultAddress].currentBurnIndex == max){
            endBurn(vaultAddress);
        }
    }

    /**
     * @dev Ends a burn for a given vault
     *
     * @param vaultAddress vault address
     */
    function endBurn(address vaultAddress) public {
        _requireAdmin();
        require(_burnData[vaultAddress].status == STATUS_IN_PROGRESS);
        require(_burnData[vaultAddress].tokensToBurn <= _burnData[vaultAddress].totalBurned);

        _burnData[vaultAddress].status = STATUS_COMPLETE;
        _burnData[vaultAddress].burnEnd = block.timestamp;

        emit EndBurn(
            vaultAddress, 
            _burnData[vaultAddress].burnWeek, 
            _burnData[vaultAddress].burnStart, 
            _burnData[vaultAddress].totalBurned, 
            _burnData[vaultAddress].burnEnd
        );
    }

    /**
     * @dev Returns an instance of the round staking contract
     *
     * @return RoundStaking round staking contract instance
     */
    function _getRoundStaking() internal view returns(RoundStaking) {
        return  RoundStaking(_getITrustVaultFactory().getContractAddress("RS"));
    }

    /**
     * @dev Returns an instance of the vault contract
     *
     * @return Vault vault contract instance
     */
    function _getVault(address payable vaultAdddress) internal pure returns(Vault) {
        return  Vault(vaultAdddress);
    }

    /**
     * @dev Returns an instance of the itrust vault factory contract
     *
     * @return ITrustVaultFactory itrust vault factory contract instance
     */
    function _getITrustVaultFactory() internal view returns(ITrustVaultFactory) {
        return ITrustVaultFactory(_iTrustFactoryAddress);
    }

    /**
     * @dev Ensures the msg sender is an admin address
     *
     */
    function _requireAdmin() internal view {
        require(_getITrustVaultFactory().isAddressAdmin(_msgSender()));
    }

    /**
     * @dev Divide function
     *
     * @param numerator numerator
     * @param denominator denominator
     * @param precision precision
     * @return uint256 result
     */
    function _divider(uint256 numerator, uint256 denominator, uint256 precision) internal pure returns(uint) {  
        // This rounds up and not the same as everywhere else      
        return (numerator*(uint(10)**uint(precision+1))/denominator + 9)/uint(10);
    }

}