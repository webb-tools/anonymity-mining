#!/bin/bash

mkdir -p artifacts/circuits/{anchor,anchor_trees,bridge,keypair,semaphore,signature,vanchor_2,vanchor_16}

compile () {
    local outdir="$1" circuit="$2" size="$3"
    mkdir -p build/$outdir
    mkdir -p build/$outdir/$size
    echo "$circuits/test/$circuit.circom"
    ~/.cargo/bin/circom --r1cs --wasm --sym \
        -o artifacts/circuits/$outdir \
        circuits/test/$circuit.circom
    echo -e "Done!\n"
}

copy_to_fixtures () {
    local outdir="$1" circuit="$2" size="$3" bridgeType="$4" 
    mkdir -p anonymity-mining-fixtures/fixtures/$bridgeType
    mkdir -p anonymity-mining-fixtures/fixtures/$bridgeType/$size
    cp artifacts/circuits/$outdir/$circuit.sym anonymity-mining-fixtures/fixtures/$bridgeType/$size/$circuit.sym
    cp artifacts/circuits/$outdir/$circuit.r1cs anonymity-mining-fixtures/fixtures/$bridgeType/$size/$circuit.r1cs
    cp artifacts/circuits/$outdir/$circuit\_js/$circuit.wasm anonymity-mining-fixtures/fixtures/$bridgeType/$size/$circuit.wasm
    cp artifacts/circuits/$outdir/$circuit\_js/witness_calculator.js anonymity-mining-fixtures/fixtures/$bridgeType/$size/witness_calculator.js
}

# Anchor Trees BatchUpdateVerifier Circuit
compile anchor_trees anchor_trees_test
copy_to_fixtures anchor_trees anchor_trees_test 0 anchor_trees