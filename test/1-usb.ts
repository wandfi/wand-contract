import _ from 'lodash';
import { ethers } from 'hardhat';
import { expect } from 'chai';
import { loadFixture } from '@nomicfoundation/hardhat-network-helpers';
import { deployContractsFixture } from './utils';
import { anyValue } from '@nomicfoundation/hardhat-chai-matchers/withArgs';

describe('Usb', () => {

  it('Usb works', async () => {

    const { usbToken, Alice, Bob, Caro } = await loadFixture(deployContractsFixture);

  });

});
