const { expect } = require("chai");
const { ethers } = require("hardhat");

describe("Passport Finance Contract", function() {
    let owner;
    let customer;
    let nftFactory;

    beforeEach(async function() {
        const _nft = await ethers.getContractFactory("YCBShareYield");
        [owner, customer] = await ethers.getSigners();
        nftFactory = await _nft.deploy(owner.address);
    })

    it("everyone can mint", async function() {
    	expect(await nftFactory.connect(customer).safeMint(customer.address)).to.not.be.reverted;
    });
})