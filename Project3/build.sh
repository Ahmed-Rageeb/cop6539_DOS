#!/bin/sh
# Compile Project 3 on Mac or Linux. Needs erlc on the PATH.
cd "$(dirname "$0")" || exit 1
erlc project3.erl main.erl pastry_init.erl pastry_node.erl route.erl deliver.erl \
     forward.erl new_leafs.erl node_state.erl rtable.erl pastry_util.erl \
     failure.erl experiments.erl report.erl && echo "Build OK."
