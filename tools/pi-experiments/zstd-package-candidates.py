"""Authenticate matching ALARM package and prepare or explicitly build private O2/O3 recipes.

Run with python3. Docker must already contain the selected image. No image pull or host install,
Pi access, signing or publication occurs. --build-pair executes bounded offline builds.
"""

import argparse
import hashlib
import json
import re
import shutil
import subprocess
import time
from pathlib import Path


IMAGE = "sha256:3862c9a52166b7310e7de0b08131f4e69fbd0cbebba29c9510bf3085908417bd"
KEY = "68B3537F39A313B3E574D06777193F152BDBE6A6"
TARGET = "4eea9767b11369ebfda02824052458efcdcc08e1f82325c952adec3c1cc4db1c"
PKG = "zstd-1.5.7-3-aarch64.pkg.tar.xz"
COMMIT = "954700db664044388cabc818d703bcfae97bfa1c"
PATCH = "6af3842118ea5325480b403213b2a9fbed3d3d74.patch"
BASE = "https://gitlab.archlinux.org/archlinux/packaging/packages/zstd/-/raw/"
INPUTS = {
  PKG: ("http://mirror.archlinuxarm.org/aarch64/core/" + PKG,
        "c3b907c36049b338bda0c6d85260251e48d17e2be6c0e11ddc0dfd4cf9d2e89a"),
  PKG + ".sig": ("http://mirror.archlinuxarm.org/aarch64/core/" + PKG + ".sig",
                 "26b15a5f3e277d74a6ce12462b7971ef6ac25ebc19e5348fa7c1da5bba0d0ed0"),
  "PKGBUILD.arch": (BASE + COMMIT + "/PKGBUILD",
                    "6e92a6cf64ab0b3e4b59d838f1cd762060915ad7f13ca721246b3ae45d6c1f1d"),
  "zstd-1.5.7.tar.zst": ("https://api.github.com/repos/meta/zstd/releases/assets/230758926",
                         "5b331d961d6989dc21bb03397fc7a2a4d86bc65a14adc5ffbbce050354e30fd2"),
  "zstd-1.5.7.tar.zst.sig": ("https://api.github.com/repos/meta/zstd/releases/assets/230758931",
                             "78c9fabf945f301630a4020fadd34b9ecc16ef42ee279dd63a5a923e71d40449"),
  PATCH: ("https://github.com/facebook/zstd/commit/" + PATCH,
          "7c07be222d45718b81fb16f97e611adfeb24efa0712ca77fb1e08f4c67803ec3"),
}


def digest(path):
  return hashlib.sha256(path.read_bytes()).hexdigest()


def container(image, out, code, log):
  # Only /work is writable; no network, image pull, tmpfs build storage or compiler.
  cmd = ["docker", "run", "--rm", "--pull=never", "--read-only", "--network", "none",
         "--cpus", ".25", "--memory", "256m", "--memory-swap", "256m",
         "--pids-limit", "64", "--entrypoint", "/bin/bash",
         "-v", f"{out}:/work", image, "-c", code]
  with (out / log).open("w") as stream:
    result = subprocess.run(cmd, stdout=stream, stderr=subprocess.STDOUT)
  return result.returncode


INSPECT = r'''set -euo pipefail
mkdir -p /work/gnupg
chmod 700 /work/gnupg
gpg --homedir /work/gnupg --batch --import /usr/share/pacman/keyrings/archlinuxarm.gpg
gpg --homedir /work/gnupg --no-auto-key-retrieve --status-fd 1 --verify /work/zstd-1.5.7-3-aarch64.pkg.tar.xz.sig /work/zstd-1.5.7-3-aarch64.pkg.tar.xz
for entry in .BUILDINFO .PKGINFO; do
  tar -xOf /work/zstd-1.5.7-3-aarch64.pkg.tar.xz "$entry" > "/work/${entry#.}"
done
tar -tf /work/zstd-1.5.7-3-aarch64.pkg.tar.xz > /work/package-files.txt
tar -xOf /work/zstd-1.5.7-3-aarch64.pkg.tar.xz usr/bin/zstd > /work/stock-zstd
tar -xOf /work/zstd-1.5.7-3-aarch64.pkg.tar.xz usr/lib/libzstd.so.1.5.7 > /work/stock-libzstd.so.1.5.7
tar -xOf /work/zstd-1.5.7-3-aarch64.pkg.tar.xz usr/lib/cmake/zstd/zstdTargets-none.cmake > /work/stock-zstdTargets-none.cmake
readelf --dyn-syms --wide /work/stock-libzstd.so.1.5.7 > /work/stock-library-symbols.txt
for elf in /work/stock-zstd /work/stock-libzstd.so.1.5.7; do
  sha256sum "$elf"
  readelf -h -d -n -l --version-info "$elf"
  readelf -p .GCC.command.line "$elf"
done
cat /etc/makepkg.conf > /work/inspection-image.makepkg.conf
pacman -Q > /work/inspection-image.packages
cat /sys/fs/cgroup/{cpu.max,memory.max,memory.swap.max}
'''

# Inserted before the original build function. Both variants use exactly this body.
# Keep the original CMake/package/check operations, source hashes and feature set.
CONTROL = r'''
  [[ $CARCH == "aarch64" ]]
  [[ ${LTOFLAGS:-} == "" ]]
  # Replace the single optimization token and preserve every other makepkg flag.
  for name in CFLAGS CXXFLAGS; do
    value=${!name}
    [[ $value == *"-march=armv8-a"* ]]
    [[ $value != *"-mcpu="* && $value != *"-mtune="* && $value != *"-flto"* ]]
    [[ $value == *"-fstack-protector-strong"* && $value == *"-D_FORTIFY_SOURCE=3"* ]]
    [[ $value == *"-fstack-clash-protection"* && $value == *"-fno-omit-frame-pointer"* ]]
    [[ $value == *"-Werror=format-security"* && $value == *"-fexceptions"* ]]
    words=($value)
    count=0
    for index in "${!words[@]}"; do
      if [[ ${words[$index]} == -O* ]]; then
        words[$index]="-O${_opt}"
        (( count += 1 ))
      fi
    done
    (( count == 1 ))
    printf -v "$name" '%s' "${words[*]}"
    export "$name"
  done
  [[ $LDFLAGS == *"-z,relro"* && $LDFLAGS == *"-z,now"* ]]
  export CMAKE_BUILD_PARALLEL_LEVEL=1 CTEST_PARALLEL_LEVEL=1
  export MAKEFLAGS=-j1
'''


def prepare(out):
  config = (out / "inspection-image.makepkg.conf").read_text()
  config += '''
# Private controlled experiment config; contemporary image, not historical flags.
BUILDENV=(!distcc !color !ccache check !sign)
OPTIONS=(strip docs !libtool !staticlibs emptydirs zipman purge !debug !lto)
MAKEFLAGS="-j1"
PACKAGER="Private zstd compiler experiment"
COMPRESSXZ=(xz -c -z -T1 -)
'''
  (out / "candidate.makepkg.conf").write_text(config)
  recipe = (out / "PKGBUILD.arch").read_text()
  # This is explicitly an adaptation of the Arch recipe, not a recovered ALARM hash.
  recipe = recipe.replace("arch=(x86_64)", "arch=(aarch64)").replace("pkgrel=3\n", "pkgrel=3.1\n")
  recipe = recipe.replace("build() {", "build() {\n" + CONTROL)
  recipe = recipe.replace("-DCMAKE_BUILD_TYPE=None", "-DCMAKE_BUILD_TYPE=None \\\n    -DCMAKE_EXPORT_COMPILE_COMMANDS=ON \\\n    -DCMAKE_C_COMPILER_LAUNCHER=\"${startdir}/record-compiler\" \\\n    -DCMAKE_CXX_COMPILER_LAUNCHER=\"${startdir}/record-compiler\" \\\n    -DCMAKE_ASM_COMPILER_LAUNCHER=\"${startdir}/record-compiler\" \\\n    -DZSTD_BUILD_SHARED=ON \\\n    -DZSTD_MULTITHREAD_SUPPORT=ON \\\n    -DZSTD_LEGACY_SUPPORT=ON \\\n    -DZSTD_LEGACY_LEVEL=5")
  recipe = recipe.replace("cmake --build build", "cmake --build build --verbose")
  wrapper = '''#!/bin/bash
set -euo pipefail
printf '%q ' "$@" >> "${0%/*}/compiler-argv.log"
printf '\\n' >> "${0%/*}/compiler-argv.log"
"$@"
'''
  for opt in (2, 3):
    dest = out / f"O{opt}"
    if (dest / "src").exists() or (dest / "pkg").exists() or (dest / "compiler-argv.log").exists():
      raise RuntimeError(f"Refusing previously built candidate directory: {dest}")
    dest.mkdir(exist_ok=True)
    (dest / "PKGBUILD").write_text(f"# Private experiment; never publish. Derived from Arch {COMMIT}.\n_opt={opt}\n" + recipe)
    (dest / "record-compiler").write_text(wrapper)
    (dest / "record-compiler").chmod(0o755)
    for name in ("zstd-1.5.7.tar.zst", "zstd-1.5.7.tar.zst.sig", PATCH):
      shutil.copyfile(out / name, dest / name)
    subprocess.run(["/bin/bash", "-n", str(dest / "PKGBUILD")], check=True)
  a = (out / "O2/PKGBUILD").read_text()
  b = (out / "O3/PKGBUILD").read_text()
  if a.replace("_opt=2\n", "_opt=3\n", 1) != b:
    raise RuntimeError("Paired recipes differ beyond optimization")



HEALTH = r'''import json, os
from pathlib import Path
c = Path("/sys/fs/cgroup")
m = {line.split()[0].rstrip(":"): int(line.split()[1]) for line in Path("/proc/meminfo").read_text().splitlines()}
events = dict(line.split() for line in (c / "memory.events").read_text().splitlines())
result = {key: m[key] for key in ("MemTotal", "MemAvailable", "SwapTotal", "SwapFree")}
for key in ("memory.current", "memory.peak", "memory.swap.current", "memory.swap.max"):
  result[key.replace("memory.", "").replace(".", "_")] = int((c / key).read_text())
result["oom_kill"] = int(events["oom_kill"])
result["events"] = events
result["swap_events"] = (c / "memory.swap.events").read_text()
result["swap_peak"] = int((c / "memory.swap.peak").read_text()) if (c / "memory.swap.peak").exists() else None
result["psi_full_avg10"] = float(Path("/proc/pressure/memory").read_text().split("full avg10=")[1].split()[0]) if Path("/proc/pressure/memory").exists() else None
v = os.statvfs("/work")
result["disk_available"] = v.f_bavail * v.f_frsize
result["swaps"] = [{"device": fields[0], "size_kib": int(fields[2]), "used_kib": int(fields[3]), "priority": int(fields[4])}
                   for line in Path("/proc/swaps").read_text().splitlines()[1:] if (fields := line.split())]
print(json.dumps(result))
'''


def validate_swap_health(health, swap_mib):
  """A combined SwapTotal is insufficient: zram consumes VM RAM."""
  if swap_mib:
    devices = health["swaps"]
    if any(Path(item["device"]).name.startswith("zram") for item in devices):
      raise RuntimeError("Disk-backed envelope unavailable: active zram swap; VM changes unauthorized")
    if sum(item["size_kib"] - item["used_kib"] for item in devices) < swap_mib * 1024:
      raise RuntimeError("Insufficient free disk-backed VM swap for requested envelope")


def build_pair(out, image, expected, memory_mib=768, swap_mib=0):
  """Build only against an explicitly selected, dependency-complete local image."""
  if not re.fullmatch(r"sha256:[0-9a-f]{64}", image) or not expected:
    raise RuntimeError("Exact image ID and expected package manifest required")
  if not 768 <= memory_mib <= 3072:
    raise RuntimeError("Build budget must be 768..3072 MiB; default 768")
  if not 0 <= swap_mib <= 2304:
    raise RuntimeError("Swap budget must be 0..2304 MiB; default 0")
  if (out / "build-result.json").exists():
    raise RuntimeError("Prior attempt exists; use a distinct freshly prepared output directory")
  probe = subprocess.run([
    "docker", "run", "--rm", "--pull=never", "--read-only", "--network=none",
    "--cpus=.25", "--memory=256m", "--memory-swap=256m",
    "-v", f"{out}:/work:ro", "--entrypoint=/usr/bin/python", image, "-c", HEALTH],
    capture_output=True, text=True)
  (out / "vm-preflight.json").write_text(probe.stdout)
  (out / "vm-preflight.stderr").write_text(probe.stderr)
  if probe.returncode:
    raise RuntimeError("VM/swap accounting preflight unavailable; no build started")
  health = json.loads(probe.stdout)
  validate_swap_health(health, swap_mib)
  # Reserve 512 MiB of actual VM RAM outside the selected container envelope.
  if min(health["MemTotal"], health["MemAvailable"]) < (memory_mib + 512) * 1024 or health["disk_available"] < 4 * 1024**3:
    raise RuntimeError("VM memory/storage preflight insufficient; no build started")
  inventory = subprocess.check_output([
    "docker", "run", "--rm", "--pull=never", "--read-only", "--network=none",
    "--cpus=.25", "--memory=256m", "--memory-swap=256m", "--entrypoint=/usr/bin/pacman", image, "-Q"])
  if inventory != expected.read_bytes():
    raise RuntimeError("Builder inventory differs from frozen manifest")
  for name, (_, sha) in INPUTS.items():
    if digest(out / name) != sha:
      raise RuntimeError(f"Input checksum mismatch: {name}")
  a, b = [(out / f"O{opt}/PKGBUILD").read_text() for opt in (2, 3)]
  if a.replace("_opt=2\n", "_opt=3\n", 1) != b:
    raise RuntimeError("Recipes differ beyond optimization")
  # Refuse reuse; a failed attempt is evidence, never disposable scratch.
  for opt in (2, 3):
    dest = out / f"O{opt}"
    if any((dest / n).exists() for n in ("src", "pkg", "compiler-argv.log", "build.log")):
      raise RuntimeError(f"Prior build evidence exists: {dest}")
  code = r'''set -euo pipefail
cd /work/O$1
mkdir -p home tmp
export HOME=$PWD/home TMPDIR=$PWD/tmp GNUPGHOME=$PWD/home/gnupg
mkdir -m 700 "$GNUPGHOME"
gpg --batch --import /work/upstream-release-key.asc
gpg --batch --no-auto-key-retrieve --status-fd 1 --verify zstd-1.5.7.tar.zst.sig zstd-1.5.7.tar.zst
trap 'rc=$?; for file in cpu.max memory.max memory.swap.max memory.current memory.peak memory.swap.current memory.swap.peak memory.events memory.swap.events; do if [[ -f /sys/fs/cgroup/$file ]]; then printf "%s\n" "$file"; cat "/sys/fs/cgroup/$file"; fi; done > resources.txt; exit "$rc"' EXIT
[[ -r /sys/fs/cgroup/memory.swap.current && -r /sys/fs/cgroup/memory.swap.max ]]
[[ $(cat /sys/fs/cgroup/memory.swap.max) == "$2" ]]
pacman -Q > build.packages
env | sort > environment.txt
makepkg --config /work/candidate.makepkg.conf --cleanbuild --log
'''
  (out / "build-pair.sh").write_text("#!/bin/bash\n" + code)
  selection = {"image": image, "packages_sha256": digest(expected),
               "memory_mib": memory_mib, "swap_mib": swap_mib, "cpus": 1,
               "makepkg_config_sha256": digest(out / "candidate.makepkg.conf"),
               "status": "building; not installed", "attempts": []}
  for opt in (2, 3):
    name = f"zstd-private-{out.name}-O{opt}"
    cmd = ["docker", "run", "--name", name, "--pull=never", "--read-only",
           "--network=none", "--cpus=1", f"--memory={memory_mib}m", f"--memory-swap={memory_mib + swap_mib}m",
           "--pids-limit=128", "--user=1000:1000", "-v", f"{out}:/work", "-w", f"/work/O{opt}",
           "--entrypoint=/usr/bin/env", image, "-i", "PATH=/usr/bin:/bin", "LANG=C.UTF-8",
           "LC_ALL=C.UTF-8", "SOURCE_DATE_EPOCH=1771243807", "CMAKE_BUILD_PARALLEL_LEVEL=1",
           "CTEST_PARALLEL_LEVEL=1", "VERBOSE=1", "MAKEFLAGS=-j1",
           "/bin/bash", "/work/build-pair.sh", str(opt), str(swap_mib * 1024**2)]
    (out / f"O{opt}/docker-command.json").write_text(json.dumps(cmd, indent=2) + "\n")
    try:
      with (out / f"O{opt}/build.log").open("w") as log:
        process = subprocess.Popen(cmd, stdout=log, stderr=subprocess.STDOUT)
        severe_samples = 0
        probe_failures = 0
        with (out / f"O{opt}/health.jsonl").open("w") as health:
          while process.poll() is None:
            probe = subprocess.run(["docker", "exec", name, "/usr/bin/python", "-c", HEALTH],
                                   capture_output=True, text=True)
            if probe.returncode == 0:
              probe_failures = 0
              sample = json.loads(probe.stdout)
              sample["time"] = time.time()
              health.write(json.dumps(sample) + "\n")
              health.flush()
              severe = (sample["MemAvailable"] < 96 * 1024 or (sample["psi_full_avg10"] or 0) > 50)
              severe_samples = severe_samples + 1 if severe else 0
              blocker = None
              try:
                validate_swap_health(sample, swap_mib)
              except RuntimeError as error:
                blocker = str(error)
              if sample["swap_max"] != swap_mib * 1024**2:
                blocker = "Swap accounting/limit unavailable or differs from request"
              elif sample["oom_kill"] > 0:
                blocker = "OOM kill in unchanged upstream build/checks"
              elif severe_samples >= 3:
                blocker = "Sustained severe global Docker VM memory pressure"
              elif sample["disk_available"] < 2 * 1024**3 or shutil.disk_usage(out).free < 4 * 1024**3:
                blocker = "Storage reserve endangered"
              if blocker:
                selection["blocker"] = blocker
                subprocess.run(["docker", "stop", "--time=10", name], capture_output=True)
                break
            elif process.poll() is None:
              probe_failures += 1
              if probe_failures >= 3:
                selection["blocker"] = "Repeated resource-accounting probe failure"
                subprocess.run(["docker", "stop", "--time=10", name], capture_output=True)
                break
            try:
              process.wait(timeout=10)
            except subprocess.TimeoutExpired:
              pass
        rc = process.wait()
    finally:
      # Preserve inspection before removing this attempt's container, including on interruption.
      subprocess.run(["docker", "stop", "--time=10", name], stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
      inspected = subprocess.run(["docker", "inspect", name], capture_output=True)
      (out / f"O{opt}/container-inspect.json").write_bytes(inspected.stdout)
      subprocess.run(["docker", "rm", name], stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
    selection["attempts"].append({"optimization": opt, "exit": rc})
    selection["status"] = "blocked; partial evidence retained" if rc else "build completed; audit pending"
    (out / "build-result.json").write_text(json.dumps(selection, indent=2) + "\n")
    if rc:
      raise RuntimeError(f"O{opt} failed ({rc}); cap unchanged; see build.log")
  print("Both package builds completed; not installed. Artifact audit remains required.")


def main():
  parser = argparse.ArgumentParser(description=__doc__)
  parser.add_argument("--out", type=Path, default=Path(__file__).resolve().parents[2] / "build/upstream-pi/stable-4.5/zstd-package-candidates")
  parser.add_argument("--build-pair", help="Exact dependency-complete local image; explicitly execute bounded offline builds")
  parser.add_argument("--preflight-builder", help="Parent-selected exact local sha256 image ID; never builds")
  parser.add_argument("--expected-packages", type=Path, help="Parent-reviewed complete pacman -Q manifest")
  parser.add_argument("--build-memory-mib", type=int, default=768,
                      help="Explicit build RAM limit in MiB (768..3072; default 768)")
  parser.add_argument("--build-swap-mib", type=int, default=0,
                      help="Explicit disk-backed swap limit in MiB (0..2304; default 0)")
  args = parser.parse_args()
  if not 0 <= args.build_swap_mib <= 2304:
    parser.error("--build-swap-mib must be between 0 and 2304")
  if not 768 <= args.build_memory_mib <= 3072:
    parser.error("--build-memory-mib must be between 768 and 3072")
  out = args.out.resolve()
  out.mkdir(parents=True, exist_ok=True)
  if args.build_pair:
    build_pair(out, args.build_pair, args.expected_packages, args.build_memory_mib, args.build_swap_mib)
    return
  if args.preflight_builder:
    if not re.fullmatch(r"sha256:[0-9a-f]{64}", args.preflight_builder) or not args.expected_packages:
      parser.error("Preflight needs exact sha256 image ID and --expected-packages")
    code = '''set -euo pipefail
pacman -Q > /work/parent-builder.packages
pacman -Q gcc binutils glibc cmake ninja gtest zlib xz lz4 base-devel fakeroot python
for tool in gcc g++ cmake ninja makepkg fakeroot python patch; do command -v "$tool"; done
[[ -f /usr/include/zlib.h && -f /usr/include/lzma.h && -f /usr/include/lz4.h ]]
cat /etc/makepkg.conf > /work/parent-builder.makepkg.conf
'''
    rc = container(args.preflight_builder, out, code, "parent-builder-preflight.log")
    if rc or (out / "parent-builder.packages").read_bytes() != args.expected_packages.read_bytes():
      raise SystemExit("Builder/dependency gate FAILED; see parent-builder-preflight.log. No build attempted.")
    (out / "parent-builder-selection.json").write_text(json.dumps({"image": args.preflight_builder, "packages_sha256": digest(args.expected_packages), "status": "dependency inventory only; parent must review flags/trust/resources before building"}, indent=2) + "\n")
    print("Dependency inventory matches. No build attempted; configuration and resource gate remains manual.")
    return
  for name, (url, expected) in INPUTS.items():
    path = out / name
    if not path.exists():
      subprocess.run(["curl", "-fL", "--connect-timeout", "15", "--max-time", "90", "-H", "Accept: application/octet-stream", url, "-o", str(path)], check=True)
    if digest(path) != expected:
      raise RuntimeError(f"Hash mismatch: {path}")
  if container(IMAGE, out, INSPECT, "verified-archive-inspection.log"):
    raise RuntimeError("Signature/inspection failed; see verified-archive-inspection.log")
  log = (out / "verified-archive-inspection.log").read_text()
  if f"[GNUPG:] VALIDSIG {KEY} " not in log or digest(out / "stock-zstd") != TARGET:
    raise RuntimeError("Official signer or exact target binary mismatch")
  prepare(out)
  manifest = {name: {"url": url, "sha256": digest(out / name)} for name, (url, _) in INPUTS.items()}
  manifest["evidence"] = {"signer": KEY, "target_cli_sha256": TARGET, "installed_recipe_sha256": "924e4284597f6aede736f70c189d7b4a2445e99b88fdf7e6580e434494c6553f", "exact_arm_recipe_recovered": False, "resolved_installed_compiler_flags": "unknown", "candidate_status": "prepared only; not configured, compiled, tested, packaged or installed"}
  (out / "provenance.json").write_text(json.dumps(manifest, indent=2) + "\n")
  print(f"Verified exact target CLI; prepared O2/O3 recipes in {out}. No build attempted.")


if __name__ == "__main__":
  main()
