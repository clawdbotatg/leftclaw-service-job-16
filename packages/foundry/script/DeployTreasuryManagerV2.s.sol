// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "./DeployHelpers.s.sol";
import "../contracts/TreasuryManagerV2.sol";

contract DeployTreasuryManagerV2 is ScaffoldETHDeploy {
    // Client/Owner address
    address constant CLIENT = 0x9ba58Eea1Ea9ABDEA25BA83603D54F6D9A01E506;
    
    // Base WETH
    address constant WETH = 0x4200000000000000000000000000000000000006;

    function run() external ScaffoldEthDeployerRunner {
        // Deployer becomes operator by default, owner is client
        TreasuryManagerV2 treasury = new TreasuryManagerV2(
            CLIENT,      // owner = client
            msg.sender,  // operator = deployer (can be changed by owner)
            WETH         // WETH on Base
        );

        console.logString(
            string.concat(
                "TreasuryManagerV2 deployed at: ",
                vm.toString(address(treasury))
            )
        );
        console.logString(
            string.concat(
                "Owner: ",
                vm.toString(CLIENT)
            )
        );
    }
}
