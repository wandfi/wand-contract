import _ from 'lodash';
import { ethers } from 'hardhat';
import { expect } from 'chai';
import { loadFixture } from '@nomicfoundation/hardhat-network-helpers';
import { deployContractsFixture } from './utils';
import { anyValue } from '@nomicfoundation/hardhat-chai-matchers/withArgs';

import { 
  MockUsb__factory
} from '../typechain';

const { provider } = ethers;

describe('Usb', () => {

  it.only('Usb works', async () => {

    const { Alice, Bob, Caro } = await loadFixture(deployContractsFixture);

    const MockUsbFactory = await ethers.getContractFactory('MockUsb');
    const MockUsb = await MockUsbFactory.deploy();
    const usb = MockUsb__factory.connect(MockUsb.address, provider);

    // Alice mint 100 $USB to Bob.
    // Bobs share: 100
    let mintAmount = ethers.utils.parseUnits('100', await usb.decimals());
    await expect(usb.connect(Bob).mint(Bob.address, mintAmount)).to.be.rejectedWith('Ownable: caller is not the owner');
    await expect(usb.connect(Alice).mint(Bob.address, mintAmount))
      .to.emit(usb, 'Transfer').withArgs(ethers.constants.AddressZero, Bob.address, mintAmount)
      .to.emit(usb, 'TransferShares').withArgs(ethers.constants.AddressZero, Bob.address, mintAmount);

  });

});
