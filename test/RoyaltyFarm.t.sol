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
        wavax = new WAVAX();

        farm = new BulletRoyaltyFarm(
            FALLBACK_ADDY, // fallback address
            address(kingshit_lp), // KINGSHIT.x LP
            address(wavax),
            units, // units .001
            cooldown // cooldown 15 minutes
        );

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
        vm.warp(900);
        
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

        // claim for one user
        vm.prank(address(2));
        uint userBalanceBefore = address(2).balance;
        farm.claim();
        uint userBalanceAfter = address(2).balance;
        assertEq(userBalanceAfter, userBalanceBefore + claimable2);

        // ensure nothing is claimable for user now
        uint claimable2_after = farm.claimableForUser(address(2));
        assertEq(claimable2_after, 0);

        // add more rewards via WAVAX and add time to avoid cooldown
        wavax.deposit{value: 1 ether}();
        wavax.transfer(address(farm), 1 ether);
        vm.pauseGasMetering(); // necessary for test otherwise unwrap runs out of gas
        farm.unwrapAVAX();
        vm.resumeGasMetering();
        vm.warp(1800);

        // check that rewards were added
        uint rewardIndex_2 = farm.farmRewardIndex();
        assertEq(rewardIndex_2, .1 ether);

        // check claimable rewards
        uint claimable1_2 = farm.claimableForUser(address(1));
        assertEq(claimable1_2, .1 ether); // prev claimable + 1/20th of rewards

        uint claimable2_2 = farm.claimableForUser(address(2));
        assertEq(claimable2_2, .25 ether); // prev claimable (0) + 5/20th of rewards

        uint claimable3_2 = farm.claimableForUser(address(3));
        assertEq(claimable3_2, .20 ether); // prev claimable + 2/20th of rewards

        uint claimable4_2 = farm.claimableForUser(address(4));
        assertEq(claimable4_2, 1.2 ether); // prev claimable + 12/20th of rewards

        // withdraw and re-check balances
        vm.prank(address(3));
        farm.unstake();

        uint stakedUnits_2 = farm.stakedUnits();
        assertEq(stakedUnits_2, 18);

        uint claimable1_3 = farm.claimableForUser(address(1));
        assertEq(claimable1_3, .1 ether); // same as before

        uint claimable2_3 = farm.claimableForUser(address(2));
        assertEq(claimable2_3, .25 ether); // same as before

        uint claimable3_3 = farm.claimableForUser(address(3));
        assertEq(claimable3_3, 0); // 0 after withdraw

        uint claimable4_3 = farm.claimableForUser(address(4));
        assertEq(claimable4_3, 1.2 ether); // same as before

        // one last addition of rewards
        payable(address(farm)).call{value: 1 ether}("");
        vm.warp(2700);
        
        // check reward index
        uint rewardIndex_3 = farm.farmRewardIndex();
        assertEq(rewardIndex_3, 0.155555555555555555 ether);

        // check claimable rewards
        uint claimable1_4 = farm.claimableForUser(address(1));
        assertEq(claimable1_4, 0.155555555555555555 ether); // previous amount + 1/18th of rewards

        uint claimable2_4 = farm.claimableForUser(address(2));
        assertEq(claimable2_4, 0.527777777777777775 ether); // previous amount + 5/18th of rewards

        uint claimable3_4 = farm.claimableForUser(address(3));
        assertEq(claimable3_4, 0); // no deposit

        uint claimable4_4 = farm.claimableForUser(address(4));
        assertEq(claimable4_4, 1.86666666666666666 ether); // previous amount + 12/20th of rewards
    }

    function test_Reverts() public {
        vm.warp(2000);

        // cannot unwrap AVAX when no units staked
        wavax.deposit{value: 1 ether}();
        wavax.transfer(address(farm), 1 ether);
        vm.expectRevert(BulletRoyaltyFarm.InvalidAmount.selector);
        vm.pauseGasMetering();
        farm.unwrapAVAX();

        // cannot deposit while paused
        farm.togglePaused();
        vm.prank(address(1));
        kingshit_lp.approve(address(farm), .001 ether);
        vm.expectRevert(BulletRoyaltyFarm.Paused.selector);
        vm.prank(address(1));
        farm.stake(1);
        farm.togglePaused();

        // cannot deposit 0
        vm.expectRevert(BulletRoyaltyFarm.InvalidAmount.selector);
        vm.prank(address(1));
        farm.stake(0);

        // cannot unstake 0
        vm.expectRevert(BulletRoyaltyFarm.NothingToWithdraw.selector);
        vm.prank(address(1));
        farm.unstake();

        // unstake fails due to cooldown
        vm.prank(address(1));
        farm.stake(1);
        vm.expectRevert(BulletRoyaltyFarm.CoolingDown.selector);
        vm.prank(address(1));
        farm.unstake();

        // cannot claim 0
        vm.expectRevert(BulletRoyaltyFarm.NothingToClaim.selector);
        vm.prank(address(1));
        farm.claim();

    }

    function test_RewardFallback() public {
        uint balanceBefore = address(FALLBACK_ADDY).balance;
        payable(address(farm)).call{value: 1 ether}("");
        uint balanceAfter = address(FALLBACK_ADDY).balance;
        assertEq(balanceAfter, balanceBefore + 1 ether);
    }
}
