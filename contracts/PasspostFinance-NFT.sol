// SPDX-License-Identifier: MIT
pragma solidity 0.8.22;

import "@openzeppelin/contracts/token/ERC721/ERC721.sol";
import "@openzeppelin/contracts/token/ERC721/extensions/ERC721Pausable.sol";
import "@openzeppelin/contracts/access/Ownable.sol";
import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import './PassportSVGGen.sol';

contract YCBPassportFinance is ERC721, ERC721Pausable, Ownable {

    IERC20 public sToken;
    uint256 private _nextTokenId;

    mapping(uint256 => uint256) public stakes;
    mapping(uint256 => uint256) public lastRewardBlock;
    mapping(uint256 => uint256) public pendingRewardStakes;
    uint256 private rewardRate = 0.05 ether;
    uint256 private reductionFactor;

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

    function setReduction(uint256 _reductionFactor) public onlyOwner {
        reductionFactor = _reductionFactor;
    }

    function stakeTokens(uint256 tokenId, uint256 amount) public whenNotPaused {
        _requireOwned(tokenId);
        sToken.transferFrom(msg.sender, address(this), amount);
        // recalculate pending rewards + stake
        pendingRewardStakes[tokenId] = pendingRewards(tokenId);
        uint256 _currentAmount = stakes[tokenId];
        stakes[tokenId] = _currentAmount + amount;
        lastRewardBlock[tokenId] = block.number;
    }

    function unstakeTokens(uint256 tokenId) public {
        _requireOwned(tokenId);
        uint256 totalAmount = stakes[tokenId];

        delete stakes[tokenId];

        claimRewards(tokenId);

        sToken.transfer(msg.sender, totalAmount);
    }

    function claimRewards(uint256 tokenId) public {
        _requireOwned(tokenId);
        uint256 rewards = pendingRewards(tokenId);
        if (rewards > 0) {
            lastRewardBlock[tokenId] = block.number;
            delete pendingRewardStakes[tokenId];
            sToken.transfer(msg.sender, rewards);
        }
    }

    function pendingRewards(uint256 tokenId) public view returns (uint256) {
        uint256 _currentStakedAmount = stakes[tokenId];
        uint256 _blocksSinceLastReward = block.number - lastRewardBlock[tokenId];
        uint256 _pendingReward = 0;

        if (_blocksSinceLastReward >= 20) {
            uint256 _rewardCycles = _blocksSinceLastReward / 20;
            _pendingReward = (_rewardCycles * _currentStakedAmount / 100) * rewardRate / reductionFactor + pendingRewardStakes[tokenId];
        }
        
        return _pendingReward;
    }

    function safeMint(address to) public whenNotPaused {
        uint256 tokenId = _nextTokenId++;
        _safeMint(to, tokenId);
    }

    // The following functions are overrides required by Solidity.
    function _update(address to, uint256 tokenId, address auth)
        internal
        override(ERC721, ERC721Pausable)
        returns (address)
    {
        return super._update(to, tokenId, auth);
    }

    function tokenURI(uint256 tokenId)
        public
        view
        override(ERC721)
        returns (string memory)
    {
       _requireOwned(tokenId);
        return PassportSVGGen.constructURI(tokenId, lastRewardBlock[tokenId], stakes[tokenId]);
    }
}