import { ethers } from "ethers";

import { BatchTreeVerifier as BatchTreeVerifierContract, BatchTreeVerifier__factory } from "../../typechain";

//Maintains the BatchTreeVerifier (5,2)

export class BatchTreeVerifier {
    signer: ethers.Signer;
    contract: BatchTreeVerifierContract;
  
    private constructor(
      contract: BatchTreeVerifierContract,
      signer: ethers.Signer,
    ) {
      this.signer = signer;
      this.contract = contract;
    }
  
    // Deploys a Verifier contract and all auxiliary verifiers used by this verifier
    public static async createVerifier(
      signer: ethers.Signer,
    ) {
      const factory= new BatchTreeVerifier__factory(signer);
      const batchTreeVerifier = await factory.deploy();
      await batchTreeVerifier.deployed();
      const createdVerifier = new BatchTreeVerifier(batchTreeVerifier, signer);
      return createdVerifier;
    }
  }