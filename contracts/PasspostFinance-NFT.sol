// SPDX-License-Identifier: MIT
pragma solidity 0.8.22;

import "@openzeppelin/contracts/token/ERC721/ERC721.sol";
import "@openzeppelin/contracts/token/ERC721/extensions/ERC721Pausable.sol";
import "@openzeppelin/contracts/access/Ownable.sol";
import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/token/ERC721/IERC721Receiver.sol";
import "./PassportSVGGen.sol";

contract YCBPassportFinance is
    ERC721,
    ERC721Pausable,
    Ownable
{
    IERC20 public sToken;
    uint256 private _nextTokenId;

    mapping(uint256 => uint256) public stakes;
    mapping(uint256 => uint256) public lastRewardBlock;
    mapping(uint256 => uint256) public pendingRewardStakes;
    uint256 private rewardRate = 0.05 ether;
    uint256 private reductionFactor = 1;
    uint256 private blockFreqRate = 20;
    uint256 private quantityRate = 100;

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
        address claimant,
        address contractAddress
    );
    event TokensFlushed(
        address indexed to,
        address indexed token,
        uint256 amount,
        address contractAddress
    );

    constructor(address initialOwner, address _sToken)
        ERC721("YCB Passport Finance", "YCBFinance")
        Ownable(initialOwner)
    {
        sToken = IERC20(_sToken);
        reductionFactor = 1;
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

    function stakeTokens(uint256 tokenId, uint256 amount) public whenNotPaused {
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

        delete stakes[tokenId];

        claimRewards(tokenId);

        sToken.transfer(msg.sender, totalAmount);
        emit TokensUnstaked(tokenId, totalAmount, msg.sender, address(this));
    }

    function claimRewards(uint256 tokenId) public {
        _requireOwned(tokenId);
        uint256 rewards = pendingRewards(tokenId);
        if (rewards > 0) {
            lastRewardBlock[tokenId] = block.number;
            delete pendingRewardStakes[tokenId];
            sToken.transfer(msg.sender, rewards);
            emit RewardsClaimed(tokenId, rewards, msg.sender, address(this));
        }
    }

    function pendingRewards(uint256 tokenId) public view returns (uint256) {
        uint256 _currentStakedAmount = stakes[tokenId];
        uint256 _blocksSinceLastReward = block.number -
            lastRewardBlock[tokenId];
        uint256 _pendingReward = 0;

        if (_blocksSinceLastReward >= blockFreqRate) {
            uint256 _rewardCycles = _blocksSinceLastReward / blockFreqRate;
            _pendingReward =
                (((_currentStakedAmount * rewardRate) / reductionFactor) *
                    _rewardCycles) /
                quantityRate +
                pendingRewardStakes[tokenId];
        }

        return _pendingReward;
    }

    function safeMint(address to) public whenNotPaused {
        uint256 tokenId = _nextTokenId++;
        _safeMint(to, tokenId);
    }

    function flushStakeToken(address to, address erc20Address)
        public
        onlyOwner
    {
        IERC20 token = IERC20(erc20Address);
        uint256 contractBalance = token.balanceOf(address(this));

        require(contractBalance > 0, "No tokens to flush");
        bool sent = token.transfer(to, contractBalance);
        require(sent, "Token transfer failed");

        emit TokensFlushed(to, erc20Address, contractBalance, address(this));
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
