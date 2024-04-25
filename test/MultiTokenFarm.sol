// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.13;

import {Test, console} from "../lib/forge-std/src/Test.sol";
import {BulletMultiTokenFarm} from "../src/BulletMultiTokenFarm.sol";
import {MockERC20} from "../src/utils/MockERC20.sol";
import {WAVAX} from "../src/utils/WAVAX.sol";

contract MultiTokenFarmTest is Test {
    BulletMultiTokenFarm public farm;
    WAVAX public wavax;
    MockERC20 public lucky;
    MockERC20 public majin;
    MockERC20 public kingshit_lp;
    address public constant FALLBACK_ADDY = 0xe2a1C02000378B1B064919f688f2697Eb283D6c0;
    uint public units = 10**15; // .001
    uint public cooldown = 900; // 15 minutes

    function setUp() public {
        lucky = new MockERC20();
        majin = new MockERC20();
        kingshit_lp = new MockERC20();
        wavax = new WAVAX();

        farm = new BulletMultiTokenFarm(
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

        BulletMultiTokenFarm.Stake memory stake = farm.getUserStake(address(1));
        assertEq(stake.units, 1);

        uint stakedUnits = farm.stakedUnits();
        assertEq(stakedUnits, 1);

        // move forward in time and unstake
        vm.warp(900);
        vm.prank(address(1));
        farm.unstake();

        BulletMultiTokenFarm.Stake memory stake2 = farm.getUserStake(address(1));
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
        BulletMultiTokenFarm.Stake memory stake1 = farm.getUserStake(address(1));
        assertEq(stake1.units, 1);

        BulletMultiTokenFarm.Stake memory stake2 = farm.getUserStake(address(2));
        assertEq(stake2.units, 5);

        BulletMultiTokenFarm.Stake memory stake3 = farm.getUserStake(address(3));
        assertEq(stake3.units, 2);

        BulletMultiTokenFarm.Stake memory stake4 = farm.getUserStake(address(4));
        assertEq(stake4.units, 12);

        uint stakedUnits = farm.stakedUnits();
        assertEq(stakedUnits, 20);

        // add rewards to contract. this will be wrapped into WAVAX
        payable(address(farm)).call{value: 1 ether}("");

        // users have nothing claimable before time passes
        assertEq(farm.userCanClaim(address(1)), false);
        assertEq(farm.userCanClaim(address(2)), false);
        assertEq(farm.userCanClaim(address(3)), false);
        assertEq(farm.userCanClaim(address(4)), false);
        
        vm.warp(900);
        
        // check reward index for WAVAX 
        uint rewardIndex = farm.tokenIndexForUser(address(farm), address(wavax));
        assertEq(rewardIndex, .05 ether);

        // check claimable rewards
        assertEq(farm.userCanClaim(address(1)), true);
        BulletMultiTokenFarm.TokensClaimable[] memory claimable1 = farm.claimableForUser(address(1));
        assertEq(claimable1[0].amount, .05 ether); // 1/20th of rewards

        assertEq(farm.userCanClaim(address(2)), true);
        BulletMultiTokenFarm.TokensClaimable[] memory claimable2 = farm.claimableForUser(address(2));
        assertEq(claimable2[0].amount, .25 ether); // 5/20th of rewards

        assertEq(farm.userCanClaim(address(3)), true);
        BulletMultiTokenFarm.TokensClaimable[] memory claimable3 = farm.claimableForUser(address(3));
        assertEq(claimable3[0].amount, .10 ether); // 2/20th of rewards

        assertEq(farm.userCanClaim(address(4)), true);
        BulletMultiTokenFarm.TokensClaimable[] memory claimable4 = farm.claimableForUser(address(4));
        assertEq(claimable4[0].amount, .60 ether); // 12/20th of rewards

        // claim for one user
        uint userBalanceBefore = wavax.balanceOf(address(2));
        vm.prank(address(2));
        farm.claim();
        uint userBalanceAfter = wavax.balanceOf(address(2));
        assertEq(userBalanceAfter, userBalanceBefore + claimable2[0].amount);

        // ensure nothing is claimable for user now
        BulletMultiTokenFarm.TokensClaimable[] memory claimable2_after = farm.claimableForUser(address(2));
        assertEq(claimable2_after[0].amount, 0);

        // check that lucky is not a valid token
        assertEq(farm.tokenIsValid(address(lucky)), false);

        // add more rewards using LUCKY and add time to avoid cooldown
        lucky.approve(address(farm), 10 ether);
        farm.addReward(address(lucky), 10 ether);
        vm.warp(1800);

        // check that lucky is now a valid token
        assertEq(farm.tokenIsValid(address(lucky)), true);

        // check that rewards were added
        uint rewardIndex_wavax = farm.tokenIndexForUser(address(farm), address(wavax));
        assertEq(rewardIndex_wavax, .05 ether);

        uint rewardIndex_lucky = farm.tokenIndexForUser(address(farm), address(lucky));
        assertEq(rewardIndex_lucky, .5 ether);

        // check claimable rewards
        assertEq(farm.userCanClaim(address(1)), true);
        claimable1 = farm.claimableForUser(address(1));
        assertEq(claimable1[0].amount, .05 ether); // wavax is the same
        assertEq(claimable1[1].amount, .5 ether); // 1/20th of 10 lucky

        assertEq(farm.userCanClaim(address(2)), true);
        claimable2 = farm.claimableForUser(address(2));
        assertEq(claimable2[0].amount, 0); // 0 wavax because already claimed
        assertEq(claimable2[1].amount, 2.5 ether); // 5/20th of 10 lucky

        assertEq(farm.userCanClaim(address(3)), true);
        claimable3 = farm.claimableForUser(address(3));
        assertEq(claimable3[0].amount, .10 ether); // wavax is the same
        assertEq(claimable3[1].amount, 1 ether); // 2/20th of 10 lucky

        assertEq(farm.userCanClaim(address(4)), true);
        claimable4 = farm.claimableForUser(address(4));
        assertEq(claimable4[0].amount, .60 ether); // wavax is the same
        assertEq(claimable4[1].amount, 6 ether); // 12/20th of 10 lucky

        // withdraw and re-check balances
        vm.prank(address(3));
        farm.unstake();

        // check user token balances
        assertEq(wavax.balanceOf(address(3)), .1 ether);
        assertEq(lucky.balanceOf(address(3)), 1 ether);

        stakedUnits = farm.stakedUnits();
        assertEq(stakedUnits, 18);

        assertEq(farm.userCanClaim(address(1)), true);
        claimable1 = farm.claimableForUser(address(1));
        assertEq(claimable1[0].amount, .05 ether); // same as before
        assertEq(claimable1[1].amount, .5 ether); // same as before

        assertEq(farm.userCanClaim(address(2)), true);
        claimable2 = farm.claimableForUser(address(2));
        assertEq(claimable2[0].amount, 0); // same as before
        assertEq(claimable2[1].amount, 2.5 ether); // same as before

        assertEq(farm.userCanClaim(address(3)), false);
        claimable3 = farm.claimableForUser(address(3));
        assertEq(claimable3[0].amount, 0); // 0 because withdrawn
        assertEq(claimable3[1].amount, 0); // 0 because withdrawn

        assertEq(farm.userCanClaim(address(4)), true);
        claimable4 = farm.claimableForUser(address(4));
        assertEq(claimable4[0].amount, .60 ether); // same as before
        assertEq(claimable4[1].amount, 6 ether); // same as before

        // check that majin is not a valid token
        assertEq(farm.tokenIsValid(address(majin)), false);

        // add more rewards using MAJIN and add time
        majin.approve(address(farm), 1000 ether);
        farm.addReward(address(majin), 1000 ether);
        vm.warp(2700);

        // check that majin is now a valid token
        assertEq(farm.tokenIsValid(address(majin)), true);

        // check that rewards were added
        rewardIndex_wavax = farm.tokenIndexForUser(address(farm), address(wavax));
        assertEq(rewardIndex_wavax, .05 ether);

        rewardIndex_lucky = farm.tokenIndexForUser(address(farm), address(lucky));
        assertEq(rewardIndex_lucky, .5 ether);

        uint rewardIndex_majin = farm.tokenIndexForUser(address(farm), address(majin));
        assertEq(rewardIndex_majin, 55.555555555555555555 ether); // 1000 / 18

        // add more majin via public add
        majin.transfer(address(1), 800 ether);
        vm.startPrank(address(1));
        majin.approve(address(farm), 800 ether);
        farm.addRewardPublic(address(majin), 800 ether);
        vm.stopPrank();

        // check rewards again
        rewardIndex_wavax = farm.tokenIndexForUser(address(farm), address(wavax));
        assertEq(rewardIndex_wavax, .05 ether);

        rewardIndex_lucky = farm.tokenIndexForUser(address(farm), address(lucky));
        assertEq(rewardIndex_lucky, .5 ether);

        rewardIndex_majin = farm.tokenIndexForUser(address(farm), address(majin));
        assertEq(rewardIndex_majin, 100 ether - 1); // -1 because of rounding issue?

        // check claimable rewards
        assertEq(farm.userCanClaim(address(1)), true);
        claimable1 = farm.claimableForUser(address(1));
        assertEq(claimable1[0].amount, .05 ether); // same as before
        assertEq(claimable1[1].amount, .5 ether); // same as before
        assertEq(claimable1[2].amount, 100 ether - 1); // majin index * 1

        assertEq(farm.userCanClaim(address(2)), true);
        claimable2 = farm.claimableForUser(address(2));
        assertEq(claimable2[0].amount, 0); // same as before
        assertEq(claimable2[1].amount, 2.5 ether); // same as before
        assertEq(claimable2[2].amount, (100 ether - 1) * 5); // majin index * 5

        assertEq(farm.userCanClaim(address(3)), false);
        claimable3 = farm.claimableForUser(address(3));
        assertEq(claimable3[0].amount, 0); // same as before
        assertEq(claimable3[1].amount, 0); // same as before
        assertEq(claimable3[2].amount, 0); // not staked

        assertEq(farm.userCanClaim(address(4)), true);
        claimable4 = farm.claimableForUser(address(4));
        assertEq(claimable4[0].amount, .60 ether); // same as before
        assertEq(claimable4[1].amount, 6 ether); // same as before
        assertEq(claimable4[2].amount, (100 ether - 1) * 12); // majin index * 12

        // user 3 stakes again
        vm.startPrank(address(3));
        kingshit_lp.approve(address(farm), .002 ether);
        farm.stake(2);
        vm.stopPrank();

        // add WAVAX via add function, not sending AVAX
        wavax.deposit{value: 2 ether}();
        wavax.approve(address(farm), 2 ether);
        farm.addReward(address(wavax), 2 ether);

        // check that user 3 is not claimable, then add time
        assertEq(farm.userCanClaim(address(3)), false);
        vm.warp(3600);

        // check that wavax wasn't added to valid tokens array again
        address[] memory validTokens = farm.getValidTokens();
        assertEq(validTokens.length, 3);

        // check rewards indexes
        rewardIndex_wavax = farm.tokenIndexForUser(address(farm), address(wavax));
        assertEq(rewardIndex_wavax, .15 ether); // old value .05 + .1 (2 ether / 20)

        rewardIndex_lucky = farm.tokenIndexForUser(address(farm), address(lucky));
        assertEq(rewardIndex_lucky, .5 ether); // same as before

        rewardIndex_majin = farm.tokenIndexForUser(address(farm), address(majin));
        assertEq(rewardIndex_majin, 100 ether - 1); // same as before

        // check claimable rewards
        assertEq(farm.userCanClaim(address(1)), true);
        claimable1 = farm.claimableForUser(address(1));
        assertEq(claimable1[0].amount, .15 ether); // previous claimable + .1
        assertEq(claimable1[1].amount, .5 ether); // same as before
        assertEq(claimable1[2].amount, 100 ether - 1); // same as before

        assertEq(farm.userCanClaim(address(2)), true);
        claimable2 = farm.claimableForUser(address(2));
        assertEq(claimable2[0].amount, .5 ether); // previous claimable + .1 * 5
        assertEq(claimable2[1].amount, 2.5 ether); // same as before
        assertEq(claimable2[2].amount, (100 ether - 1) * 5); // same as before

        assertEq(farm.userCanClaim(address(3)), true);
        claimable3 = farm.claimableForUser(address(3));
        assertEq(claimable3[0].amount, .2 ether); // previous claimable + .1 * 2
        assertEq(claimable3[1].amount, 0); // same as before
        assertEq(claimable3[2].amount, 0); // same as before

        assertEq(farm.userCanClaim(address(4)), true);
        claimable4 = farm.claimableForUser(address(4));
        assertEq(claimable4[0].amount, 1.80 ether); // previous claimable + .1 * 12
        assertEq(claimable4[1].amount, 6 ether); // same as before
        assertEq(claimable4[2].amount, (100 ether - 1) * 12); // same as before
        
    }

    function test_Reverts() public {
        vm.warp(2000);

        // cannot addRewards when no units staked
        wavax.deposit{value: 1 ether}();
        wavax.approve(address(farm), 1 ether);
        vm.expectRevert(BulletMultiTokenFarm.InvalidAmount.selector);
        farm.addReward(address(wavax), 1 ether);

        // public also cannot add rewards while no units staked
        wavax.transfer(address(1), 1 ether);
        vm.startPrank(address(1));
        wavax.approve(address(farm), 1 ether);
        vm.expectRevert(BulletMultiTokenFarm.InvalidAmount.selector);
        farm.addRewardPublic(address(wavax), 1 ether);(1);
        vm.stopPrank();

        // cannot deposit while paused
        farm.togglePaused();
        vm.prank(address(1));
        kingshit_lp.approve(address(farm), .001 ether);
        vm.expectRevert(BulletMultiTokenFarm.Paused.selector);
        vm.prank(address(1));
        farm.stake(1);
        farm.togglePaused();

        // cannot deposit 0
        vm.expectRevert(BulletMultiTokenFarm.InvalidAmount.selector);
        vm.prank(address(1));
        farm.stake(0);

        // cannot unstake 0
        vm.expectRevert(BulletMultiTokenFarm.NothingToWithdraw.selector);
        vm.prank(address(1));
        farm.unstake();

        // unstake fails due to cooldown
        vm.startPrank(address(2));
        kingshit_lp.approve(address(farm), .002 ether);
        farm.stake(2);
        vm.expectRevert(BulletMultiTokenFarm.CoolingDown.selector);
        farm.unstake();
        vm.stopPrank();        

        // cannot claim 0
        vm.expectRevert(BulletMultiTokenFarm.NothingToClaim.selector);
        vm.prank(address(2));
        farm.claim();

        // owner cannot withdraw LP tokens
        vm.expectRevert(BulletMultiTokenFarm.InvalidToken.selector);
        farm.withdrawERC20(address(kingshit_lp));

        // cannot deposit less than units staked
        uint stakedUnits = farm.stakedUnits();
        assertEq(stakedUnits, 2);
        wavax.approve(address(farm), 1);
        vm.expectRevert(BulletMultiTokenFarm.InvalidAmount.selector);
        farm.addReward(address(wavax), 1);

    }

    function test_RewardFallback() public {
        uint balanceBefore = address(FALLBACK_ADDY).balance;
        payable(address(farm)).call{value: 1 ether}("");
        uint balanceAfter = address(FALLBACK_ADDY).balance;
        assertEq(balanceAfter, balanceBefore + 1 ether);
    }
}
