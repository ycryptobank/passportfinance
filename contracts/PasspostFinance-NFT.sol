// SPDX-License-Identifier: MIT
pragma solidity 0.8.22;

import "@openzeppelin/contracts/token/ERC721/ERC721.sol";
import "@openzeppelin/contracts/token/ERC721/extensions/ERC721Pausable.sol";
import "@openzeppelin/contracts/access/Ownable.sol";
import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/token/ERC721/IERC721Receiver.sol";
import "@openzeppelin/contracts/utils/ReentrancyGuard.sol";
import "./PassportSVGGen.sol";

contract YCBPassportFinance is
    ERC721,
    ERC721Pausable,
    Ownable,
    ReentrancyGuard
{
    IERC20 public sToken;
    uint256 private _nextTokenId;

    mapping(uint256 => uint256) public stakes;
    mapping(uint256 => uint256) public lastRewardBlock;
    mapping(uint256 => uint256) public pendingRewardStakes;
    mapping(address => uint256) public userMinted;
    mapping(address => uint256) public totalClaimed;
    uint256 private rewardRate = 0.05 ether;
    uint256 private reductionFactor = 1;
    uint256 private blockFreqRate = 20;
    uint256 private quantityRate = 1000 ether;
    uint256 private maxMint = 5;
    uint256 private terminatedBlock = 0;
    uint256 private maxElligibleTime = 1 days;
    uint256 private initialBalance = 0;
    uint256 private totalClaimedBalance = 0;
    bool public isTerminated = false;

    event TTransfer(
        address indexed from,
        address indexed to,
        uint256 tokenId,
        address contractAddress
    );
    event ReductionFactorUpdated(
        uint256 newReductionFactor,
        address contractAddress
    );
    event RewardRateUpdated(uint256 newRewardRate, address contractAddress);
    event BlockFreqRateUpdated(
        uint256 newBlockFreqRate,
        address contractAddress
    );
    event QuantityRateUpdated(uint256 newQuantityRate, address contractAddress);
    event TokensStaked(
        uint256 tokenId,
        uint256 amount,
        address staker,
        address contractAddress
    );
    event TokensUnstaked(
        uint256 tokenId,
        uint256 amount,
        address unstaker,
        address contractAddress
    );
    event RewardsClaimed(
        uint256 tokenId,
        uint256 rewards,
        uint256 totalClaimedContract,
        address claimant,
        address contractAddress
    );
    event TokensFlushed(
        address indexed to,
        address indexed token,
        uint256 amount,
        address contractAddress
    );
    event MaxMintUpdated(uint256 _maxMint, address _contractAddress);
    event MaxElligibleTime(uint256 _maxElligibleTime, address _contractAddress);
    event BalanceAdd(uint256 _amount, address _contractAddress);

    constructor(address initialOwner, address _sToken)
        ERC721("YCB Passport Finance", "YCBFinance")
        Ownable(initialOwner)
    {
        sToken = IERC20(_sToken);
        reductionFactor = 1;
    }

    function terminate() public onlyOwner {
        // Caution: this will froze the yield forever
        terminatedBlock = block.number;
        isTerminated = true;
        pause();
    }

    function pause() public onlyOwner {
        _pause();
    }

    function unpause() public onlyOwner {
        _unpause();
    }

    function updateReduction(uint256 _reductionFactor) public onlyOwner {
        reductionFactor = _reductionFactor;
        emit ReductionFactorUpdated(_reductionFactor, address(this));
    }

    function updateRewardRate(uint256 _rewardRate) public onlyOwner {
        rewardRate = _rewardRate;
        emit RewardRateUpdated(_rewardRate, address(this));
    }

    function updateBlockFreqRate(uint256 _blockFreqRate) public onlyOwner {
        blockFreqRate = _blockFreqRate;
        emit BlockFreqRateUpdated(_blockFreqRate, address(this));
    }

    function updateQuantityRate(uint256 _quantityRate) public onlyOwner {
        quantityRate = _quantityRate;
        emit QuantityRateUpdated(_quantityRate, address(this));
    }

    function updateMaxMint(uint256 _maxMint) public onlyOwner {
        maxMint = _maxMint;
        emit MaxMintUpdated(_maxMint, address(this));
    }

    function updateMaxElligibleTime(uint256 _maxElligibleTime)
        public
        onlyOwner
    {
        maxElligibleTime = _maxElligibleTime;
        emit MaxElligibleTime(maxElligibleTime, address(this));
    }

    function addBalance(uint256 amount) public onlyOwner {
        sToken.transferFrom(msg.sender, address(this), amount);
        initialBalance += amount;
        emit BalanceAdd(initialBalance, address(this));
    }

    function stakeTokens(uint256 tokenId, uint256 amount)
        public
        whenNotPaused
        nonReentrant
    {
        _requireOwned(tokenId);
        sToken.transferFrom(msg.sender, address(this), amount);
        // recalculate pending rewards + stake
        pendingRewardStakes[tokenId] = pendingRewards(tokenId);
        uint256 _currentAmount = stakes[tokenId];
        stakes[tokenId] = _currentAmount + amount;
        lastRewardBlock[tokenId] = block.number;
        emit TokensStaked(tokenId, amount, msg.sender, address(this));
    }

    function unstakeTokens(uint256 tokenId) public {
        _requireOwned(tokenId);
        uint256 totalAmount = stakes[tokenId];

        // ClaimReward algo
        require(
            isElligibleToClaim(tokenId),
            "Token rewards can only be claimed once per day"
        );
        uint256 rewards;
        if (isTerminated) {
            rewards = pendingFrozenRewards(tokenId);
        } else {
            rewards = pendingRewards(tokenId);
        }

        if (rewards > 0) {
            lastRewardBlock[tokenId] = block.number;
            terminatedBlock = 0;
            delete pendingRewardStakes[tokenId];
            sToken.transfer(msg.sender, rewards);
            totalClaimed[msg.sender] += rewards;
            totalClaimedBalance += rewards;
        }
        // end

        delete stakes[tokenId];

        sToken.transfer(msg.sender, totalAmount);

        emit TokensUnstaked(tokenId, totalAmount, msg.sender, address(this));
    }

    function claimRewards(uint256 tokenId) public nonReentrant {
        _requireOwned(tokenId);
        require(
            isElligibleToClaim(tokenId),
            "Token rewards can only be claimed once per day"
        );
        uint256 rewards;
        if (isTerminated) {
            rewards = pendingFrozenRewards(tokenId);
        } else {
            rewards = pendingRewards(tokenId);
        }

        if (rewards > 0) {
            lastRewardBlock[tokenId] = block.number;
            terminatedBlock = 0;
            delete pendingRewardStakes[tokenId];
            sToken.transfer(msg.sender, rewards);
            totalClaimed[msg.sender] += rewards;
            totalClaimedBalance += rewards;
            emit RewardsClaimed(
                tokenId,
                rewards,
                totalClaimedBalance,
                msg.sender,
                address(this)
            );
        }
    }

    function pendingRewards(uint256 tokenId) public view returns (uint256) {
        if (isTerminated) {
            return pendingFrozenRewards(tokenId);
        } else {
            uint256 _pendingReward = 0;
            uint256 efficientFactor = initialBalance - totalClaimedBalance;
            uint256 maxFactor = (efficientFactor * 50) / 100;
            // to avoid overflow
            if (block.number > lastRewardBlock[tokenId] && initialBalance > 0) {
                uint256 _currentStakedAmount = stakes[tokenId];

                uint256 _blocksSinceLastReward = block.number -
                    lastRewardBlock[tokenId];

                if (_blocksSinceLastReward >= blockFreqRate) {
                    uint256 _rewardCycles = _blocksSinceLastReward /
                        blockFreqRate;
                    _pendingReward =
                        (((_currentStakedAmount * rewardRate) /
                            reductionFactor) * _rewardCycles) /
                        quantityRate +
                        pendingRewardStakes[tokenId];
                }
            }

            if (_pendingReward > 0 && efficientFactor > 0) {
                _pendingReward =
                    (_pendingReward * efficientFactor) /
                    initialBalance;
            }

            if (_pendingReward > maxFactor) {
                _pendingReward = maxFactor;
            }

            return _pendingReward;
        }
    }

    function pendingFrozenRewards(uint256 tokenId)
        internal
        view
        returns (uint256)
    {
        uint256 _pendingReward = 0;
        if (isTerminated && terminatedBlock > 0) {
            uint256 _currentStakedAmount = stakes[tokenId];
            uint256 efficientFactor = initialBalance - totalClaimedBalance;
            uint256 maxFactor = (efficientFactor * 50) / 100;

            uint256 _blocksSinceLastReward = terminatedBlock -
                lastRewardBlock[tokenId];

            if (_blocksSinceLastReward >= blockFreqRate && initialBalance > 0) {
                uint256 _rewardCycles = _blocksSinceLastReward / blockFreqRate;
                _pendingReward =
                    (((_currentStakedAmount * rewardRate) / reductionFactor) *
                        _rewardCycles) /
                    quantityRate +
                    pendingRewardStakes[tokenId];
            }

            if (_pendingReward > 0 && efficientFactor > 0) {
                _pendingReward =
                    (_pendingReward * efficientFactor) /
                    initialBalance;
            }

            if (_pendingReward > maxFactor) {
                _pendingReward = maxFactor;
            }
        }
        return _pendingReward;
    }

    function safeMint(address to) public whenNotPaused nonReentrant {
        require(
            userMinted[to] < maxMint,
            "Address has exceeded the maximum token limit"
        );

        uint256 tokenId = _nextTokenId++;
        _safeMint(to, tokenId);
        userMinted[to]++;
    }

    // dumb mistake when someone sending other erc20 token accidently to refund
    function flushStakeToken(address to, address erc20Address)
        public
        onlyOwner
    {
        IERC20 token = IERC20(erc20Address);
        uint256 contractBalance = token.balanceOf(address(this));
        if (erc20Address == address(sToken)) {
            // To avoid owner flush customer stake token
            contractBalance = initialBalance;
        }
        
        require(contractBalance > 0, "No tokens to flush");
        bool sent = token.transfer(to, contractBalance);
        require(sent, "Token transfer failed");

        emit TokensFlushed(to, erc20Address, contractBalance, address(this));
    }

    function isElligibleToClaim(uint256 tokenId) public view returns (bool) {
        return (lastRewardBlock[tokenId] + maxElligibleTime) < block.number;
    }

    function isMaxReward(uint256 tokenId) public view returns (bool) {
        uint256 maxFactor = ((initialBalance - totalClaimedBalance) * 50) / 100;
        uint256 userReward = pendingRewards(tokenId);
        return userReward >= maxFactor;
    }

    function userMintCount() public view returns (uint256) {
        return userMinted[msg.sender];
    }

    // The following functions are overrides required by Solidity.
    function _update(
        address to,
        uint256 tokenId,
        address auth
    ) internal override(ERC721, ERC721Pausable) returns (address) {
        emit TTransfer(auth, to, tokenId, address(this));
        return super._update(to, tokenId, auth);
    }

    function tokenURI(uint256 tokenId)
        public
        view
        override(ERC721)
        returns (string memory)
    {
        _requireOwned(tokenId);
        return
            PassportSVGGen.constructURI(
                tokenId,
                address(this),
                stakes[tokenId]
            );
    }
}
