#!/usr/bin/env bash
# Lab 01b, turn the temperature up (slide: "But doesn't it always take the most predictable
# token?"). Same prompt, same distribution: now watch which candidate it picks. Run it a few times.
#
# Usage:  ./logprobs_high_temp.bash     # TEMP=1.5
#         TEMP=3 ./logprobs_high_temp.bash
TEMP="${TEMP:-1.5}" exec "$(dirname "$0")/logprobs.bash" "$@"
