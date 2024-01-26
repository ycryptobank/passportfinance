const { expect } = require("chai");
const { ethers } = require("hardhat");
const { parseUnits, parseEther } = require("ethers");

describe("Passport Finance Contract", function () {
    let owner;
    let customer;
    let nftFactory;
    let mockErc20;
    let svgGen;

    beforeEach(async function () {
        const _svggen = await ethers.getContractFactory("PassportSVGGen");
        svgGen = await _svggen.deploy();
        const _address = await svgGen.getAddress();
        const _nft = await ethers.getContractFactory("YCBPassportFinance", {
            libraries: {
                PassportSVGGen: _address,
            },
        });
        const _mockErc20 = await ethers.getContractFactory("MockERC20");
        [owner, customer] = await ethers.getSigners();
        mockErc20 = await _mockErc20.deploy("MockToken", "MTT");
        nftFactory = await _nft.deploy(owner.address, mockErc20.getAddress());

        await mockErc20.mint(customer.address, parseUnits("10000000", 18));
    })

    it("everyone can mint", async function () {
        expect(await nftFactory.connect(customer).safeMint(customer.address)).to.not.be.reverted;
    });

    it("when paused can't mint", async function () {
        await nftFactory.pause();
        await expect(nftFactory.connect(customer).safeMint(customer.address)).to.be.revertedWithCustomError(nftFactory, "EnforcedPause");
        await nftFactory.unpause();
        await expect(nftFactory.connect(customer).safeMint(customer.address)).to.not.be.reverted;
    })

    it("tokenURI should be not reverted", async function () {
        const mintTx = await nftFactory.connect(customer).safeMint(customer.address);

        const _tokenUri = await nftFactory.tokenURI(0);
        expect(_tokenUri).to.not.be.reverted;
    });

    it("Stake token", async function () {
        await nftFactory.connect(customer).safeMint(customer.address);
        await mockErc20.connect(customer).approve(nftFactory.getAddress(), parseEther("1000"));
        await expect(nftFactory.connect(customer).stakeTokens(0, parseEther("1"))).to.not.be.reverted;

        await nftFactory.pause();
        await expect(nftFactory.connect(customer).stakeTokens(0, parseEther("1"))).to.be.reverted;

        await nftFactory.unpause();
        await expect(nftFactory.connect(customer).stakeTokens(0, parseEther("1"))).to.not.be.reverted;
    });

    it("Unstake token", async function () {
        await nftFactory.connect(customer).safeMint(customer.address);
        await mockErc20.connect(customer).approve(nftFactory.getAddress(), parseEther("1000"));
        await expect(nftFactory.connect(customer).stakeTokens(0, parseEther("1"))).to.not.be.reverted;
        await nftFactory.pause();
    });
})