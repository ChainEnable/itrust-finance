pragma solidity 0.7.6;
pragma abicoder v2;

import "@openzeppelin/contracts-upgradeable/GSN/ContextUpgradeable.sol";
import "@openzeppelin/contracts-upgradeable/proxy/Initializable.sol";import "@openzeppelin/contracts-upgradeable/math/SafeMathUpgradeable.sol";

import "./../iTrustVaultFactory.sol";
import "./Vault.sol";

contract Burn is Initializable, ContextUpgradeable
{
    using SafeMathUpgradeable for uint;


    uint8 internal constant STATUS_IN_PROGRESS = 1;
    uint8 internal constant STATUS_COMPLETE = 2;

    struct BurnData {
        uint burnStart;
        uint burnEnd;
        uint burnBlock; // Date we want to burn the tokens for
        uint tokensToBurn;
        uint totalBurned;
        uint currentBurnIndex;
        uint perTokenToBurn;
        uint8 status;
        uint totalSupply;
    }

    address internal _iTrustFactoryAddress;
    mapping (address => BurnData) internal _burnData;

    event StartBurn(address indexed vault, uint256 indexed burnBlock, uint256 indexed burnStart, uint256 burnAmount, uint256 burnPerToken, uint totalSupplyForDay);
    event StakeBurned(address indexed vault, uint256 indexed burnStart, address indexed account, uint256 burned);
    event EndBurn(address indexed vault, uint256 indexed burnBlock, uint256 indexed burnStarty, uint256 totalBurned, uint256 endDate);

    function initialize(
        address iTrustFactoryAddress
    ) 
        initializer 
        external 
    {
        _iTrustFactoryAddress = iTrustFactoryAddress;
    }

    /**
     * Public functions
     */

     function getBurnDataPreview(address vaultAddress, uint burnBlock, uint tokensToBurn) external view returns(uint burnRate, uint totalSupplyForBlock) {
         _isAdmin();
        StakingData stakingDataContract = _getStakingData();
        totalSupplyForBlock = stakingDataContract.getTotalSupplyForAccountBlock(vaultAddress, burnBlock);
        burnRate = _divider(tokensToBurn, totalSupplyForBlock, 18);
        //tokensToBurn.div(totalSupplyForDay);

        if (burnRate < 1) {
            burnRate = 1;
        }

        return(burnRate, totalSupplyForBlock);
    }

    function getCurrentBurnData(address vaultAddress) external view returns(uint burnStart, uint burnEnd, uint burnBlock, uint tokensToBurn, uint totalBurned, uint currentBurnIndex, uint perTokenToBurn, uint8 status, uint totalSupply) {
        _isAdmin();
        burnStart = _burnData[vaultAddress].burnStart;
        burnEnd = _burnData[vaultAddress].burnEnd;
        burnBlock = _burnData[vaultAddress].burnBlock; // Date we want to burn the tokens for
        tokensToBurn = _burnData[vaultAddress].tokensToBurn;
        totalBurned = _burnData[vaultAddress].totalBurned;
        currentBurnIndex = _burnData[vaultAddress].currentBurnIndex;
        perTokenToBurn = _burnData[vaultAddress].perTokenToBurn;
        status = _burnData[vaultAddress].status;
        totalSupply= _burnData[vaultAddress].totalSupply;
        return(burnStart, burnEnd, burnBlock, tokensToBurn, totalBurned,  currentBurnIndex, perTokenToBurn, status, totalSupply);
    }

    function startBurn(address vaultAddress, uint burnBlock, uint tokensToBurn) external {
        _isAdmin();
        require(_burnData[vaultAddress].status != STATUS_IN_PROGRESS);

        StakingData stakingDataContract = _getStakingData();
        uint max = stakingDataContract.getNumberOfStakingAddressesForVault(vaultAddress);

        require(max != 0); // require at least one staking

        uint totalSupplyForBlock = stakingDataContract.getTotalSupplyForAccountBlock(vaultAddress, burnBlock);
        uint256 perTokenBurn = _divider(tokensToBurn, totalSupplyForBlock, 18);

        if (perTokenBurn < 1) {
            perTokenBurn = 1;
        }

        _burnData[vaultAddress].status = STATUS_IN_PROGRESS;
        _burnData[vaultAddress].tokensToBurn = tokensToBurn;
        _burnData[vaultAddress].burnStart = block.timestamp;
        _burnData[vaultAddress].burnBlock = burnBlock;
        _burnData[vaultAddress].burnEnd = 0;
        _burnData[vaultAddress].currentBurnIndex = 0;
        _burnData[vaultAddress].totalBurned = 0;
        _burnData[vaultAddress].perTokenToBurn =  perTokenBurn;
        _burnData[vaultAddress].totalSupply =  totalSupplyForBlock;
        emit StartBurn(vaultAddress, burnBlock, _burnData[vaultAddress].burnStart, tokensToBurn, _burnData[vaultAddress].perTokenToBurn, totalSupplyForBlock);
    }

    function processBurn(address payable vaultAddress) external {
        _isAdmin();
        require(_burnData[vaultAddress].status == STATUS_IN_PROGRESS);
        StakingData stakingDataContract = _getStakingData();
        Vault vaultContract = _getVault(vaultAddress);
        uint max = stakingDataContract.getNumberOfStakingAddressesForVault(vaultAddress);
        require(max > 0);

        uint counter = 0;
        uint totalBurned = _burnData[vaultAddress].totalBurned;
        uint currentIndex = _burnData[vaultAddress].currentBurnIndex;

        while(currentIndex <= max - 1 && counter < 100){
            ( address indexAddress, uint addressHoldings ) = stakingDataContract.getHoldingsForIndexAndBlockForVault(vaultAddress, currentIndex, _burnData[vaultAddress].burnBlock);
            
            // User had no stakings for the block
            if(addressHoldings == 0){
                currentIndex ++;
                counter ++;
                continue;
            }
            
            uint256 toBurn = _divider(addressHoldings, _burnData[vaultAddress].totalSupply, 18)
                                .mul(_burnData[vaultAddress].tokensToBurn);
            toBurn = toBurn.div(1e18);

            // Burn at least one wei
            if(toBurn < 1){
                toBurn = 1;
            }

            uint currentBalance = vaultContract.balanceOf(indexAddress);

            //if the users balance is less then they have withdrawn and would have not been burned by nexus
            if(currentBalance < toBurn){
                toBurn = currentBalance;
            }

            require(vaultContract.burnTokensForAccount(indexAddress, toBurn));
            totalBurned = totalBurned.add(toBurn);
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

    function endBurn(address vaultAddress) public {
        _isAdmin();
        require(_burnData[vaultAddress].status == STATUS_IN_PROGRESS);
        require(_burnData[vaultAddress].tokensToBurn <= _burnData[vaultAddress].totalBurned);
        _burnData[vaultAddress].status = STATUS_COMPLETE;
        _burnData[vaultAddress].burnEnd = block.timestamp;
        emit EndBurn(vaultAddress, _burnData[vaultAddress].burnBlock, _burnData[vaultAddress].burnStart, _burnData[vaultAddress].totalBurned, _burnData[vaultAddress].burnEnd);
    }

    /**
     * Internal functions
     */

    function _getStakingData() internal view returns(StakingData) {
        return  StakingData(_getITrustVaultFactory().getStakingDataAddress());
    }

    function _getVault(address payable vaultAdddress) internal pure returns(Vault) {
        return  Vault(vaultAdddress);
    }

    function _getITrustVaultFactory() internal view returns(ITrustVaultFactory) {
        return ITrustVaultFactory(_iTrustFactoryAddress);
    }

    /**
     * Validate functions
     */

    function _isAdmin() internal view returns (bool) {
        require(_getITrustVaultFactory().isAddressAdmin(_msgSender()));
    }

    function _divider(uint numerator, uint denominator, uint precision) internal pure returns(uint) {  
        // This rounds up and not the same as everywhere else      
        return (numerator*(uint(10)**uint(precision+1))/denominator + 9)/uint(10);
    }

}