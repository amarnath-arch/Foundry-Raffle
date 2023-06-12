//SPDX-License-Identifier: MIT

pragma solidity ^0.8.18;

import {Test, console} from "forge-std/Test.sol";
import {RaffleDeploy} from "../../script/RaffleDeploy.s.sol";
import {Raffle} from "../../src/Raffle.sol";
import {HelperConfig} from "../../script/HelperConfig.s.sol";
import {Vm} from "forge-std/Vm.sol";
import {VRFCoordinatorV2Mock} from "@chainlink/contracts/src/v0.8/mocks/VRFCoordinatorV2Mock.sol";

contract RaffleTest is Test {
    /**
     * events
     */
    event EnteredRaffle(address indexed player);

    Raffle raffle;
    HelperConfig helperConfig;

    uint256 entranceFee;
    uint256 interval;
    address vrfCoordinator;
    bytes32 gasLane;
    uint64 subscriptionId;
    uint32 callbackGasLimit;
    address link;

    address public player = makeAddr("player");
    uint256 startingBalance = 10 ether;

    function setUp() external {
        RaffleDeploy deployer = new RaffleDeploy();
        (raffle, helperConfig) = deployer.run();

        (
            entranceFee,
            interval,
            vrfCoordinator,
            gasLane,
            subscriptionId,
            callbackGasLimit,
            link,

        ) = helperConfig.activeNetworkConfig();
        vm.deal(player, startingBalance);
    }

    function testRaffleInitializesInOpen() external view {
        // console.log(Raffle.RaffleState.OPEN);
        assert(raffle.getRaffleState() == Raffle.RaffleState.OPEN);
    }

    /**
     * Enter Raffle
     */

    function testRaffleRevertsWhenYouDontPayEnoughETH() external {
        vm.prank(player);
        vm.expectRevert(Raffle.Raffle__NotEnoughETHSent.selector);
        raffle.enterRaffle();
    }

    function testRaffleRecordsPlayerWhenTheyEnter() external {
        vm.prank(player);
        raffle.enterRaffle{value: entranceFee}();
        address playerRecorded = raffle.getPlayer(0);
        assert(playerRecorded == player);
    }

    function testEmitsEventsonEntrance() external {
        vm.prank(player);
        vm.expectEmit(true, false, false, false, address(raffle));
        emit EnteredRaffle(player);
        raffle.enterRaffle{value: entranceFee}();
    }

    function testCanEnterWhenRaffleIsCalculating() external {
        vm.prank(player);
        raffle.enterRaffle{value: entranceFee}();
        vm.warp(block.timestamp + interval + 1);
        vm.roll(block.number + 1);
        raffle.performUpkeep("");

        vm.expectRevert(Raffle.Raffle__RaffleNotOpen.selector);
        vm.prank(player);
        raffle.enterRaffle{value: entranceFee}();
    }

    /**
     * ----------------------------------------------------------------
     *            checkUpKeep
     */

    function testReturnsFalseWhenThereIsNotEnoughBalance() external {
        vm.warp(block.timestamp + interval + 1);
        vm.roll(block.number + 1);
        (bool checkUpKeep, ) = raffle.checkUpkeep("");
        assert(!checkUpKeep);
    }

    function testReturnsFalseWhenRaffleisNotOpen() external {
        vm.prank(player);
        raffle.enterRaffle{value: entranceFee}();
        vm.warp(block.timestamp + 1 + interval);
        vm.roll(block.number + 1);

        raffle.performUpkeep("");
        (bool checkUpkeep, ) = raffle.checkUpkeep("");
        assert(checkUpkeep == false);
    }

    function testReturnsFalseWhenEnoughTimehasntPassed() external {
        vm.prank(player);
        raffle.enterRaffle{value: entranceFee}();
        (bool checkUpKeep, ) = raffle.checkUpkeep("");
        assert(!checkUpKeep);
    }

    function testReturnsTrueWhenParametersareGood() external {
        vm.prank(player);
        raffle.enterRaffle{value: entranceFee}();
        vm.warp(block.timestamp + interval + 1);
        vm.roll(block.number + 1);
        (bool checkUpkeep, ) = raffle.checkUpkeep("");
        assert(checkUpkeep);
    }

    /**
     * ----------------------------------------------------------
     *             PerformUpKeep
     */

    modifier EnterTheRaffleAndPassTime() {
        vm.prank(player);
        raffle.enterRaffle{value: entranceFee}();
        vm.warp(block.timestamp + interval + 1);
        vm.roll(block.number + 1);
        _;
    }

    function testCanOnlyRunIfupkeepNeededisTrue()
        external
        EnterTheRaffleAndPassTime
    {
        raffle.performUpkeep("");
    }

    function testWillRevertIfupkeepNeededisFalse() external {
        uint256 currentBalance = 0;
        uint256 numPlayers = 0;
        uint256 raffleState = 0;
        vm.expectRevert(
            abi.encodeWithSelector(
                Raffle.Raffle_UpkeepNotNeeded.selector,
                currentBalance,
                numPlayers,
                raffleState
            )
        );
        raffle.performUpkeep("");
    }

    function testWillChangetheRaffleStateAndEmitRequestId()
        external
        EnterTheRaffleAndPassTime
    {
        vm.recordLogs();
        raffle.performUpkeep("");
        Vm.Log[] memory entries = vm.getRecordedLogs();
        bytes32 requestId = entries[1].topics[1];
        Raffle.RaffleState raffleState = raffle.getRaffleState();

        assert(uint256(requestId) > 0);
        assert(uint256(raffleState) == 1);
    }

    /**
     *
     * --------------------------------------------
     *              fulfillRandomWords
     */

    modifier skipFork() {
        if (block.chainid != 31337) {
            return;
        }
        _;
    }

    function testCannotCallfulfillRandomWordsbeforeperformUpKeep(
        uint256 randomRequestId
    ) external skipFork {
        vm.expectRevert("nonexistent request");
        VRFCoordinatorV2Mock(vrfCoordinator).fulfillRandomWords(
            randomRequestId,
            address(raffle)
        );
    }

    function testFulfillRandomWordsPicksAWinnerResetsAndSendsMoney()
        external
        EnterTheRaffleAndPassTime
        skipFork
    {
        uint256 additional_entrants = 5;
        uint256 startingIndex = 1;

        for (
            uint256 i = startingIndex;
            i < startingIndex + additional_entrants;
            ++i
        ) {
            address mock_player = address(uint160(i));
            hoax(mock_player, startingBalance);
            raffle.enterRaffle{value: entranceFee}();
        }

        uint256 previousTimestamp = raffle.getLastTimestamp();
        uint256 prize = entranceFee * (additional_entrants + 1);

        vm.recordLogs();
        raffle.performUpkeep("");
        Vm.Log[] memory entries = vm.getRecordedLogs();
        bytes32 requestId = entries[1].topics[1];

        // pretending to be chainlink VRF and get a RandomNumber
        VRFCoordinatorV2Mock(vrfCoordinator).fulfillRandomWords(
            uint256(requestId),
            address(raffle)
        );

        // assert
        assert(uint256(raffle.getRaffleState()) == 0);
        assert(raffle.getRecentWinner() != address(0));
        assert(raffle.getLastTimestamp() > previousTimestamp);
        assert(raffle.getLengthOfPlayers() == 0);
        assert(
            raffle.getRecentWinner().balance ==
                startingBalance + prize - entranceFee
        );
    }
}
