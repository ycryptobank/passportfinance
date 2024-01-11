// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "@openzeppelin/contracts/token/ERC721/ERC721.sol";
import "@openzeppelin/contracts/token/ERC721/extensions/ERC721Pausable.sol";
import "@openzeppelin/contracts/access/Ownable.sol";
import "@openzeppelin/contracts/token/ERC20/IERC20.sol";

contract YCBShareYield is ERC721, ERC721Pausable, Ownable {
    struct Stake {
        uint256 amount;
        uint256 startTime;
    }

    IERC20 public sToken;
    uint256 private _nextTokenId;
    string private constant STATIC_URI = "ipfs://bafybeigluhjtgca3gminf75i47n5sjpdqkf2dajloosdcsyqelaopakyxy";

    mapping(uint256 => Stake[]) public stakes;

    constructor(address initialOwner, address _sToken)
        ERC721("YCBShareYield", "YCBSY")
        Ownable(initialOwner)
    {
        sToken = IERC20(_sToken);
    }

    function pause() public onlyOwner {
        _pause();
    }

    function unpause() public onlyOwner {
        _unpause();
    }

    function stakeTokens(uint256 tokenId, uint256 amount) public whenNotPaused {
        _requireOwned(tokenId);
        sToken.transferFrom(msg.sender, address(this), amount);
        stakes[tokenId].push(Stake(amount, block.timestamp));
    }

    function unstakeTokens(uint256 tokenId) public {
        _requireOwned(tokenId);
        uint256 totalAmount = 0;
        for (uint i = 0; i < stakes[tokenId].length; i++) {
            totalAmount += stakes[tokenId][i].amount;
        }

        delete stakes[tokenId];

        sToken.transfer(msg.sender, totalAmount);
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
        return STATIC_URI;
    }
}