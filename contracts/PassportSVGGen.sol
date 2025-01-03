// SPDX-License-Identifier: MIT
pragma solidity 0.8.28;
pragma abicoder v2;

import "base64-sol/base64.sol";

library PassportSVGGen {
    function constructURI(
        uint256 _tokenId,
        address _contract,
        uint256 _stakeQuantity
    ) public pure returns (string memory) {
        string memory image = Base64.encode(
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
                    Base64.encode(
                        bytes(
                            abi.encodePacked(
                                '{"name":"',
                                "YCB - Passport Finance",
                                '", "description":"',
                                "YCB - DeFi Yield",
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
        public
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
}
