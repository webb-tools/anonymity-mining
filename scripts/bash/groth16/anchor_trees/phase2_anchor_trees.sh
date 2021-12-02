source ./scripts/bash/groth16/phase2_circuit_groth16.sh

compile_phase2 ./build/anchor_trees anchor_trees_test ./artifacts/circuits/anchor_trees
move_verifiers_and_metadata ./build/anchor_trees 0 anchor_trees 