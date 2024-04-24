// SPDX-License-Identifier: UNLICENSED

import "openzeppelin-contracts/contracts/access/Ownable.sol";
import "openzeppelin-contracts/contracts/utils/ReentrancyGuard.sol";
import "openzeppelin-contracts/contracts/token/ERC20/IERC20.sol";
import "openzeppelin-contracts/contracts/token/ERC20/utils/SafeERC20.sol";

interface IWAVAX {
    function withdraw(uint256 amount) external;
    function balanceOf(address account) external view returns(uint);
}

pragma solidity ^0.8.22;

contract BulletRoyaltyFarm is Ownable, ReentrancyGuard {
    using SafeERC20 for IERC20;

    /// @notice Error caused by failed avax transfer
    error TransferFailed();

    /// @notice Error caused by invalid stake/unstake amount or not enough WAVAX to convert
    error InvalidAmount();

    /// @notice Error caused by trying to unstake or claim during the cooldown period
    error CoolingDown();

    /// @notice Error caused by trying to claim 0
    error NothingToClaim();

    /// @notice Error caused by trying to withdraw 0 
    error NothingToWithdraw();

    /// @notice Error caused by trying to deposit while paused
    error Paused();

    /// @notice Structure to store stake information
    struct Stake {
        uint units;
        uint rewardIndex;
        uint lastStake;
    }

    /// @notice Fallback address in case a deposit is made that is less than the total number of staked units
    address public fallbackAddress;

    /// @notice Total number of staked LP units
    uint public stakedUnits;

    /// @notice Current farm reward index used to calculate rewards
    uint public farmRewardIndex;

    /// @notice Cooldown that prevents attackers from frontrunning the deposit of rewards and staking,
    /// claiming rewards, and then unstaking to earn without actually participating
    uint public cooldown;

    /// @notice Unit that normalizes staked LP tokens. Deposit amount must be divisible by this number
    uint public unit;

    /// @notice Boolean to determine whether deposits are paused
    bool public paused;

    /// @notice Current reward index for a user used to calculate rewards
    mapping(address => Stake) internal userStake;

    /// @notice Wrapped AVAX contract
    IWAVAX public WAVAX;

    /// @notice The LP tokens that will be staked in the farm
    IERC20 public immutable LP;

    event UnitsStaked(address staker, uint amount);
    event UnitsUnstaked(address staker, uint amount);
    event AvaxDistributed(uint amount);
    event RewardsClaimed(address staked, uint rewards);
    
    constructor(address _fallbackAddress, address _lpAddress, address _wavax, uint _unit, uint _cooldown) Ownable(msg.sender) {
        fallbackAddress = _fallbackAddress;
        LP = IERC20(_lpAddress);
        WAVAX = IWAVAX(_wavax);
        unit = _unit;
        cooldown = _cooldown;
    }

    /// @dev Upon receipt of AVAX, calculate rewards per staked unit and update rewardIndex. If 
    /// deposit amount is less than stakedUnits, send to fallbackAddress instead
    receive() external payable {
        if (msg.value < stakedUnits || stakedUnits == 0) {
            (bool success,) = payable(fallbackAddress).call{ value: msg.value }("");
            if (!success) revert TransferFailed();
        } else {
            uint rewardPerUnit = msg.value / stakedUnits;
            farmRewardIndex += rewardPerUnit;
            emit AvaxDistributed(msg.value);
        }
    }

    /// @notice Function to stake LP tokens
    /// @dev Amount should be denominated in "unit"s
    function stake(uint amount) external nonReentrant {
        if (paused) revert Paused();
        if (amount == 0) revert InvalidAmount();
        Stake storage s = userStake[msg.sender];

        // Claim if there is anything claimable
        if (claimableForUser(msg.sender) > 0) {
            _claim(msg.sender);
        } else {
            // Only necessary if not set in _claim
            s.rewardIndex = farmRewardIndex;
            s.lastStake = block.timestamp;
        }

        LP.safeTransferFrom(msg.sender, address(this), amount * unit);

        s.units += amount;
        stakedUnits += amount;

        emit UnitsStaked(msg.sender, amount);
    }

    /// @notice function to unstake LP tokens
    /// @dev Partial withdrawals are not allowed
    function unstake() external nonReentrant {
        Stake memory s = userStake[msg.sender];
        if (block.timestamp < s.lastStake + cooldown) revert CoolingDown();
        if (s.units == 0) revert NothingToWithdraw();

        // Claim if already staked and there are pending rewards
        if (claimableForUser(msg.sender) > 0) {
            _claim(msg.sender);
        }

        uint unitsWithdrawn = s.units;

        uint amountToTransfer = unitsWithdrawn * unit;

        stakedUnits -= unitsWithdrawn;

        delete userStake[msg.sender];

        LP.safeTransfer(msg.sender, amountToTransfer);

        emit UnitsUnstaked(msg.sender, unitsWithdrawn);
    }

    /// @notice Function to claim rewards
    function claim() external nonReentrant {
        if (claimableForUser(msg.sender) == 0) revert NothingToClaim();

        _claim(msg.sender);
    }

    /// @notice Function to convert WAVAX and distribute rewards
    /// @dev Reward distribution should happen in the receive function once AVAX is unwrapped
    function unwrapAVAX() external {
        uint balance = WAVAX.balanceOf(address(this));
        if (balance < stakedUnits || stakedUnits == 0) revert InvalidAmount();

        // Unwrap WAVAX
        WAVAX.withdraw(balance);
    }

    /// @notice Admin function to toggle the pause of deposits
    function togglePaused() external onlyOwner {
        paused = !paused;
    }

    /// @notice Admin function to withdraw all AVAX from contract in case of emergency or migration
    function withdrawAVAX() external onlyOwner {
        (bool success,) = payable(msg.sender).call{ value: address(this).balance }("");
        if (!success) revert TransferFailed();
    }

    /// @notice Admin function to withdraw all of an ERC20 token sent in error
    function withdrawERC20(address _contract) external onlyOwner {
        IERC20 token = IERC20(_contract);
        token.safeTransfer(msg.sender, token.balanceOf(address(this)));
    }

    /// @notice View function to get claimable amount for user
    function claimableForUser(address user) public view returns(uint) {
        Stake memory s = userStake[user];
        if (s.units == 0 || 
            s.rewardIndex == farmRewardIndex ||
            block.timestamp < s.lastStake + cooldown
            ) {
            return 0;
        }

        return (farmRewardIndex - s.rewardIndex) * s.units;
    }

    /// @notice View function to get a user's stake information
    function getUserStake(address user) external view returns (Stake memory) {
        return userStake[user];
    }

    /// @notice Internal function to claim rewards
    function _claim(address user) internal {
        Stake storage s = userStake[msg.sender];
        uint rewards = claimableForUser(user);

        // Safety feature in case rounding causes a minor discrepancy in the amount left for final withdrawal
        if (rewards > address(this).balance) {
            rewards = address(this).balance;
        }

        s.lastStake = block.timestamp;
        s.rewardIndex = farmRewardIndex;

        (bool success,) = payable(user).call{ value: rewards }("");
        if (!success) revert TransferFailed();

        emit RewardsClaimed(user, rewards);
    }
}