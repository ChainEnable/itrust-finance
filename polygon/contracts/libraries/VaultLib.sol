// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.4;

library VaultLib {

	struct EpochData {
		uint256 week;
		uint256 amount;
	}

	struct AccountUnstakings {
		uint256 lastClaimedIndex;
		bool hasPreviouslyClaimed;
		EpochData[] unstakingRequests;
	}

    struct TokenRoundData {
        uint amount;
        uint commissionAmount;
        uint tokenPerStaking;                 
    }

	struct Round {
        TokenRoundData premium;	
        TokenRoundData bonus;     
        TokenRoundData itg;   			
		uint totalSupplyForRound;
  	}

    struct ClaimedReward {
        uint premiumAmount;
        uint bonusAmount;
        uint itgAmount;
        uint lastClaimedWeek;
    }
    
    /**
     * @dev Divide function
     *
     * @param numerator numerator
     * @param denominator denominator
     * @param precision precision
     * @return uint256 result
     */
	function divider(uint numerator, uint denominator, uint precision) internal pure returns(uint) {        
		return numerator*(uint(10)**uint(precision))/denominator;
  	}

    /**
     * @dev splits the supplied signature into v,r and s
     *
     * @param sig signature to split
     * @return v
     * @return r
     * @return s
     */
   function splitSignature(bytes memory sig)
        internal
        pure
        returns (uint8, bytes32, bytes32)
    {
        require(sig.length == 65);

        bytes32 r;
        bytes32 s;
        uint8 v;

        assembly {
            // first 32 bytes, after the length prefix
            r := mload(add(sig, 32))
            // second 32 bytes
            s := mload(add(sig, 64))
            // final byte (first byte of the next 32 bytes)
            v := byte(0, mload(add(sig, 96)))
        }

        return (v, r, s);
    }

    /**
     * @dev Returns the signer from the message and signature
     *
     * @param message message 
     * @param sig signature 
     * @return address signer address
     */
    function recoverSigner(bytes32 message, bytes memory sig)
        internal
        pure
        returns (address)
    {
        uint8 v;
        bytes32 r;
        bytes32 s;

        (v, r, s) = splitSignature(sig);

        return ecrecover(message, v, r, s);
    }

    /**
     * @dev Prepends hash for recovery
     *
     * @param hash supplied hash
     * @return bytes32 new hash
     */
    function prefixed(bytes32 hash) internal pure returns (bytes32) {
        return keccak256(abi.encodePacked("\x19Ethereum Signed Message:\n32", hash));
    }

}