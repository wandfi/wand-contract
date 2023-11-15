import _ from 'lodash';
import { ethers } from 'hardhat';
import { expect } from 'chai';
import { loadFixture } from '@nomicfoundation/hardhat-network-helpers';
import { maxContractSize, nativeTokenAddress, deployContractsFixture } from './utils';
import { 
  Vault__factory,
  AssetX__factory,
} from '../typechain';

const { provider, BigNumber } = ethers;

describe('Wand Protocol', () => {

  it('X Token Works', async () => {

    const {
      Alice, Bob, Caro, Ivy, ethPriceFeed,
      wandProtocol, settings, vaultFactory
    } = await loadFixture(deployContractsFixture);

    // Create $ETHx token
    const AssetXFactory = await ethers.getContractFactory('AssetX');
    expect(AssetXFactory.bytecode.length / 2).lessThan(maxContractSize);
    const ETHx = await AssetXFactory.deploy(wandProtocol.address, "ETHx Token", "ETHx");
    const ethxToken = AssetX__factory.connect(ETHx.address, provider);

    // Create ETH asset pool
    const ethAddress = nativeTokenAddress;
    await expect(wandProtocol.connect(Alice).addVault(ethAddress, ethPriceFeed.address, ethxToken.address,
      [ethers.utils.formatBytes32String("Y"), ethers.utils.formatBytes32String("AART"), ethers.utils.formatBytes32String("AARS"), ethers.utils.formatBytes32String("AARC"), ethers.utils.formatBytes32String("C1"), ethers.utils.formatBytes32String("C2")],
      [
        BigNumber.from(10).pow(await settings.decimals()).mul(365).div(10000), BigNumber.from(10).pow(await settings.decimals()).mul(200).div(100),
        BigNumber.from(10).pow(await settings.decimals()).mul(150).div(100), BigNumber.from(10).pow(await settings.decimals()).mul(110).div(100),
        0, 0
      ])
    ).not.to.be.reverted;
    const ethPoolAddress = await vaultFactory.getVaultAddress(ethAddress);
    await expect(ethxToken.connect(Bob).setAssetPool(ethPoolAddress)).to.be.rejectedWith(/Ownable: caller is not the owner/);
    await expect(ethxToken.connect(Alice).setAssetPool(ethPoolAddress)).not.to.be.reverted;
    await expect(ethxToken.connect(Alice).setAssetPool(ethPoolAddress)).to.be.rejectedWith(/Vault already set/);
    const ethPool = Vault__factory.connect(ethPoolAddress, provider);

    // Set ETH price to $2000, Alice deposit 100 ETH to mint 100 $ETHx, and 1 ETH to mint 2000 $USB
    let ethPrice = BigNumber.from(2000).mul(BigNumber.from(10).pow(await ethPriceFeed.decimals()));
    await expect(ethPriceFeed.connect(Alice).mockPrice(ethPrice)).not.to.be.reverted;
    await expect(ethPool.connect(Alice).mintXTokens(ethers.utils.parseEther("100"), {value: ethers.utils.parseEther("100")})).not.to.be.rejected;
    await expect(ethPool.connect(Alice).mintUSB(ethers.utils.parseEther("1"), {value: ethers.utils.parseEther("1")})).not.to.be.rejected;
    // await dumpAssetPoolState(ethPool);

    // $ETHx could only be minted or burned by the asset pool, not even the owner
    await expect(ethxToken.connect(Alice).mint(Alice.address, 100)).to.be.revertedWith(/Caller is not Vault/);

    // By default, fee is enabled for $ETHx transfer. Default value is 0.08%
    // Alice transfer 10 $ETHx to Bob, Bob receives 9.992 $ETHx
    let fee = BigNumber.from(10).pow(await ethxToken.feeDecimals()).mul(8).div(10000);
    let transferAmount = ethers.utils.parseUnits("10", await ethxToken.decimals());
    let netAmount = ethers.utils.parseUnits("9.992", await ethxToken.decimals());
    let feeAmount = ethers.utils.parseUnits("0.008", await ethxToken.decimals());
    expect(await ethxToken.fee()).to.equal(BigNumber.from(10).pow(await ethxToken.feeDecimals()).mul(8).div(10000));
    await expect(ethxToken.connect(Alice).transfer(Bob.address, transferAmount))
      .to.emit(ethxToken, 'Transfer').withArgs(Alice.address, Bob.address, netAmount)
      .to.emit(ethxToken, 'Transfer').withArgs(Alice.address, await settings.treasury(), feeAmount)
      .to.emit(ethxToken, 'TransferFeeCollected').withArgs(Alice.address, await settings.treasury(), feeAmount);
    expect(await ethxToken.balanceOf(Bob.address)).to.equal(netAmount);

    // transferFrom, fee is also charged
    await expect(ethxToken.connect(Alice).approve(Caro.address, transferAmount))
      .to.emit(ethxToken, 'Approval').withArgs(Alice.address, Caro.address, transferAmount);
    await expect(ethxToken.connect(Caro).transferFrom(Alice.address, Bob.address, transferAmount))
      .to.emit(ethxToken, 'Transfer').withArgs(Alice.address, Bob.address, netAmount)
      .to.emit(ethxToken, 'Transfer').withArgs(Alice.address, await settings.treasury(), feeAmount)
      .to.emit(ethxToken, 'TransferFeeCollected').withArgs(Alice.address, await settings.treasury(), feeAmount);
    expect(await ethxToken.balanceOf(Bob.address)).to.equal(netAmount.mul(2));

    // Add Bob to whitelist, no fee is charged
    await expect(ethxToken.connect(Bob).setWhitelistAddress(Bob.address, true)).to.be.revertedWith(/Ownable: caller is not the owner/);
    await expect(ethxToken.connect(Alice).setWhitelistAddress(Bob.address, true))
      .to.emit(ethxToken, 'UpdateWhitelistAddress').withArgs(Bob.address, true);
    await expect(ethxToken.connect(Alice).transfer(Bob.address, transferAmount))
      .to.emit(ethxToken, 'Transfer').withArgs(Alice.address, Bob.address, transferAmount);
    await expect(ethxToken.connect(Bob).transfer(Alice.address, transferAmount))
      .to.emit(ethxToken, 'Transfer').withArgs(Bob.address, Alice.address, transferAmount);

    await expect(ethxToken.connect(Bob).approve(Caro.address, transferAmount))
      .to.emit(ethxToken, 'Approval').withArgs(Bob.address, Caro.address, transferAmount);
    await expect(ethxToken.connect(Caro).transferFrom(Bob.address, Alice.address, transferAmount))
      .to.emit(ethxToken, 'Transfer').withArgs(Bob.address, Alice.address, transferAmount);

    // Update fee to 10%
    fee = BigNumber.from(10).pow(await settings.decimals()).mul(10).div(100);
    await expect(ethxToken.connect(Bob).setFee(fee)).to.be.revertedWith(/Ownable: caller is not the owner/);
    await expect(ethxToken.connect(Alice).setFee(fee))
      .to.emit(ethxToken, 'UpdatedFee').withArgs(BigNumber.from(10).pow(await ethxToken.feeDecimals()).mul(8).div(10000), fee);

    // Remove Bob from whitelist, fee is charged again
    await expect(ethxToken.connect(Alice).setWhitelistAddress(Bob.address, false))
      .to.emit(ethxToken, 'UpdateWhitelistAddress').withArgs(Bob.address, false);
    await expect(ethxToken.connect(Alice).setWhitelistAddress(Bob.address, false)).to.be.revertedWith(/Address not whitelisted/);

    transferAmount = ethers.utils.parseUnits("10", await ethxToken.decimals());
    netAmount = ethers.utils.parseUnits("9", await ethxToken.decimals());
    feeAmount = ethers.utils.parseUnits("1", await ethxToken.decimals());
    await expect(ethxToken.connect(Alice).transfer(Bob.address, transferAmount))
      .to.emit(ethxToken, 'Transfer').withArgs(Alice.address, Bob.address, netAmount)
      .to.emit(ethxToken, 'Transfer').withArgs(Alice.address, await settings.treasury(), feeAmount)
      .to.emit(ethxToken, 'TransferFeeCollected').withArgs(Alice.address, await settings.treasury(), feeAmount);

    // Set fee to minimum 0%
    fee = BigNumber.from(0);
    await expect(ethxToken.connect(Alice).setFee(fee)).not.to.be.reverted;
    transferAmount = ethers.utils.parseUnits("10", await ethxToken.decimals());
    await expect(ethxToken.connect(Alice).transfer(Bob.address, transferAmount))
      .to.emit(ethxToken, 'Transfer').withArgs(Alice.address, Bob.address, transferAmount);
    
    // Set fee to maximum 100%
    fee = BigNumber.from(10).pow(await ethxToken.feeDecimals());
    await expect(ethxToken.connect(Alice).setFee(fee)).not.to.be.reverted;
    transferAmount = ethers.utils.parseUnits("10", await ethxToken.decimals());
    feeAmount = transferAmount;
    await expect(ethxToken.connect(Alice).transfer(Bob.address, transferAmount))
      .to.emit(ethxToken, 'Transfer').withArgs(Alice.address, await settings.treasury(), feeAmount)
      .to.emit(ethxToken, 'TransferFeeCollected').withArgs(Alice.address, await settings.treasury(), feeAmount);

    // Restore fee to 10%
    fee = BigNumber.from(10).pow(await settings.decimals()).mul(10).div(100);
    await expect(ethxToken.connect(Alice).setFee(fee)).not.to.be.reverted;

    // OK, what if treasury account transfer $ETHx to Bob? Will fee be charged?
    expect(await settings.treasury()).to.equal(Ivy.address);
    expect(await ethxToken.isAddressWhitelisted(Ivy.address)).to.equal(false);
    transferAmount = ethers.utils.parseUnits("10", await ethxToken.decimals());
    feeAmount = ethers.utils.parseUnits("1", await ethxToken.decimals());
    await expect(ethxToken.connect(Alice).transfer(Ivy.address, transferAmount))
      .to.emit(ethxToken, 'Transfer').withArgs(Alice.address, Ivy.address, transferAmount.sub(feeAmount))
      .to.emit(ethxToken, 'Transfer').withArgs(Alice.address, Ivy.address, feeAmount)
      .to.emit(ethxToken, 'TransferFeeCollected').withArgs(Alice.address, Ivy.address, feeAmount);
    
    await expect(ethxToken.connect(Ivy).transfer(Alice.address, transferAmount))
      .to.emit(ethxToken, 'Transfer').withArgs(Ivy.address, Alice.address, transferAmount.sub(feeAmount))
      .to.emit(ethxToken, 'Transfer').withArgs(Ivy.address, Ivy.address, feeAmount)
      .to.emit(ethxToken, 'TransferFeeCollected').withArgs(Ivy.address, Ivy.address, feeAmount);

  });

});