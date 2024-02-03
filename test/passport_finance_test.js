const { expect } = require("chai");
const { ethers } = require("hardhat");
const { parseUnits, parseEther, formatEther } = require("ethers");

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

    describe("updateReduction", function () {
        it("Should allow the owner to update reduction factor and emit event", async function () {
            const tx = await nftFactory.connect(owner).updateReduction(100);
            const receipt = await tx.wait();
            const event = receipt.logs?.find(e => e.fragment.name === 'ReductionFactorUpdated');

            expect(event.args[0]).to.equal(100);
            expect(event.args[1]).to.equal(await nftFactory.getAddress());
        });

        it("Should fail if non-owner tries to update reduction factor", async function () {
            await expect(nftFactory.connect(customer).updateReduction(100)).to.be.reverted;
        });
    });

    describe("updateQuantityRate", function () {
        it("Should allow the owner to update quantity rate factor and emit event", async function () {
            const tx = await nftFactory.connect(owner).updateQuantityRate(100);
            const receipt = await tx.wait();
            const event = receipt.logs?.find(e => e.fragment.name === 'QuantityRateUpdated');

            expect(event.args[0]).to.equal(100);
            expect(event.args[1]).to.equal(await nftFactory.getAddress());
        });

        it("Should fail if non-owner tries to update quantity factor", async function () {
            await expect(nftFactory.connect(customer).updateQuantityRate(100)).to.be.reverted;
        });
    });

    describe("updateRewardRate", function () {
        it("Should allow the owner to update reward rate factor and emit event", async function () {
            const tx = await nftFactory.connect(owner).updateRewardRate(parseEther("0.1"));
            const receipt = await tx.wait();
            const event = receipt.logs?.find(e => e.fragment.name === 'RewardRateUpdated');

            expect(event.args[0]).to.equal(parseEther("0.1"));
            expect(event.args[1]).to.equal(await nftFactory.getAddress());
        });

        it("Should fail if non-owner tries to update reward rate factor", async function () {
            await expect(nftFactory.connect(customer).updateRewardRate(parseEther("0.1"))).to.be.reverted;
        });
    });

    describe("updateBlockFreqRate", function () {
        it("Should allow the owner to update block freq rate factor and emit event", async function () {
            const tx = await nftFactory.connect(owner).updateBlockFreqRate(10);
            const receipt = await tx.wait();
            const event = receipt.logs?.find(e => e.fragment.name === 'BlockFreqRateUpdated');

            expect(event.args[0]).to.equal(10);
            expect(event.args[1]).to.equal(await nftFactory.getAddress());
        });

        it("Should fail if non-owner tries to update block req rate factor", async function () {
            await expect(nftFactory.connect(customer).updateBlockFreqRate(10)).to.be.reverted;
        });
    });

    describe("flushStakeToken", function () {
        it("Should allow the owner to flush stake tokens and emit event", async function () {
            await mockErc20.mint(nftFactory.getAddress(), parseUnits("1000", 18));
            const initialBalance = await mockErc20.balanceOf(owner.address);
            const contractBalance = await mockErc20.balanceOf(nftFactory.getAddress());

            const tx = await nftFactory.flushStakeToken(owner.address, mockErc20.getAddress());
            const receipt = await tx.wait();
            const event = receipt.logs?.find(e => e.fragment?.name === 'TokensFlushed');

            const finalBalance = await mockErc20.balanceOf(owner.address);

            expect(event).not.to.be.undefined;
            expect(event.args[0]).to.equal(owner.address);
            expect(event.args[1]).to.equal(await mockErc20.getAddress());
            expect(event.args[2]).to.equal(contractBalance);

            expect(finalBalance - initialBalance).to.equal(contractBalance);
        });

        it("Should fail if non-owner tries to flush stake tokens", async function () {
            await expect(nftFactory.connect(customer).flushStakeToken(customer.address, mockErc20.getAddress())).to.be.reverted;
        });

        it("Should fail if there are no tokens to flush", async function () {
            await expect(nftFactory.flushStakeToken(customer.address, mockErc20.getAddress())).to.be.revertedWith("No tokens to flush");
        });
    });

    describe("pendingRewards", function () {
        it("Should correctly calculate pending rewards", async function () {
            await mockErc20.mint(nftFactory.getAddress(), parseUnits("100000", 18));
            // Initialize contract state
            let blockFreqRate = 20;
            let quantityRate = parseEther("100");
            let rewardRate = parseEther("0.05");
            let reductionFactor = 1;

            await nftFactory.updateBlockFreqRate(blockFreqRate);
            await nftFactory.updateQuantityRate(quantityRate);
            await nftFactory.updateRewardRate(rewardRate);
            await nftFactory.updateReduction(reductionFactor);

            const tokenId = 0;
            const stakedAmount = parseEther("0.1");
            const currentBlockNumber = await ethers.provider.getBlockNumber();

            await nftFactory.connect(customer).safeMint(customer.address);
            await mockErc20.connect(customer).approve(nftFactory.getAddress(), parseEther("100"));

            await nftFactory.connect(customer).stakeTokens(tokenId, stakedAmount);

            const _tStakeAoumnt = await nftFactory.stakes(tokenId);

            const blocksToAdvance = blockFreqRate + 20; 
            for (let i = 0; i < blocksToAdvance; i++) {
                await ethers.provider.send('evm_mine', []); 
            }

            const newBlockNumber = await ethers.provider.getBlockNumber();
            const blocksSinceLastReward = newBlockNumber - currentBlockNumber;
            const rewardCycles = Math.floor(blocksSinceLastReward / blockFreqRate);
            const expectedReward = parseInt(stakedAmount) * parseInt(rewardRate) / reductionFactor * rewardCycles / parseInt(quantityRate);
            const pendingReward = await nftFactory.pendingRewards(tokenId);
            
            expect(pendingReward).to.equal(BigInt(expectedReward));
        });
    });

})