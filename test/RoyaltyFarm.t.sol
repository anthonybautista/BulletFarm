// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.13;

import {Test, console} from "../lib/forge-std/src/Test.sol";
import {BulletRoyaltyFarm} from "../src/BulletRoyaltyFarm.sol";
import {MockERC20} from "../src/MockERC20.sol";
import {WAVAX} from "../src/WAVAX.sol";

contract RoyaltyFarmTest is Test {
    BulletRoyaltyFarm public farm;
    WAVAX public wavax;
    MockERC20 public reward;
    MockERC20 public kingshit_lp;
    address public constant FALLBACK_ADDY = 0xe2a1C02000378B1B064919f688f2697Eb283D6c0;
    uint public units = 10**15; // .001
    uint public cooldown = 900; // 15 minutes

    function setUp() public {
        kingshit_lp = new MockERC20();

        farm = new BulletRoyaltyFarm(
            FALLBACK_ADDY, // fallback address
            address(kingshit_lp), // KINGSHIT.x LP
            units, // units .001
            cooldown // cooldown 15 minutes
        );

        wavax = new WAVAX();

        // transfer mock lp tokens to users
        kingshit_lp.transfer(address(1), .001 ether);
        kingshit_lp.transfer(address(2), .005 ether);
        kingshit_lp.transfer(address(3), .002 ether);
        kingshit_lp.transfer(address(4), .012 ether);
        
    }

    function test_LPTokensReceived() public view {
        uint balance1 = kingshit_lp.balanceOf(address(1));
        assertEq(balance1, .001 ether);

        uint balance2 = kingshit_lp.balanceOf(address(2));
        assertEq(balance2, .005 ether);

        uint balance3 = kingshit_lp.balanceOf(address(3));
        assertEq(balance3, .002 ether);

        uint balance4 = kingshit_lp.balanceOf(address(4));
        assertEq(balance4, .012 ether);
    }

    function test_StakeAndWithdraw() public {
        // set timestamp
        vm.warp(0);

        // approve and deposit
        vm.prank(address(1));
        kingshit_lp.approve(address(farm), .001 ether);
        vm.prank(address(1));
        farm.stake(1);

        BulletRoyaltyFarm.Stake memory stake = farm.getUserStake(address(1));
        assertEq(stake.units, 1);

        uint stakedUnits = farm.stakedUnits();
        assertEq(stakedUnits, 1);

        // fails due to cooldown
        vm.expectRevert(BulletRoyaltyFarm.CoolingDown.selector);
        vm.prank(address(1));
        farm.unstake();

        // move forward in time and unstake
        vm.warp(900);
        vm.prank(address(1));
        farm.unstake();

        BulletRoyaltyFarm.Stake memory stake2 = farm.getUserStake(address(1));
        assertEq(stake2.units, 0);

        uint stakedUnits2 = farm.stakedUnits();
        assertEq(stakedUnits2, 0);
    }

    function test_RewardsAndClaiming() public {
        // set timestamp
        vm.warp(0);
        
        // approve, deposit, and stake for all users
        vm.prank(address(1));
        kingshit_lp.approve(address(farm), .001 ether);
        vm.prank(address(1));
        farm.stake(1);

        vm.prank(address(2));
        kingshit_lp.approve(address(farm), .005 ether);
        vm.prank(address(2));
        farm.stake(5);

        vm.prank(address(3));
        kingshit_lp.approve(address(farm), .002 ether);
        vm.prank(address(3));
        farm.stake(2);

        vm.prank(address(4));
        kingshit_lp.approve(address(farm), .012 ether);
        vm.prank(address(4));
        farm.stake(12);

        // check all balances
        BulletRoyaltyFarm.Stake memory stake1 = farm.getUserStake(address(1));
        assertEq(stake1.units, 1);

        BulletRoyaltyFarm.Stake memory stake2 = farm.getUserStake(address(2));
        assertEq(stake2.units, 5);

        BulletRoyaltyFarm.Stake memory stake3 = farm.getUserStake(address(3));
        assertEq(stake3.units, 2);

        BulletRoyaltyFarm.Stake memory stake4 = farm.getUserStake(address(4));
        assertEq(stake4.units, 12);

        uint stakedUnits = farm.stakedUnits();
        assertEq(stakedUnits, 20);

        // add rewards to contract and pass time
        payable(address(farm)).call{value: 1 ether}("");
        
        // check reward index
        uint rewardIndex = farm.farmRewardIndex();
        assertEq(rewardIndex, .05 ether);

        // check claimable rewards
        uint claimable1 = farm.claimableForUser(address(1));
        assertEq(claimable1, .05 ether); // 1/20th of rewards

        uint claimable2 = farm.claimableForUser(address(2));
        assertEq(claimable2, .25 ether); // 5/20th of rewards

        uint claimable3 = farm.claimableForUser(address(3));
        assertEq(claimable3, .10 ether); // 2/20th of rewards

        uint claimable4 = farm.claimableForUser(address(4));
        assertEq(claimable4, .60 ether); // 12/20th of rewards

    }
}
