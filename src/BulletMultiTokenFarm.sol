// SPDX-License-Identifier: UNLICENSED

import "openzeppelin-contracts/contracts/access/Ownable.sol";
import "openzeppelin-contracts/contracts/utils/ReentrancyGuard.sol";
import "openzeppelin-contracts/contracts/token/ERC20/IERC20.sol";
import "openzeppelin-contracts/contracts/token/ERC20/utils/SafeERC20.sol";

interface IWAVAX {
    function deposit() external payable;
    function balanceOf(address account) external view returns(uint);
}

pragma solidity ^0.8.22;

contract BulletMultiTokenFarm is Ownable, ReentrancyGuard {
    using SafeERC20 for IERC20;

    /// @notice Error caused by failed avax transfer
    error TransferFailed();

    /// @notice Error caused by invalid stake/unstake amount or not enough WAVAX to convert
    error InvalidAmount();

    /// @notice Error caused by trying to deposit an invalid reward token or owner trying to withdraw LP tokens
    error InvalidToken();

    /// @notice Error caused by trying to unstake or claim during the cooldown period
    error CoolingDown();

    /// @notice Error caused by trying to claim 0
    error NothingToClaim();

    /// @notice Error caused by trying to withdraw 0 
    error NothingToWithdraw();

    /// @notice Error caused by trying to deposit while paused
    error Paused();

    /// @notice Error caused by trying to set a variable to the 0 address
    error ZeroAddress();

    /// @notice Structure to store stake information
    struct Stake {
        uint units;
        uint lastStake;
    }

    /// @notice Structure to store user index information
    struct TokensClaimable {
        address token;
        uint amount;
    }

    /// @notice Fallback address in case a deposit is made that is less than the total number of staked units
    address public fallbackAddress;

    /// @notice Total number of staked LP units
    uint public stakedUnits;

    /// @notice Cooldown that prevents attackers from frontrunning the deposit of rewards and staking,
    /// claiming rewards, and then unstaking to earn without actually participating
    uint public cooldown;

    /// @notice Unit that normalizes staked LP tokens. Deposit amount must be divisible by this number
    uint public unit;

    /// @notice Boolean to determine whether deposits are paused
    bool public paused;

    /// @notice Current reward index for a user used to calculate rewards
    mapping(address => Stake) internal userStake;

    /// @notice Reward index by token for user
    mapping(address => mapping(address => uint)) internal userToTokenToIndex;

    /// @notice Current valid reward tokens as mapping and list
    mapping(address => bool) public tokenIsValid;
    address[] internal validTokens;

    /// @notice Wrapped AVAX contract
    IWAVAX public WAVAX;

    /// @notice The LP tokens that will be staked in the farm
    IERC20 public immutable LP;

    event UnitsStaked(address indexed staker, uint amount);
    event UnitsUnstaked(address indexed staker, uint amount);
    event TokensDistributed(address indexed token, uint amount);
    event RewardsClaimed(address indexed staker, TokensClaimable[] rewards);
    event RewardTokenAdded(address token);
    
    constructor(address _fallbackAddress, address _lpAddress, address _wavax, uint _unit, uint _cooldown) Ownable(msg.sender) {
        if (_fallbackAddress == address(0) ||
            _lpAddress == address(0) ||
            _wavax == address(0)) revert ZeroAddress();

        fallbackAddress = _fallbackAddress;
        LP = IERC20(_lpAddress);
        WAVAX = IWAVAX(_wavax);
        unit = _unit;
        cooldown = _cooldown;

        //initialize reward tokens with WAVAX
        tokenIsValid[_wavax] = true;
        validTokens.push(_wavax);
    }

    /// @dev Upon receipt of AVAX, calculate rewards per staked unit and wrap as WAVAX and update index. If 
    /// deposit amount is less than stakedUnits, send to fallbackAddress instead
    receive() external payable {
        if (msg.value < stakedUnits || stakedUnits == 0) {
            (bool success,) = payable(fallbackAddress).call{ value: msg.value }("");
            if (!success) revert TransferFailed();
        } else {
            uint rewardPerUnit = msg.value / stakedUnits;
            WAVAX.deposit{value: msg.value}();
            userToTokenToIndex[address(this)][address(WAVAX)] += rewardPerUnit;
            emit TokensDistributed(address(WAVAX), msg.value);
        }
    }

    /// @notice Function to stake LP tokens
    /// @dev Amount should be denominated in "unit"s
    function stake(uint amount) external nonReentrant {
        if (paused) revert Paused();
        if (amount == 0) revert InvalidAmount();
        Stake storage s = userStake[msg.sender];

        // Claim if there is anything claimable
        if (userCanClaim(msg.sender)) {
            _claim(msg.sender);
        } else {
            // Only necessary if not set in _claim
            uint length = validTokens.length;
            for (uint i = 0; i < length; i++) {
                userToTokenToIndex[msg.sender][validTokens[i]] = userToTokenToIndex[address(this)][validTokens[i]];
            }
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
        if (userCanClaim(msg.sender)) {
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
        if (!userCanClaim(msg.sender)) revert NothingToClaim();

        _claim(msg.sender);
    }

    /// @notice Admin function to toggle the pause of deposits
    function togglePaused() external onlyOwner {
        paused = !paused;
    }

    /// @notice Admin function to set fallback address
    function setFallbackAddress(address _fallbackAddress) external onlyOwner {
        if (_fallbackAddress == address(0)) revert ZeroAddress();
        fallbackAddress = _fallbackAddress;
    }

    /// @notice Admin function to withdraw all of an ERC20 token sent in error
    /// @dev CAUTION! If reward tokens are withdrawn after being added it can cause contract failures. 
    function withdrawERC20(address _contract) external onlyOwner {
        if (_contract == address(LP)) revert InvalidToken();
        IERC20 token = IERC20(_contract);
        token.safeTransfer(msg.sender, token.balanceOf(address(this)));
    }

    /// @notice Admin function to add reward tokens
    function addReward(address _token, uint _amount) external onlyOwner {
        if (_amount < stakedUnits || stakedUnits == 0) revert InvalidAmount();

        // if not already a valid token, make it one
        if (!tokenIsValid[_token]) {
            tokenIsValid[_token] = true;
            validTokens.push(_token);
        }

        IERC20(_token).safeTransferFrom(msg.sender, address(this), _amount);

        // calculate reward per unit and update index
        uint rewardPerUnit = _amount / stakedUnits;
        userToTokenToIndex[address(this)][_token] += rewardPerUnit;
    }
    
    /// @notice Function for public to add rewards for valid tokens
    function addRewardPublic(address _token, uint _amount) external {
        if (_amount < stakedUnits || stakedUnits == 0) revert InvalidAmount();

        // token must be valid
        if (!tokenIsValid[_token]) revert InvalidToken();

        IERC20(_token).safeTransferFrom(msg.sender, address(this), _amount);

        // calculate reward per unit and update index
        uint rewardPerUnit = _amount / stakedUnits;
        userToTokenToIndex[address(this)][_token] += rewardPerUnit;
    }

    /// @notice View function to get valid tokens array
    function getValidTokens() external view returns(address[] memory) {
        return validTokens;
    }

    /// @notice View function for a user's token index
    function tokenIndexForUser(address user, address token) public view returns(uint) {
        return userToTokenToIndex[user][token];
    }

    /// @notice View function to get claimable amount for user
    function claimableForUser(address user) public view returns(TokensClaimable[] memory) {
        Stake memory s = userStake[user];

        TokensClaimable[] memory claimable = new TokensClaimable[](validTokens.length);

        uint length = validTokens.length;
        for (uint i = 0; i < length; i++) {
            uint amountClaimable = (userToTokenToIndex[address(this)][validTokens[i]] - 
                                    userToTokenToIndex[user][validTokens[i]]) * s.units;

            claimable[i] = TokensClaimable({
                token: validTokens[i],
                amount: s.units == 0 || block.timestamp < s.lastStake + cooldown ? 0 : amountClaimable
            });
        }

        return claimable;
    }

    /// @notice View function to check if user has anything claimable
    function userCanClaim(address user) public view returns(bool) {
        TokensClaimable[] memory claimable = claimableForUser(user);

        uint length = claimable.length;
        for (uint i = 0; i < length; i++) {
            if (claimable[i].amount > 0) {
                return true;
            }
        }

        return false;
    }

    /// @notice View function to get a user's stake information
    function getUserStake(address user) external view returns (Stake memory) {
        return userStake[user];
    }

    /// @notice Internal function to claim rewards
    function _claim(address user) internal {
        Stake storage s = userStake[msg.sender];
        TokensClaimable[] memory claimable = claimableForUser(user);
        s.lastStake = block.timestamp;
        
        uint length = claimable.length;
        for (uint i = 0; i < length; i++) {
            IERC20 token = IERC20(claimable[i].token);
            uint reward = claimable[i].amount;

            // Safety feature in case rounding causes a minor discrepancy in the amount left for final withdrawal
            if (reward > token.balanceOf(address(this))) {
                reward = token.balanceOf(address(this));
            }

            if (reward > 0) {
                userToTokenToIndex[user][claimable[i].token] = userToTokenToIndex[address(this)][claimable[i].token];
                token.safeTransfer(user, reward);
            }
        }

        emit RewardsClaimed(user, claimable);
    }
}