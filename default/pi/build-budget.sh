# shellcheck shell=bash
# Sourced by makepkg on this Pi only. Never add -march=native: artifacts must
# remain usable across the supported Pi 4 boards and their build hosts.
omarchy_pi_build_budget() {
  local cores available total jobs memory_jobs
  cores=$(nproc)
  available=$(awk '/^MemAvailable:/ {print $2}' /proc/meminfo)
  total=$(awk '/^MemTotal:/ {print $2}' /proc/meminfo)
  jobs=$(( cores > 1 ? cores - 1 : 1 ))
  memory_jobs=$(( available / 1048576 ))
  (( memory_jobs > 0 )) || memory_jobs=1
  (( jobs <= memory_jobs )) || jobs=$memory_jobs
  # A 4GB desktop gets at most two compiler jobs; leave RAM for the browser,
  # compositor, linker, and the agent orchestrating the build.
  if (( total < 5242880 && jobs > 2 )); then
    jobs=2
  fi
  export MAKEFLAGS="${MAKEFLAGS:--j$jobs}"
  export CMAKE_BUILD_PARALLEL_LEVEL="${CMAKE_BUILD_PARALLEL_LEVEL:-$jobs}"
  export CARGO_BUILD_JOBS="${CARGO_BUILD_JOBS:-$jobs}"
  # Local install artifacts need not spend CPU/RAM chasing archival ratios.
  # shellcheck disable=SC2034 # Consumed by the sourcing makepkg process.
  COMPRESSZST=(zstd -c -T"$jobs" -3 -)
}
omarchy_pi_build_budget
unset -f omarchy_pi_build_budget
