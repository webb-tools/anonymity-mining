import { ethers } from "ethers";
import { AnchorProxy as AnchorProxyContract, AnchorProxy__factory } from '../../typechain';
import { WithdrawalEvent, RefreshEvent } from '@webb-tools/contracts/src/AnchorBase';
import { Anchor } from '@webb-tools/fixed-bridge';
import { AnchorDepositInfo } from '@webb-tools/fixed-bridge';
import { toFixedHex } from "@webb-tools/utils";

export enum InstanceState {
  DISABLED,
  ENABLED,
  MINEABLE,
}

interface Instance {
  token: string;
  state: InstanceState;
}

interface IAnchorStruct {
  addr: string;
  instance: Instance;
}

export class AnchorProxy {
  signer: ethers.Signer;
  contract: AnchorProxyContract;
  // An AnchorProxy can proxy for multiple anchors so we have a map from address to Anchor Class
  anchorMap: Map<string, Anchor>; 
  instanceMap: Map<string, InstanceState>;
  
  constructor(
    contract: AnchorProxyContract,
    signer: ethers.Signer,
    anchorList: Anchor[]
  ) {
    this.contract = contract;
    this.signer = signer;
    this.anchorMap = new Map<string, Anchor>();
    for (let i = 0; i < anchorList.length; i++) {
      this.insertAnchor(anchorList[i]);
    }
  }

  //need to fix this
  public static async createAnchorProxy(
    _anchorTrees: string,
    _governance: string,
    _anchorList: Anchor[],
    _instanceStateList: InstanceState[],
    deployer: ethers.Signer
  ) {
    const factory = new AnchorProxy__factory(deployer);
    const instances = _anchorList.map((a: Anchor, index) => {
      return {
        addr: a.contract.address,
        instance: {
          token: a.token || '',
          state: _instanceStateList[index],
        },
      }
    });
    const contract = await factory.deploy(_anchorTrees, _governance, instances); //edit this
    await contract.deployed();

    const handler = new AnchorProxy(contract, deployer, _anchorList);
    return handler;
  }

  public async deposit(anchorAddr: string, destChainId: number, encryptedNote?: string): Promise<{deposit: AnchorDepositInfo, index: number}> {
    const deposit: AnchorDepositInfo = Anchor.generateDeposit(destChainId);
    let _encryptedNote: string = '0x000000'
    if (encryptedNote) {
      const _encryptedNote: string = encryptedNote;
    } 

    const tx = await this.contract.deposit(
      anchorAddr,
      toFixedHex(deposit.commitment),
      _encryptedNote,
      { gasLimit: '0x5B8D80' }
    );
  
    await tx.wait();

    const anchor = this.anchorMap.get(anchorAddr);
    if (!anchor) {
      throw new Error('Anchor not found');
    }

    const index: number = anchor.tree.insert(deposit.commitment);
    return { deposit, index };
  }

  public async withdraw(
    anchorAddr: string,
    deposit: AnchorDepositInfo,
    index: number,
    recipient: string,
    relayer: string,
    fee: bigint,
    refreshCommitment: string | number,
  ): Promise<RefreshEvent | WithdrawalEvent> {
    const anchor = this.anchorMap.get(anchorAddr);
    if (!anchor) {
      throw new Error('Anchor not found');
    }
    const { args, input, proofEncoded, publicInputs } = await anchor.setupWithdraw(
      deposit,
      index,
      recipient,
      relayer,
      fee,
      refreshCommitment,
    );
    //@ts-ignore
    let tx = await this.contract.withdraw(
      anchorAddr,
      `0x${proofEncoded}`,
      publicInputs,
      { gasLimit: '0x5B8D80' }
    );
    const receipt = await tx.wait();

    if (args[2] !== '0x0000000000000000000000000000000000000000000000000000000000000000') {
      anchor.tree.insert(input.refreshCommitment);
      const filter = anchor.contract.filters.Refresh(null, null, null);
      const events = await anchor.contract.queryFilter(filter, receipt.blockHash);
      return events[0];
    } else {
      const filter = anchor.contract.filters.Withdrawal(null, null, relayer, null);
      const events = await anchor.contract.queryFilter(filter, receipt.blockHash);
      return events[0];
    }
  }

  public insertAnchor(anchor: Anchor) {
    this.anchorMap.set(anchor.contract.address, anchor);
  }

  public static stringToInstanceState(stringInstance: string): InstanceState {
    if (stringInstance === 'MINEABLE') {
      return InstanceState.MINEABLE;
    } else if (stringInstance === 'ENABLED')  {
      return InstanceState.ENABLED;
    } else if (stringInstance === "DISABLED") {
      return InstanceState.DISABLED;
    } else {
      console.log("Invalid string instance");
    }
  }
}
