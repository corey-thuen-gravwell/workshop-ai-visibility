#!/usr/bin/env bash
# Lab 01b: the same picker, on code. When the training data is nearly unanimous, so is the
# distribution: watch the probabilities go to 99%.
#
# Usage:  ./logprobs_code.bash          (accepts the same TEMP= / TOP= / RAW= as logprobs.bash)
exec "$(dirname "$0")/logprobs.bash" \
    "Complete the function without annotation, just complete the function: void main(void){ printf("
