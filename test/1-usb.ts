import _ from 'lodash';
import { ethers } from 'hardhat';
import { expect } from 'chai';
import { loadFixture } from '@nomicfoundation/hardhat-network-helpers';
import { deployContractsFixture } from './utils';

import { 
  MockUsb__factory
} from '../typechain';

const { provider } = ethers;

describe('Usb', () => {

  it('Usb works', async () => {

    const { Alice, Bob, Caro, Dave } = await loadFixture(deployContractsFixture);

    const MockUsbFactory = await ethers.getContractFactory('MockUsb');
    const MockUsb = await MockUsbFactory.deploy();
    const usb = MockUsb__factory.connect(MockUsb.address, provider);

    // Alice mint 100 $USB to Bob.
    // Bobs share: 100
    let mintAmount = ethers.utils.parseUnits('100', await usb.decimals());
    // await expect(usb.connect(Bob).mint(Bob.address, mintAmount)).to.be.rejectedWith('Ownable: caller is not the owner');
    await expect(usb.connect(Alice).mint(Bob.address, mintAmount))
      .to.emit(usb, 'Transfer').withArgs(ethers.constants.AddressZero, Bob.address, mintAmount)
      .to.emit(usb, 'TransferShares').withArgs(ethers.constants.AddressZero, Bob.address, mintAmount);
    expect(await usb.sharesOf(Bob.address)).to.equal(ethers.utils.parseUnits('100', await usb.decimals()));
    expect(await usb.balanceOf(Bob.address)).to.equal(ethers.utils.parseUnits('100', await usb.decimals()));

    // Bob transfer 50 $USB to Caro.
    // Bob shares: 50; Caro shares: 50
    let transferAmount = ethers.utils.parseUnits('50', await usb.decimals());
    await expect(usb.connect(Bob).transfer(Caro.address, transferAmount)).not.to.be.rejected;
    expect(await usb.sharesOf(Bob.address)).to.equal(ethers.utils.parseUnits('50', await usb.decimals()));
    expect(await usb.balanceOf(Bob.address)).to.equal(ethers.utils.parseUnits('50', await usb.decimals()));
    expect(await usb.sharesOf(Caro.address)).to.equal(ethers.utils.parseUnits('50', await usb.decimals()));
    expect(await usb.balanceOf(Caro.address)).to.equal(ethers.utils.parseUnits('50', await usb.decimals()));

    // Admin rebase supply from 100 $USB to 200 $USB
    let rebaseAmount = ethers.utils.parseUnits('100', await usb.decimals());
    // await expect(usb.connect(Bob).rebase(rebaseAmount)).to.be.rejectedWith('Ownable: caller is not the owner');
    await expect(usb.connect(Alice).rebase(rebaseAmount))
      .to.emit(usb, 'Rebased').withArgs(rebaseAmount);
    expect(await usb.balanceOf(Bob.address)).to.equal(ethers.utils.parseUnits('100', await usb.decimals()));
    expect(await usb.balanceOf(Caro.address)).to.equal(ethers.utils.parseUnits('100', await usb.decimals()));

    // Admin mint 100 $USB to Dave.
    // Total supply: 300; Bob shares: 50, Caro shares: 50, Dave shares: 50
    mintAmount = ethers.utils.parseUnits('100', await usb.decimals());
    await expect(usb.connect(Alice).mint(Dave.address, mintAmount))
      .to.emit(usb, 'Transfer').withArgs(ethers.constants.AddressZero, Dave.address, mintAmount)
      .to.emit(usb, 'TransferShares').withArgs(ethers.constants.AddressZero, Dave.address, ethers.utils.parseUnits('50', await usb.decimals()));

    // Dave directly transfer 10 shares to Bob
    // Total supply: 300; Bob shares: 60, Caro shares: 50, Dave shares: 40
    transferAmount = ethers.utils.parseUnits('10', await usb.decimals());
    await expect(usb.connect(Dave).transferShares(Bob.address, transferAmount))
      .emit(usb, 'Transfer').withArgs(Dave.address, Bob.address, ethers.utils.parseUnits('20', await usb.decimals()))
      .emit(usb, 'TransferShares').withArgs(Dave.address, Bob.address, transferAmount);
    expect(await usb.sharesOf(Bob.address)).to.equal(ethers.utils.parseUnits('60', await usb.decimals()));
    expect(await usb.balanceOf(Bob.address)).to.equal(ethers.utils.parseUnits('120', await usb.decimals()));
    
    // Bob approve Caro to transfer 20 $USB to Dave
    // Total supply: 300; Bob shares: 50, Caro shares: 50, Dave shares: 50
    let allowance = ethers.utils.parseUnits('20', await usb.decimals());
    await expect(usb.connect(Bob).approve(Caro.address, allowance))
      .to.emit(usb, 'Approval').withArgs(Bob.address, Caro.address, allowance);
    await expect(usb.connect(Caro).transferFrom(Bob.address, Dave.address, allowance.mul(2))).to.be.rejectedWith('Allowance exceeded');
    await expect(usb.connect(Caro).transferFrom(Bob.address, Dave.address, allowance))
      .to.emit(usb, 'Transfer').withArgs(Bob.address, Dave.address, allowance)
      .to.emit(usb, 'TransferShares').withArgs(Bob.address, Dave.address, ethers.utils.parseUnits('10', await usb.decimals()));
    expect(await usb.sharesOf(Bob.address)).to.equal(ethers.utils.parseUnits('50', await usb.decimals()));
    expect(await usb.balanceOf(Bob.address)).to.equal(ethers.utils.parseUnits('100', await usb.decimals()));

    // Bob increase 10 $USB allowance to Caro
    await expect(usb.connect(Caro).transferFrom(Bob.address, Dave.address, allowance)).to.be.rejectedWith('Allowance exceeded');
    await expect(usb.connect(Bob).increaseAllowance(Caro.address, allowance))
      .to.emit(usb, 'Approval').withArgs(Bob.address, Caro.address, allowance);
    await expect(usb.connect(Bob).decreaseAllowance(Caro.address, allowance.div(2)))
      .to.emit(usb, 'Approval').withArgs(Bob.address, Caro.address, allowance.div(2));
    
    // Caro transfer 5 shares (10 $USB) from Bob to Dave
    // Total supply: 300; Bob shares: 45, Caro shares: 50, Dave shares: 55
    transferAmount = ethers.utils.parseUnits('5', await usb.decimals());
    await expect(usb.connect(Caro).transferSharesFrom(Bob.address, Dave.address, transferAmount))
      .to.emit(usb, 'Transfer').withArgs(Bob.address, Dave.address, ethers.utils.parseUnits('10', await usb.decimals()))
      .to.emit(usb, 'TransferShares').withArgs(Bob.address, Dave.address, transferAmount);
    expect(await usb.sharesOf(Bob.address)).to.equal(ethers.utils.parseUnits('45', await usb.decimals()));
    expect(await usb.balanceOf(Bob.address)).to.equal(ethers.utils.parseUnits('90', await usb.decimals()));
    expect(await usb.sharesOf(Dave.address)).to.equal(ethers.utils.parseUnits('55', await usb.decimals()));
    expect(await usb.balanceOf(Dave.address)).to.equal(ethers.utils.parseUnits('110', await usb.decimals()));

    // Admin burns 10 $USB from Caro
    // Total supply: 295; Bob shares: 45, Caro shares: 45, Dave shares: 55
    let burnAmount = ethers.utils.parseUnits('10', await usb.decimals());
    // await expect(usb.connect(Caro).burn(Caro.address, burnAmount)).to.be.rejectedWith('Ownable: caller is not the owner');
    await expect(usb.connect(Alice).burn(Caro.address, burnAmount))
      .to.emit(usb, 'Transfer').withArgs(Caro.address, ethers.constants.AddressZero, burnAmount)
      .to.emit(usb, 'TransferShares').withArgs(Caro.address, ethers.constants.AddressZero, burnAmount.div(2));
    expect(await usb.sharesOf(Caro.address)).to.equal(ethers.utils.parseUnits('45', await usb.decimals()));
    expect(await usb.balanceOf(Caro.address)).to.equal(ethers.utils.parseUnits('90', await usb.decimals()));
    expect(await usb.totalShares()).to.equal(ethers.utils.parseUnits('145', await usb.decimals()));
    expect(await usb.totalSupply()).to.equal(ethers.utils.parseUnits('290', await usb.decimals()));

  });

});
