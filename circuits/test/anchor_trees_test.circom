pragma circom 2.0.0;

include "../anchor_trees/BatchTreeUpdate.circom";

component main {public [argsHash]} = BatchTreeUpdate(5, 2, nthZero(2));
