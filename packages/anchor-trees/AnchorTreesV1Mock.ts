import { AnchorTreesV1Mock as AnchorTreesV1MockContract, AnchorTreesV1Mock__factory }from '../../typechain'
import { ethers, BigNumberish, BigNumber } from "ethers";
import { toFixedHex } from './utils';

export class AnchorTreesV1Mock {
  signer: ethers.Signer;
  contract: AnchorTreesV1MockContract;
  depositRoot: BigNumberish;
  withdrawalRoot: BigNumberish;

  constructor(
    signer: ethers.Signer,
    contract: AnchorTreesV1MockContract,
    depositRoot: BigNumberish,
    withdrawalRoot: BigNumberish
  ) {
    this.signer = signer;
    this.contract = contract;
    this.depositRoot = depositRoot;
    this.withdrawalRoot = withdrawalRoot;
  }

  public static async createAnchorTreesV1Mock(
    _depositRoot: BigNumberish,
    _withdrawalRoot: BigNumberish,
    deployer: ethers.Signer
  ) {
    const factory = new AnchorTreesV1Mock__factory(deployer);
    const contract = await factory.deploy(0, 0, toFixedHex(BigNumber.from(_depositRoot)), toFixedHex(BigNumber.from(_withdrawalRoot)));
    await contract.deployed();

    return new AnchorTreesV1Mock(deployer, contract, _depositRoot, _withdrawalRoot);
  }
}