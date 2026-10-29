#!/usr/bin/env bash
# Runs all the experiments, each one in a new Erlang VM so a crash only
# loses that run. Results go to results/
set -u
ERL="/c/Program Files/Erlang OTP/bin/erl"
cd "$(dirname "$0")"
run() { "$ERL" -noshell -pa . -run experiments main "$@" -s init stop; }

mkdir -p results
run header

echo "### core: average hops vs network size ###"
for n in 10 20 50 100 200 500 1000 2000 5000; do run core $n 3; done
for n in 10000 20000 50000 100000; do run core $n 1; done

echo "### bonus: node death ###";                  run bonus kill
echo "### bonus: temporary connection failure ###"; run bonus drop
echo "### bonus: permanent connection failure ###"; run bonus links
echo "### ALL DONE ###"
