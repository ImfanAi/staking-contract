    // SPDX-License-Identifier: MIT
    pragma solidity ^0.8.19;

    import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
    import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
    import {ReentrancyGuard} from "@openzeppelin/contracts/utils/ReentrancyGuard.sol";
    import "@openzeppelin/contracts/access/Ownable.sol";
    /**
    * @title Staking Contract
    * @dev A staking contract that allows users to stake ERC20 tokens and earn rewards based on staking duration and tier.
    * The contract supports multiple staking periods, APRs, and tiers with multipliers for rewards.
    */
    contract Staking is Ownable, ReentrancyGuard {
        using SafeERC20 for IERC20;
        IERC20 public stakingToken; // The ERC20 token used for staking

        struct Stake {
            uint256 tokenAmount; // Amount of tokens staked
            uint256 startTime; // Timestamp when staking started
            uint256 stakingType; // Type of staking (0 = flexible, 1+ = locked)
            address user; // Address of the staker
            uint256 id; // Unique ID of the stake
            bool finished; // Whether the stake is withdrawn
        }

        // Staking periods in days (0 = flexible, 1 = 1 month, 3 = 3 months, etc.)
        uint256[] public stakingPeriods = [
            0 days,
            1 * 30 days,
            3 * 30 days,
            6 * 30 days,
            12 * 30 days
        ];

        // Annual Percentage Rates (APR) for each staking type
        uint256[] public stakingAPRs = [30, 42, 60, 90, 120];

        // Multipliers for staking types (used for launchpad tier calculation)
        uint256[] public stakingMultipliers = [0, 1000, 1500, 2200, 4000];

        uint256 public constant BASE = 1000; // Base value for APR calculations

        Stake[] public stakes; // Array of all stakes
        uint256 public totalNumberOfStakes; // Total number of stakes created
        uint256 public totalAmountOfStakes; // Total amount of stakes
        bool public isOpen; // Whether staking is open
        uint256 public totalPaidRewards; // Total paid rewards
        uint256 public BASE_SCORE_VALUE = 1; // Base score value used as multiplier in score calculations
        bool public depositsPaused; // Whether deposits are paused

        mapping(uint256 => uint256) public rewards; // Mapping of stake ID to reward amount

        mapping(address => uint256) public rewardsPerUser; // Mapping of user address to their total reward amount

        mapping(uint8 => uint256) public tierScore; // Mapping of tier level (uint8) to its required score

        event Deposit(address indexed user, uint256 amount, uint256 stakingType);
        event Withdraw(uint256 indexed id, uint256 rewardAmount);
        event Restake(uint256 indexed id, uint256 stakingType);
        event EmergencyWithdraw(address indexed user, uint256 stakeId, uint256 amount, uint256 reward);

        /**
        * @dev Constructor to initialize the staking contract.
        * @param _stakingToken Address of the ERC20 token used for staking.
        */
        constructor(address _stakingToken) Ownable(msg.sender) {
            stakingToken = IERC20(_stakingToken);
            totalNumberOfStakes = 0;
            totalAmountOfStakes = 0;
            tierScore[0] = 0;
            tierScore[1] = 50_000;
            tierScore[2] = 150_000;
            tierScore[3] = 250_000;
            tierScore[4] = 500_000;
        }

        /**
        * @dev Initializes the staking contract by transferring tokens to the contract.
        * @param _amount Amount of tokens to transfer.
        */
        function initialize(uint256 _amount) external onlyOwner {
            require(!isOpen, "Already initialized");
            stakingToken.safeTransferFrom(msg.sender, address(this), _amount);
            isOpen = true;
        }

        /**
        * @dev Allows a user to stake tokens.
        * @param _amount Amount of tokens to stake.
        * @param _user Address of the user to stake for.
        * @param _stakingType Type of staking (0 = flexible, 1+ = locked).
        */
        function stakeTokens(
            uint256 _amount,
            address _user,
            uint256 _stakingType
        ) external {
            require(isOpen, "Staking is not available");
            require(!depositsPaused, "Deposits are paused");
            require(_amount > 0, "Cannot stake 0 tokens");
            require(_stakingType < stakingPeriods.length, "Invalid staking type");

            stakes.push(
                Stake({
                    tokenAmount: _amount,
                    startTime: block.timestamp,
                    stakingType: _stakingType,
                    user: _user,
                    id: totalNumberOfStakes,
                    finished: false
                })
            );

            totalNumberOfStakes++;
            totalAmountOfStakes += _amount;
            stakingToken.safeTransferFrom(msg.sender, address(this), _amount);
            emit Deposit(msg.sender, _amount, _stakingType);
        }

        /**
        * @dev Initiates the unlock process for a locked stake.
        * @param _id ID of the stake to unlock.
        */
        function initiateUnlock(uint256 _id) external {
            Stake storage stake = stakes[_id];
            require(!stake.finished, "Stake already withdrawn");
            require(stake.user == msg.sender, "Not the stake owner");

            uint256 stakingDuration = block.timestamp - stake.startTime;
            if (stake.stakingType != 0) {
                require(
                    stakingDuration > stakingPeriods[stake.stakingType],
                    "Lock period not reached"
                );
            }
        }

        /**
        * @dev Allows a user to withdraw their stake and rewards.
        * @param _id ID of the stake to withdraw.
        */
        function withdrawStake(uint256 _id) external nonReentrant {
            Stake storage stake = stakes[_id];
            require(!stake.finished, "Stake already withdrawn");
            require(stake.user == msg.sender, "Not the stake owner");
            uint256 rewardAmount = calculateReward(_id);
            require(rewardAmount > 0, "Insufficient reward amount");
            stake.finished = true;
            require(
                stakingToken.balanceOf(address(this)) >=
                    stake.tokenAmount + rewardAmount,
                "Not enough token in staking contract."
            );
            stakingToken.safeTransfer(msg.sender, stake.tokenAmount + rewardAmount);
            rewards[_id] = rewardAmount;
            rewardsPerUser[msg.sender] += rewardAmount;
            totalPaidRewards += rewardAmount;
            totalAmountOfStakes -= stake.tokenAmount;
            emit Withdraw(_id, rewardAmount);
        }

        /**
        * @dev Allows a user to restake their rewards into a new stake.
        * @param _id ID of the stake to restake.
        * @param _stakingType New staking type for the restake.
        */
        function restakeRewards(uint256 _id, uint256 _stakingType) external {
            Stake storage stake = stakes[_id];
            require(!stake.finished, "Stake already withdrawn");
            require(stake.user == msg.sender, "Not the stake owner");
            require(_stakingType < stakingPeriods.length, "Invalid staking type");
            uint256 rewardAmount = calculateReward(_id);
            require(rewardAmount > 0, "Insufficient reward amount");
            
            // Mark old stake as finished
            stake.finished = true;
            
            // Create new stake with combined amount
            uint256 newAmount = stake.tokenAmount + rewardAmount;
            stakes.push(
                Stake({
                    tokenAmount: newAmount,
                    startTime: block.timestamp,
                    stakingType: _stakingType,
                    user: msg.sender,
                    id: totalNumberOfStakes,
                    finished: false
                })
            );
            
            totalNumberOfStakes++;
            totalAmountOfStakes = totalAmountOfStakes - stake.tokenAmount + newAmount;
            emit Restake(_id, _stakingType);
        }

        /**
        * @dev Returns the list of stake IDs owned by a specific address.
        * @param _owner Address of the staker.
        * @return Array of stake IDs.
        */
        function getStakeIdsByOwner(
            address _owner
        ) public view returns (uint256[] memory) {
            uint256[] memory ids = new uint256[](totalNumberOfStakes);
            uint256 count = 0;
            for (uint256 i = 0; i < totalNumberOfStakes; i++) {
                Stake storage stake = stakes[i];
                if (stake.user == _owner) {
                    ids[count] = i;
                    count++;
                }
            }
            uint256[] memory result = new uint256[](count);
            for (uint256 j = 0; j < count; j++) {
                result[j] = ids[j];
            }
            return result;
        }

        /**
        * @dev Calculates the reward for a specific stake.
        * @param _id ID of the stake.
        * @return Reward amount.
        */
        function calculateReward(uint256 _id) public view returns (uint256) {
            Stake storage stake = stakes[_id];
            if (stake.finished) return 0;
            
            uint256 rewardDuration = block.timestamp - stake.startTime;
            uint256 lockPeriod = stakingPeriods[stake.stakingType];

            if (rewardDuration > lockPeriod && stake.stakingType != 0) {
                uint256 lockedReward = stake.tokenAmount * lockPeriod * stakingAPRs[stake.stakingType] / (365 days * BASE);
                uint256 flexReward = stake.tokenAmount * (rewardDuration - lockPeriod) * stakingAPRs[0] / (365 days * BASE);
                return lockedReward + flexReward;
            } else {
                return stake.tokenAmount * rewardDuration * stakingAPRs[stake.stakingType] / (365 days * BASE);
            }
        }

        /**
        * @dev Returns the total number of stakes in the contract.
        * @return Total number of stakes.
        */
        function getTotalStakes() public view returns (uint256) {
            return totalNumberOfStakes;
        }

        /**
        * @dev Returns the details of a specific stake.
        * @param _id ID of the stake.
        * @return Stake details.
        */
        function getStakeDetails(uint256 _id) public view returns (Stake memory) {
            return stakes[_id];
        }

        /**
        * @dev Sets the score required for a specific tier level.
        * @param _tier The tier level to set score.
        * @param _score The score value to set for the tier.
        * @notice Only callable by contract owner.
        */
        function setTierScore(uint8 _tier, uint256 _score) external onlyOwner {
            tierScore[_tier] = _score;
        }

        /**
        * @dev Sets the base score value used in total score calculations.
        * @param _newValue The new base score value to use.
        * @notice Only callable by contract owner.
        */
        function setBaseScoreValue(uint256 _newValue) external onlyOwner {
            BASE_SCORE_VALUE = _newValue;
        }

        /**
        * @dev Calculates and returns the total score for a given owner.
        * @param _owner Address of the user to calculate score for.
        * @return totalScore The calculated total score based on user's stakes.
        * @notice Score is calculated as: sum of (tokenAmount * BASE_SCORE_VALUE * stakingMultiplier / 100) for all stakes.
        */
        function getTotalScore(address _owner) public view returns (uint256) {
            uint256[] memory ids = getStakeIdsByOwner(_owner);
            uint256 totalScore = 0;
            for (uint256 i = 0; i < ids.length; i++) {
                Stake storage stake = stakes[ids[i]];
                if (stake.finished) continue;
                uint256 rewardTime = stakingPeriods[stake.stakingType];
                uint256 stakingDuration = block.timestamp - stake.startTime;
                uint256 exceeds = 1;
                if (stakingDuration > rewardTime) {
                    exceeds = 0;
                }
                totalScore +=
                    ((exceeds *
                        stake.tokenAmount *
                        stakingMultipliers[stake.stakingType] +
                        (1 - exceeds) *
                        stake.tokenAmount *
                        stakingMultipliers[0]) * BASE_SCORE_VALUE) /
                    BASE /
                    1e9;
            }
            return totalScore;
        }
        /**
        * @dev Determines the tier level for a given owner based on their total score
        * @param _owner The address of the owner to check the tier for
        * @return tier The tier level (1-5) that the owner qualifies for
        * @notice The tier is determined by comparing the owner's total score against predefined tier thresholds
        * @notice Tier levels range from 1 to 5, with 5 being the highest
        * @notice The owner's tier is the highest level where their score meets or exceeds the tier's threshold
        */
        function getTierByOwner(address _owner) public view returns (uint8) {
            uint256 totalScore = getTotalScore(_owner);
            uint8 tier;
            for (uint8 i = 0; i < 5; i++) {
                if (totalScore >= tierScore[i]) {
                    tier = i + 1;
                }
            }
            return tier;
        }

        function getUsersSortedByScore()
            public
            view
            returns (address[] memory, uint256[] memory)
        {
            // First, collect all unique users with active stakes
            address[] memory allUsers = new address[](stakes.length);
            uint256 userCount = 0;

            // Use an array to track processed addresses instead of mapping
            address[] memory processed = new address[](stakes.length);
            uint256 processedCount = 0;

            // Find all unique users with active stakes
            for (uint256 i = 0; i < stakes.length; i++) {
                Stake storage stake = stakes[i];
                if (stake.finished) continue;

                bool alreadyProcessed = false;
                for (uint256 j = 0; j < processedCount; j++) {
                    if (processed[j] == stake.user) {
                        alreadyProcessed = true;
                        break;
                    }
                }

                if (!alreadyProcessed) {
                    allUsers[userCount] = stake.user;
                    processed[processedCount] = stake.user;
                    userCount++;
                    processedCount++;
                }
            }

            // Create properly sized arrays
            address[] memory users = new address[](userCount);
            uint256[] memory scores = new uint256[](userCount);

            // Populate with actual users and their scores
            for (uint256 i = 0; i < userCount; i++) {
                users[i] = allUsers[i];
                scores[i] = getTotalScore(allUsers[i]);
            }

            // Sort using simple bubble sort (not gas efficient for large arrays)
            for (uint256 i = 0; i < userCount - 1; i++) {
                for (uint256 j = 0; j < userCount - i - 1; j++) {
                    if (scores[j] < scores[j + 1]) {
                        // Swap scores
                        (scores[j], scores[j + 1]) = (scores[j + 1], scores[j]);
                        // Swap addresses
                        (users[j], users[j + 1]) = (users[j + 1], users[j]);
                    }
                }
            }
            return (users, scores);
        }

        /**
        * @dev Returns all addresses that belong to a specific tier.
        * @param tier The tier level to snapshot (1-5).
        * @return Array of addresses in the specified tier.
        * @notice Only callable by contract owner.
        */
        function snapshotTier(uint8 tier) external view onlyOwner returns (address[] memory) {
            require(tier > 0 && tier <= 5, "Invalid tier");
            
            address[] memory temp = new address[](stakes.length);
            uint256 count = 0;
            
            for (uint256 i = 0; i < stakes.length; i++) {
                if (!stakes[i].finished && getTierByOwner(stakes[i].user) == tier) {
                    bool exists = false;
                    for (uint256 j = 0; j < count; j++) {
                        if (temp[j] == stakes[i].user) {
                            exists = true;
                            break;
                        }
                    }
                    if (!exists) {
                        temp[count] = stakes[i].user;
                        count++;
                    }
                }
            }
            
            address[] memory result = new address[](count);
            for (uint256 k = 0; k < count; k++) {
                result[k] = temp[k];
            }
            return result;
        }

        /**
        * @dev Sets the APR for a specific staking type.
        * @param stakingType The staking type to update (0-4).
        * @param newAPR The new APR value to set.
        * @notice Only callable by contract owner.
        */
        function setAPR(uint8 stakingType, uint256 newAPR) external onlyOwner {
            require(stakingType < stakingAPRs.length, "Invalid type");
            stakingAPRs[stakingType] = newAPR;
        }

        /**
        * @dev Pauses all new deposits.
        * @notice Only callable by contract owner.
        */
        function pauseDeposits() external onlyOwner {
            depositsPaused = true;
        }

        /**
        * @dev Unpauses deposits.
        * @notice Only callable by contract owner.
        */
        function unpauseDeposits() external onlyOwner {
            depositsPaused = false;
        }

        /**
        * @dev Emergency withdrawal function for a specific user that returns all their staked tokens and rewards.
        * @param user The address of the user to process emergency withdrawal for.
        * @notice Only callable by contract owner when deposits are paused.
        * @notice This function will process all unfinished stakes for the specified user.
        */
        function emergencyWithdrawUser(address user) external onlyOwner {
            require(depositsPaused, "Must pause before emergency withdraw");
            require(user != address(0), "Invalid user address");

            uint256[] memory ids = getStakeIdsByOwner(user);
            uint256 totalRequiredPayout = 0;

            // First pass: calculate total required payout
            for (uint256 i = 0; i < ids.length; i++) {
                uint256 stakeId = ids[i];
                Stake storage stake = stakes[stakeId];
                if (stake.finished) continue;

                uint256 rewardAmount = calculateReward(stakeId);
                totalRequiredPayout += stake.tokenAmount + rewardAmount;
            }

            // Verify contract has enough balance
            require(
                stakingToken.balanceOf(address(this)) >= totalRequiredPayout,
                "Not enough funds for emergency withdrawal"
            );

            // Second pass: process withdrawals
            for (uint256 i = 0; i < ids.length; i++) {
                uint256 stakeId = ids[i];
                Stake storage stake = stakes[stakeId];
                if (stake.finished) continue;

                uint256 rewardAmount = calculateReward(stakeId);
                uint256 totalPayout = stake.tokenAmount + rewardAmount;

                stake.finished = true;
                rewards[stakeId] = rewardAmount;
                rewardsPerUser[user] += rewardAmount;
                totalPaidRewards += rewardAmount;
                totalAmountOfStakes -= stake.tokenAmount;

                stakingToken.safeTransfer(user, totalPayout);

                emit EmergencyWithdraw(user, stakeId, stake.tokenAmount, rewardAmount);
            }
        }

        /**
        * @dev Emergency withdrawal function that returns all staked tokens and rewards to users.
        * @notice Only callable by contract owner when deposits are paused.
        * @notice This function will process all unfinished stakes and return tokens to users.
        */
        function emergencyWithdrawAll() external onlyOwner {
            require(depositsPaused, "Pause deposits first");
            
            // First pass: calculate total required payout
            uint256 totalRequiredPayout = 0;
            for (uint256 i = 0; i < stakes.length; i++) {
                Stake storage stake = stakes[i];
                if (stake.finished) continue;
                
                uint256 rewardAmount = calculateReward(i);
                totalRequiredPayout += stake.tokenAmount + rewardAmount;
            }
            
            // Verify contract has enough balance
            require(
                stakingToken.balanceOf(address(this)) >= totalRequiredPayout,
                "Not enough funds for emergency withdrawal"
            );
            
            // Second pass: process withdrawals
            for (uint256 i = 0; i < stakes.length; i++) {
                Stake storage stake = stakes[i];
                if (stake.finished) continue;

                uint256 rewardAmount = calculateReward(i);
                uint256 totalPayout = stake.tokenAmount + rewardAmount;

                stake.finished = true;
                rewards[i] = rewardAmount;
                rewardsPerUser[stake.user] += rewardAmount;
                totalPaidRewards += rewardAmount;
                totalAmountOfStakes -= stake.tokenAmount;

                stakingToken.safeTransfer(stake.user, totalPayout);

                emit EmergencyWithdraw(stake.user, stake.id, stake.tokenAmount, rewardAmount);
            }
        }
    }
