// SPDX-License-Identifier: MIT
pragma solidity 0.8.28;

import "forge-std/Script.sol";
import "../src/StakingBBT.sol";

contract DeployStakingBBT is Script {
    function run() external {
        // Get private key from .env file
        uint256 deployerPrivateKey = vm.envUint("PRIVATE_KEY");
        
        // Set the ERC20 token address for staking (replace with your token address)
        address stakingTokenAddress = 0x262c2647bB163af796D9e0902E312bFa01Cb5e4A; // Replace with actual token address
        
        // Start broadcasting transactions
        vm.startBroadcast(deployerPrivateKey);
        
        // Deploy the StakingBBT contract
        StakingBBT stakingContract = new StakingBBT(stakingTokenAddress);
        
        // Stop broadcasting
        vm.stopBroadcast();
        
        // Log the deployed contract address
        console.log("StakingBBT deployed at:", address(stakingContract));
    }
}

// Deployment commands:
// To deploy to BSC testnet:
// forge script script/StakingBBT.s.sol:DeployStakingBBT --rpc-url $TESTNET --broadcast --verify -vvvv
