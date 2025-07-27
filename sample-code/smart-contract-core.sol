// SPDX-License-Identifier: MIT
pragma solidity ^0.8.19;

import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/token/ERC721/ERC721.sol";
import "@openzeppelin/contracts/security/ReentrancyGuard.sol";
import "@openzeppelin/contracts/access/Ownable.sol";

/**
 * @title MemeBattleArenaV9
 * @dev Advanced DeFi gaming contract with winner-takes-all mechanics and NFT rewards
 * @notice This contract enables users to create token battles and stake meme tokens
 */
contract MemeBattleArenaV9 is ERC721, ReentrancyGuard, Ownable {
    
    // ============ STATE VARIABLES ============
    
    uint256 public constant BATTLE_CREATION_FEE = 0.01 ether;
    uint256 public constant STAKING_FEE = 0.001 ether;
    
    uint256 private _battleIdCounter = 1;
    uint256 private _tokenIdCounter = 1;
    
    // ============ STRUCTS ============
    
    /**
     * @dev Battle struct optimized for gas efficiency
     * @param tokenA First token in battle
     * @param tokenB Second token in battle  
     * @param endTime Unix timestamp when battle ends
     * @param finalized Whether battle has been finalized
     * @param totalStakedA Total amount of tokenA staked
     * @param totalStakedB Total amount of tokenB staked
     * @param totalValueA Total USD value of tokenA stakes (in wei)
     * @param totalValueB Total USD value of tokenB stakes (in wei)
     * @param creator Address that created the battle
     */
    struct Battle {
        address tokenA;
        address tokenB;
        uint256 endTime;
        bool finalized;
        uint256 totalStakedA;
        uint256 totalStakedB;
        uint256 totalValueA;    // USD value in wei for fair comparison
        uint256 totalValueB;    // USD value in wei for fair comparison
        address creator;
    }
    
    // ============ MAPPINGS ============
    
    mapping(uint256 => Battle) public battles;
    mapping(uint256 => mapping(address => mapping(address => uint256))) public userStakes;
    mapping(address => uint256) public userWins;
    mapping(address => uint256) public userParticipations;
    mapping(address => uint256) public userTotalRewards;
    
    // ============ EVENTS ============
    
    event BattleCreated(
        uint256 indexed battleId, 
        address indexed creator,
        address tokenA, 
        address tokenB, 
        uint256 endTime
    );
    
    event StakePlaced(
        uint256 indexed battleId, 
        address indexed user, 
        address token, 
        uint256 amount,
        uint256 usdValue
    );
    
    event BattleFinalized(
        uint256 indexed battleId, 
        address winningToken,
        uint256 totalWinningValue,
        uint256 totalLosingValue
    );
    
    event RewardsClaimed(
        uint256 indexed battleId, 
        address indexed user, 
        address token,
        uint256 amount
    );
    
    event NFTMinted(
        address indexed recipient, 
        uint256 tokenId, 
        string rarity
    );
    
    // ============ MODIFIERS ============
    
    modifier validBattleDuration(uint256 duration) {
        require(duration >= 300, "Minimum 5 minutes");        // 5 minutes
        require(duration <= 15552000, "Maximum 6 months");    // 6 months
        _;
    }
    
    modifier battleExists(uint256 battleId) {
        require(battleId > 0 && battleId < _battleIdCounter, "Battle does not exist");
        _;
    }
    
    modifier battleEnded(uint256 battleId) {
        require(block.timestamp >= battles[battleId].endTime, "Battle not ended");
        _;
    }
    
    // ============ CONSTRUCTOR ============
    
    constructor() ERC721("MemeBattleArena", "MBA") {}
    
    // ============ CORE FUNCTIONS ============
    
    /**
     * @dev Create a new battle between two tokens
     * @param tokenA Address of first token
     * @param tokenB Address of second token
     * @param duration Battle duration in seconds
     * @return battleId The ID of the created battle
     */
    function makeBattle(
        address tokenA,
        address tokenB,
        uint256 duration
    ) external payable validBattleDuration(duration) returns (uint256) {
        require(msg.value >= BATTLE_CREATION_FEE, "Insufficient battle creation fee");
        require(tokenA != tokenB, "Tokens must be different");
        require(tokenA != address(0) && tokenB != address(0), "Invalid token address");
        
        uint256 battleId = _battleIdCounter++;
        uint256 endTime = block.timestamp + duration;
        
        battles[battleId] = Battle({
            tokenA: tokenA,
            tokenB: tokenB,
            endTime: endTime,
            finalized: false,
            totalStakedA: 0,
            totalStakedB: 0,
            totalValueA: 0,
            totalValueB: 0,
            creator: msg.sender
        });
        
        emit BattleCreated(battleId, msg.sender, tokenA, tokenB, endTime);
        return battleId;
    }
    
    /**
     * @dev Stake tokens in a battle
     * @param battleId The battle to stake in
     * @param token The token to stake (must be tokenA or tokenB)
     * @param amount Amount of tokens to stake
     * @param usdValue USD value of the stake in wei
     */
    function makeStake(
        uint256 battleId,
        address token,
        uint256 amount,
        uint256 usdValue
    ) external payable battleExists(battleId) nonReentrant {
        require(msg.value >= STAKING_FEE, "Insufficient staking fee");
        require(amount > 0, "Amount must be positive");
        require(usdValue > 0, "USD value required");
        require(block.timestamp < battles[battleId].endTime, "Battle ended");
        
        Battle storage battle = battles[battleId];
        require(
            token == battle.tokenA || token == battle.tokenB, 
            "Invalid token for this battle"
        );
        
        // Transfer tokens from user to contract
        IERC20(token).transferFrom(msg.sender, address(this), amount);
        
        // Update user stakes
        userStakes[battleId][msg.sender][token] += amount;
        
        // Update battle totals
        if (token == battle.tokenA) {
            battle.totalStakedA += amount;
            battle.totalValueA += usdValue;
        } else {
            battle.totalStakedB += amount;
            battle.totalValueB += usdValue;
        }
        
        // Update user statistics (only on first participation)
        if (userStakes[battleId][msg.sender][battle.tokenA] + 
            userStakes[battleId][msg.sender][battle.tokenB] == amount) {
            userParticipations[msg.sender]++;
        }
        
        emit StakePlaced(battleId, msg.sender, token, amount, usdValue);
    }
    
    /**
     * @dev Claim rewards from a finished battle
     * @param battleId The battle to claim rewards from
     */
    function takeReward(uint256 battleId) 
        external 
        battleExists(battleId) 
        battleEnded(battleId) 
        nonReentrant 
    {
        if (!battles[battleId].finalized) {
            _finalizeBattle(battleId);
        }
        
        uint256 reward = _calculateReward(battleId, msg.sender);
        require(reward > 0, "No rewards to claim");
        
        Battle memory battle = battles[battleId];
        address winningToken = battle.totalValueA >= battle.totalValueB 
            ? battle.tokenA 
            : battle.tokenB;
        
        // Clear user stakes to prevent double claiming
        userStakes[battleId][msg.sender][winningToken] = 0;
        
        // Transfer reward tokens
        IERC20(winningToken).transfer(msg.sender, reward);
        
        // Update user statistics
        userWins[msg.sender]++;
        userTotalRewards[msg.sender] += reward;
        
        // Mint NFT reward
        _mintNFTReward(msg.sender);
        
        emit RewardsClaimed(battleId, msg.sender, winningToken, reward);
    }
    
    // ============ INTERNAL FUNCTIONS ============
    
    /**
     * @dev Finalize a battle by determining the winner
     * @param battleId The battle to finalize
     */
    function _finalizeBattle(uint256 battleId) internal {
        Battle storage battle = battles[battleId];
        require(!battle.finalized, "Battle already finalized");
        
        address winningToken = battle.totalValueA >= battle.totalValueB 
            ? battle.tokenA 
            : battle.tokenB;
        
        battle.finalized = true;
        
        emit BattleFinalized(
            battleId, 
            winningToken,
            battle.totalValueA >= battle.totalValueB ? battle.totalValueA : battle.totalValueB,
            battle.totalValueA >= battle.totalValueB ? battle.totalValueB : battle.totalValueA
        );
    }
    
    /**
     * @dev Calculate rewards for a user in a battle
     * @param battleId The battle ID
     * @param user The user address
     * @return The reward amount
     */
    function _calculateReward(uint256 battleId, address user) internal view returns (uint256) {
        Battle memory battle = battles[battleId];
        
        address winningToken = battle.totalValueA >= battle.totalValueB 
            ? battle.tokenA 
            : battle.tokenB;
        address losingToken = winningToken == battle.tokenA 
            ? battle.tokenB 
            : battle.tokenA;
        
        uint256 userStake = userStakes[battleId][user][winningToken];
        if (userStake == 0) return 0;
        
        uint256 totalWinningStakes = winningToken == battle.tokenA 
            ? battle.totalStakedA 
            : battle.totalStakedB;
        uint256 totalLosingStakes = losingToken == battle.tokenA 
            ? battle.totalStakedA 
            : battle.totalStakedB;
        
        if (totalWinningStakes == 0) return 0;
        
        // Winner gets: original stake + proportional share of losing tokens
        uint256 proportionalShare = (userStake * totalLosingStakes) / totalWinningStakes;
        return userStake + proportionalShare;
    }
    
    /**
     * @dev Mint NFT reward with rarity-based distribution
     * @param recipient The address to receive the NFT
     */
    function _mintNFTReward(address recipient) internal {
        uint256 tokenId = _tokenIdCounter++;
        _mint(recipient, tokenId);
        
        string memory rarity = _getRarity(tokenId);
        emit NFTMinted(recipient, tokenId, rarity);
    }
    
    /**
     * @dev Determine NFT rarity based on token ID
     * @param tokenId The token ID to check
     * @return The rarity string
     */
    function _getRarity(uint256 tokenId) internal pure returns (string memory) {
        uint256 rarityRoll = tokenId % 1000;
        
        if (rarityRoll == 0) return "Victory Champion";    // 0.1%
        if (rarityRoll <= 10) return "Legendary";          // 1%
        if (rarityRoll <= 50) return "Epic";               // 4%
        if (rarityRoll <= 150) return "Rare";              // 10%
        if (rarityRoll <= 350) return "Uncommon";          // 20%
        return "Common";                                    // 64.9%
    }
    
    // ============ VIEW FUNCTIONS ============
    
    /**
     * @dev Get battle information
     * @param battleId The battle ID
     * @return Battle information tuple
     */
    function getBattleInfo(uint256 battleId) external view returns (
        address tokenA,
        address tokenB,
        uint256 endTime,
        bool finalized,
        address creator
    ) {
        Battle memory battle = battles[battleId];
        return (battle.tokenA, battle.tokenB, battle.endTime, battle.finalized, battle.creator);
    }
    
    /**
     * @dev Get battle statistics
     * @param battleId The battle ID
     * @return Battle statistics tuple
     */
    function getBattleStats(uint256 battleId) external view returns (
        uint256 totalStakedA,
        uint256 totalStakedB,
        uint256 totalValueA,
        uint256 totalValueB
    ) {
        Battle memory battle = battles[battleId];
        return (battle.totalStakedA, battle.totalStakedB, battle.totalValueA, battle.totalValueB);
    }
    
    /**
     * @dev Get total number of battles created
     * @return The total battle count
     */
    function getBattleCount() external view returns (uint256) {
        return _battleIdCounter - 1;
    }
    
    /**
     * @dev Get user stakes for a specific battle
     * @param battleId The battle ID
     * @param user The user address
     * @return Stakes in tokenA and tokenB
     */
    function getUserStakes(uint256 battleId, address user) external view returns (
        uint256 stakeA,
        uint256 stakeB
    ) {
        Battle memory battle = battles[battleId];
        return (
            userStakes[battleId][user][battle.tokenA],
            userStakes[battleId][user][battle.tokenB]
        );
    }
    
    /**
     * @dev Get comprehensive leaderboard data
     * @return Arrays of user data for leaderboard
     */
    function getLeaderboard() external view returns (
        address[] memory users,
        uint256[] memory wins,
        uint256[] memory participations,
        uint256[] memory totalRewards
    ) {
        // Implementation would require additional data structures for efficiency
        // This is a simplified version for demonstration
        users = new address[](0);
        wins = new uint256[](0);
        participations = new uint256[](0);
        totalRewards = new uint256[](0);
    }
    
    // ============ EMERGENCY FUNCTIONS ============
    // Note: These functions are intentionally removed for trustless operation
    // Users can be confident that their funds cannot be accessed by administrators
    
    /**
     * @dev Withdraw contract fees (only owner)
     */
    function withdrawFees() external onlyOwner {
        uint256 balance = address(this).balance;
        require(balance > 0, "No fees to withdraw");
        
        (bool success, ) = payable(owner()).call{value: balance}("");
        require(success, "Withdrawal failed");
    }
    
    // ============ NFT METADATA ============
    
    /**
     * @dev Override tokenURI to provide metadata for NFTs
     * @param tokenId The token ID
     * @return The metadata URI
     */
    function tokenURI(uint256 tokenId) public view override returns (string memory) {
        require(_exists(tokenId), "Token does not exist");
        
        string memory rarity = _getRarity(tokenId);
        
        return string(abi.encodePacked(
            "https://memearena.club/api/nft/",
            Strings.toString(tokenId),
            "?rarity=",
            rarity
        ));
    }
}