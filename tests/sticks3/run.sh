#!/bin/sh
set -eu
cd "$(dirname "$0")/../.."
test_dir=$(mktemp -d)
trap 'rm -rf "$test_dir"' EXIT
for test_name in power imu backlight; do
    "${CXX:-c++}" -std=c++11 -I tests/sticks3 "tests/sticks3/$test_name.cpp" -o "$test_dir/$test_name"
    "$test_dir/$test_name"
    echo "$test_name: PASS"
done

case "$(uname -s)" in
    Darwin) gp_runtime=./gp/gp-mac ;;
    Linux) gp_runtime=./gp/gp-linux64bit ;;
    *) gp_runtime= ;;
esac
if [ -n "$gp_runtime" ] && [ -x "$gp_runtime" ]; then
    "$gp_runtime" gp/runtime/lib/*.gp ide/MicroBlocksRuntime.gp tests/sticks3/ide.gp > "$test_dir/ide.log"
    cat "$test_dir/ide.log"
    grep -q '^ide capabilities: PASS' "$test_dir/ide.log"
else
    echo 'ide capabilities: SKIP (no bundled GP runtime for this host)'
fi
