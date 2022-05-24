pragma solidity 0.7.6;

interface IPooledStaking {

    struct Staker {
        uint deposit; // total amount of deposit nxm
        uint reward; // total amount that is ready to be claimed
        address[] contracts; // list of contracts the staker has staked on
    
        // staked amounts for each contract
        mapping(address => uint) stakes;
    
        // amount pending to be subtracted after all unstake requests will be processed
        mapping(address => uint) pendingUnstakeRequestsTotal;
    
        // flag to indicate the presence of this staker in the array of stakers of each contract
        mapping(address => bool) isInContractStakers;
    }

    function lastUnstakeRequestId() external view returns(uint256);
    function stakerDeposit(address user) external view returns (uint256);
    function stakerMaxWithdrawable(address user) external view returns (uint256);
    function withdrawReward(address user) external;
    function requestUnstake(address[] calldata protocols, uint256[] calldata amounts, uint256 insertAfter) external;
    function depositAndStake(uint256 deposit, address[] calldata protocols, uint256[] calldata amounts) external;
    function stakerContractStake(address staker, address protocol) external view returns (uint256);
    function stakerContractPendingUnstakeTotal(address staker, address protocol) external view returns(uint256);
    function withdraw(uint256 amount) external;
    function stakerReward(address staker) external view returns (uint256);
    function stakerContractsArray(address staker) external view returns (address[] memory);
    function MIN_STAKE() external view returns(uint);         // Minimum allowed stake per contract
    function MAX_EXPOSURE() external view returns(uint);       // Stakes sum must be less than the deposit amount times this
    function MIN_UNSTAKE() external view returns(uint);       // Forbid unstake of small amounts to prevent spam
    function UNSTAKE_LOCK_TIME() external view returns(uint); 
    function unstakeRequestAtIndex(uint unstakeRequestId) external view returns (
        uint amount, uint unstakeAt, address contractAddress, address stakerAddress, uint next ); 
}