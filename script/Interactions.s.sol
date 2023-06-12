// SPDX-License-Identifier:MIT
pragma solidity ^0.8.18;

import {Script, console} from "forge-std/Script.sol";
import {HelperConfig} from "./HelperConfig.s.sol";

import {VRFCoordinatorV2Mock} from "@chainlink/contracts/src/v0.8/mocks/VRFCoordinatorV2Mock.sol";
import {LinkToken} from "../test/mocks/LinkToken.sol";

import {DevOpsTools} from "lib/foundry-devops/src/DevOpsTools.sol";

contract CreateSubscription is Script {
    function createSubscriptionusingConfig() public returns (uint64) {
        HelperConfig helperConfig = new HelperConfig();
        (, , address vrfCoordinator, , , , , uint256 deployerKey) = helperConfig
            .activeNetworkConfig();
        return createSubscription(vrfCoordinator, deployerKey);
    }

    function createSubscription(
        address vrfCoordinator,
        uint256 deployerKey
    ) public returns (uint64) {
        console.log("Creating Subscription on chainId:", block.chainid);
        vm.startBroadcast(deployerKey);
        uint64 subId = VRFCoordinatorV2Mock(vrfCoordinator)
            .createSubscription();
        vm.stopBroadcast();
        console.log("Your subId is:", subId);
        return subId;
    }

    function run() external returns (uint64) {
        return createSubscriptionusingConfig();
    }
}

contract FundSubscription is Script {
    uint96 private constant FUND_AMOUNT = 3 ether;

    function fundSubscriptionusingConfig() public {
        HelperConfig helperConfig = new HelperConfig();
        (
            ,
            ,
            address vrfCoordinator,
            ,
            uint64 subId,
            ,
            address link,
            uint256 deployerKey
        ) = helperConfig.activeNetworkConfig();
        fundSubscription(vrfCoordinator, subId, link, deployerKey);
    }

    function fundSubscription(
        address vrfCoordinator,
        uint64 subId,
        address link,
        uint256 deployerKey
    ) public {
        console.log("Funding Subscription on chainId:", block.chainid);
        console.log("With subid:", subId);
        console.log("Using VRFCoordinator:", vrfCoordinator);

        if (block.chainid == 31337) {
            vm.startBroadcast(deployerKey);
            VRFCoordinatorV2Mock(vrfCoordinator).fundSubscription(
                subId,
                FUND_AMOUNT
            );
            vm.stopBroadcast();
        } else {
            vm.startBroadcast(deployerKey);
            LinkToken(link).transferAndCall(
                vrfCoordinator,
                FUND_AMOUNT,
                abi.encode(subId)
            );
            vm.stopBroadcast();
        }
    }

    function run() external {
        fundSubscriptionusingConfig();
    }
}

contract AddConsumer is Script {
    function addConsumer(
        address vrfCoordinator,
        uint64 subId,
        address raffle,
        uint256 deployerKey
    ) public {
        console.log("Adding Consumer contract: ", raffle);
        console.log("Using VRF Coordinator: ", vrfCoordinator);
        console.log("On Chainid:", block.chainid);

        vm.startBroadcast(deployerKey);
        VRFCoordinatorV2Mock(vrfCoordinator).addConsumer(subId, raffle);
        vm.stopBroadcast();
    }

    function AddConsumerusingConfig(address raffle) public {
        HelperConfig helperConfig = new HelperConfig();
        (
            ,
            ,
            address vrfCoordinator,
            ,
            uint64 subId,
            ,
            ,
            uint256 deployerKey
        ) = helperConfig.activeNetworkConfig();

        addConsumer(vrfCoordinator, subId, raffle, deployerKey);
    }

    function run() external {
        address raffle = DevOpsTools.get_most_recent_deployment(
            "Raffle",
            block.chainid
        );

        AddConsumerusingConfig(raffle);
    }
}
