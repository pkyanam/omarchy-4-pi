#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")"
run_name=${1:?unique result name required}
mkdir "results/$run_name"
docker run --name "cts-firmware-$run_name" --network none --cpus .25 --memory 128m --memory-swap 128m --pids-limit 32 --cap-drop ALL --cap-add CHOWN --cap-add SYS_CHROOT --security-opt no-new-privileges --mount "type=bind,src=$(cd .. && pwd),dst=/work,readonly" --entrypoint /usr/bin/python sha256:69878cfd4a96e064871f852fc0299669b15825d50a1bebfa72969cf72cb2d5b2 -I /work/firmware-tests/alpm.py >"results/$run_name/test.log" 2>&1 && result=0 || result=$?
docker inspect "cts-firmware-$run_name" >"results/$run_name/container.json"
exit "$result"
