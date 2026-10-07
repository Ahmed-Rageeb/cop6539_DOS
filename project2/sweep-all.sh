#!/usr/bin/env bash
# Run every (algorithm, topology) configuration in its OWN Erlang VM.
# A configuration that dies then costs only itself, and each VM starts with
# a clean heap and process table instead of inheriting the previous one's.
set -u
ERL="/c/Program Files/Erlang OTP/bin/erl"
cd "$(dirname "$0")"
"$ERL" -noshell -pa . -run experiments main header -s init stop
for algo in gossip push_sum; do
  for topo in full 2D line imp2D; do
    echo "### $algo / $topo ###"
    "$ERL" -noshell -pa . -run experiments main one "$algo" "$topo" -s init stop
    echo "    [vm exited: $?]"
  done
done
echo "### CORE DONE -- starting bonus sweep ###"
"$ERL" -noshell -pa . -run experiments main bonus -s init stop
echo "### ALL DONE ###"
