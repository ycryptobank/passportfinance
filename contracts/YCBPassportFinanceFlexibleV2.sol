// SPDX-License-Identifier: MIT
pragma solidity 0.8.28;

import "@openzeppelin/contracts/token/ERC721/ERC721.sol";
import "@openzeppelin/contracts/token/ERC721/extensions/ERC721Pausable.sol";
import "@openzeppelin/contracts/access/Ownable.sol";
import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/token/ERC721/IERC721Receiver.sol";
import "@openzeppelin/contracts/utils/ReentrancyGuard.sol";

contract YCBPassportFinanceFlexibleV2 is
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
    uint256 private maxElligibleTime = 28800;
    uint256 private initialBalance = 0;
    uint256 private totalClaimedBalance = 0;
    uint256 private maxRewardPercentage = 50;
    bool public isTerminated = false;
    bool public isStarted = false;

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
        uint256 totalClaimedContract,
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

    constructor(address _initialOwner, address _sToken)
        ERC721("YCB Passport V2", "Campaign Yield")
        Ownable(_initialOwner)
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

    function startCampaign() public onlyOwner {
        isStarted = true;
    }

    function pause() public onlyOwner {
        _pause();
    }

    function unpause() public onlyOwner {
        _unpause();
    }

    function updateMaxRewardPercentage(uint256 _maxRewardPercentage)
        public
        onlyOwner
    {
        maxRewardPercentage = _maxRewardPercentage;
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
        whenCampaignStarted
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

    function unstakeTokens(uint256 tokenId) public nonReentrant {
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

        emit TokensUnstaked(
            tokenId,
            totalAmount,
            totalClaimedBalance,
            msg.sender,
            address(this)
        );
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
            uint256 maxFactor = (efficientFactor * maxRewardPercentage) / 100;
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

            if (_pendingReward == 0) {
                _pendingReward = pendingRewardStakes[tokenId];
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
            uint256 maxFactor = (efficientFactor * maxRewardPercentage) / 100;

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
        if (_pendingReward == 0) {
            _pendingReward = pendingRewardStakes[tokenId];
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
            initialBalance = 0;
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
        uint256 maxFactor = ((initialBalance - totalClaimedBalance) *
            maxRewardPercentage) / 100;
        uint256 userReward = pendingRewards(tokenId);
        return userReward >= maxFactor;
    }

    function userMintCount() public view returns (uint256) {
        return userMinted[msg.sender];
    }

    modifier whenCampaignStarted() {
        require(isStarted, "The campaign has not started yet");
        _;
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
        return constructURI(tokenId, address(this), stakes[tokenId]);
    }

    function constructURI(
        uint256 _tokenId,
        address _contract,
        uint256 _stakeQuantity
    ) internal pure returns (string memory) {
        string memory image = encode(
            bytes(
                generateSVG(
                    uintToString(_tokenId),
                    addressToString(_contract),
                    uintToString(_stakeQuantity)
                )
            )
        );
        return
            string(
                abi.encodePacked(
                    "data:application/json;base64,",
                    encode(
                        bytes(
                            abi.encodePacked(
                                '{"name":"',
                                "Passport Finance",
                                '", "description":"',
                                "Flexible Yield",
                                '", "image": "',
                                "data:image/svg+xml;base64,",
                                image,
                                '"}'
                            )
                        )
                    )
                )
            );
    }

    function generateSVG(
        string memory _tokenId,
        string memory _contract,
        string memory _stakeQuantity
    ) internal pure returns (string memory svg) {
        return
            string(
                abi.encodePacked(
                    '<svg xmlns="http://www.w3.org/2000/svg" xmlns:xlink="http://www.w3.org/1999/xlink" width="900" zoomAndPan="magnify" viewBox="0 0 675 1199.999942" height="1600" preserveAspectRatio="xMidYMid meet" version="1.0"> <defs> <g /> </defs>',
                    '<rect x="-67.5" width="810" fill="#ffffff" y="-119.999994" height="1439.999931" fill-opacity="1" />',
                    '<rect x="-67.5" width="810" fill="#360751" y="-119.999994" height="1439.999931" fill-opacity="1" />',
                    '<text x="320" y="250" fill="#d4ade6" font-size="100" text-anchor="end">YCB</text>',
                    '<text x="470" y="350" fill="#ffffff" font-size="50" text-anchor="end">Passport Finance</text>',
                    '<text x="450" y="500" fill="#f2f2f2" font-size="20" text-anchor="end">Token ID</text>',
                    '<text x="450" y="520" fill="#d4ade6" font-size="20" text-anchor="end">',
                    _tokenId,
                    "</text>",
                    '<text x="450" y="540" fill="#f2f2f2" font-size="20" text-anchor="end">Pass Contract</text>',
                    '<text x="450" y="560" fill="green" font-size="20" text-anchor="end">',
                    _contract,
                    "</text>",
                    '<text x="450" y="580" fill="#f2f2f2" font-size="20" text-anchor="end">Stake in Wei</text>',
                    '<text x="450" y="600" fill="yellow" font-size="20" text-anchor="end">',
                    _stakeQuantity,
                    "</text>",
                    "</svg>"
                )
            );
    }

    function uintToString(uint256 _value)
        internal
        pure
        returns (string memory)
    {
        // Handle zero case explicitly to simplify loop
        if (_value == 0) {
            return "0";
        }

        // Calculate the length of the integer
        uint256 temp = _value;
        uint256 digits;
        while (temp != 0) {
            digits++;
            temp /= 10;
        }

        // Allocate memory for the string
        bytes memory buffer = new bytes(digits);

        // Convert integer to string by populating buffer from the end
        while (_value != 0) {
            digits -= 1;
            buffer[digits] = bytes1(uint8(48 + (_value % 10)));
            _value /= 10;
        }

        return string(buffer);
    }

    function addressToString(address _addr)
        internal
        pure
        returns (string memory)
    {
        bytes32 value = bytes32(uint256(uint160(_addr)));
        bytes memory alphabet = "0123456789abcdef";
        bytes memory str = new bytes(42);
        str[0] = "0";
        str[1] = "x";
        for (uint256 i = 0; i < 20; i++) {
            str[2 + i * 2] = alphabet[uint8(value[i + 12] >> 4)];
            str[3 + i * 2] = alphabet[uint8(value[i + 12] & 0x0f)];
        }
        return string(str);
    }

    //base64
    string internal constant TABLE_ENCODE =
        "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789+/";
    bytes internal constant TABLE_DECODE =
        hex"0000000000000000000000000000000000000000000000000000000000000000"
        hex"00000000000000000000003e0000003f3435363738393a3b3c3d000000000000"
        hex"00000102030405060708090a0b0c0d0e0f101112131415161718190000000000"
        hex"001a1b1c1d1e1f202122232425262728292a2b2c2d2e2f303132330000000000";

    function encode(bytes memory data) internal pure returns (string memory) {
        if (data.length == 0) return "";

        // load the table into memory
        string memory table = TABLE_ENCODE;

        // multiply by 4/3 rounded up
        uint256 encodedLen = 4 * ((data.length + 2) / 3);

        // add some extra buffer at the end required for the writing
        string memory result = new string(encodedLen + 32);

        assembly {
            // set the actual output length
            mstore(result, encodedLen)

            // prepare the lookup table
            let tablePtr := add(table, 1)

            // input ptr
            let dataPtr := data
            let endPtr := add(dataPtr, mload(data))

            // result ptr, jump over length
            let resultPtr := add(result, 32)

            // run over the input, 3 bytes at a time
            for {

            } lt(dataPtr, endPtr) {

            } {
                // read 3 bytes
                dataPtr := add(dataPtr, 3)
                let input := mload(dataPtr)

                // write 4 characters
                mstore8(
                    resultPtr,
                    mload(add(tablePtr, and(shr(18, input), 0x3F)))
                )
                resultPtr := add(resultPtr, 1)
                mstore8(
                    resultPtr,
                    mload(add(tablePtr, and(shr(12, input), 0x3F)))
                )
                resultPtr := add(resultPtr, 1)
                mstore8(
                    resultPtr,
                    mload(add(tablePtr, and(shr(6, input), 0x3F)))
                )
                resultPtr := add(resultPtr, 1)
                mstore8(resultPtr, mload(add(tablePtr, and(input, 0x3F))))
                resultPtr := add(resultPtr, 1)
            }

            // padding with '='
            switch mod(mload(data), 3)
            case 1 {
                mstore(sub(resultPtr, 2), shl(240, 0x3d3d))
            }
            case 2 {
                mstore(sub(resultPtr, 1), shl(248, 0x3d))
            }
        }

        return result;
    }

    function decode(string memory _data) internal pure returns (bytes memory) {
        bytes memory data = bytes(_data);

        if (data.length == 0) return new bytes(0);
        require(data.length % 4 == 0, "invalid base64 decoder input");

        // load the table into memory
        bytes memory table = TABLE_DECODE;

        // every 4 characters represent 3 bytes
        uint256 decodedLen = (data.length / 4) * 3;

        // add some extra buffer at the end required for the writing
        bytes memory result = new bytes(decodedLen + 32);

        assembly {
            // padding with '='
            let lastBytes := mload(add(data, mload(data)))
            if eq(and(lastBytes, 0xFF), 0x3d) {
                decodedLen := sub(decodedLen, 1)
                if eq(and(lastBytes, 0xFFFF), 0x3d3d) {
                    decodedLen := sub(decodedLen, 1)
                }
            }

            // set the actual output length
            mstore(result, decodedLen)

            // prepare the lookup table
            let tablePtr := add(table, 1)

            // input ptr
            let dataPtr := data
            let endPtr := add(dataPtr, mload(data))

            // result ptr, jump over length
            let resultPtr := add(result, 32)

            // run over the input, 4 characters at a time
            for {

            } lt(dataPtr, endPtr) {

            } {
                // read 4 characters
                dataPtr := add(dataPtr, 4)
                let input := mload(dataPtr)

                // write 3 bytes
                let output := add(
                    add(
                        shl(
                            18,
                            and(
                                mload(add(tablePtr, and(shr(24, input), 0xFF))),
                                0xFF
                            )
                        ),
                        shl(
                            12,
                            and(
                                mload(add(tablePtr, and(shr(16, input), 0xFF))),
                                0xFF
                            )
                        )
                    ),
                    add(
                        shl(
                            6,
                            and(
                                mload(add(tablePtr, and(shr(8, input), 0xFF))),
                                0xFF
                            )
                        ),
                        and(mload(add(tablePtr, and(input, 0xFF))), 0xFF)
                    )
                )
                mstore(resultPtr, shl(232, output))
                resultPtr := add(resultPtr, 3)
            }
        }

        return result;
    }
}
