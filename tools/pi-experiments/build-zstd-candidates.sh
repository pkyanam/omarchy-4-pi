#!/bin/bash
# Isolated experiment only. Never installs packages or libraries.
set -euo pipefail
if [[ ${1:-} != "--inner" ]]; then
  repo=$(cd "$(dirname "$0")/../.." && pwd)
  out=${1:-"$repo/build/upstream-pi/stable-4.5/zstd-compiler-candidates"}
  mkdir -p "$out/source"
  out=$(cd "$out" && pwd)
  cat >"$out/correctness.py" <<'ZSTD_CORRECTNESS_PY'
"""Run inside the bounded builder, never on a Pi in this lane."""
import gzip, hashlib, json, pathlib, subprocess
p=pathlib.Path('/work'); corpus=p/'corpus'; corpus.mkdir(exist_ok=True)
(corpus/'source.tar').write_bytes(gzip.decompress((p/'source/zstd-1.5.7.tar.gz').read_bytes()))
(corpus/'zeros.bin').write_bytes(bytes(4*1024*1024))
(corpus/'sha256-counter.bin').write_bytes(b''.join(hashlib.sha256(b'zstd-compiler-v1:'+i.to_bytes(8,'big')).digest() for i in range(131072)))
(corpus/'empty.bin').write_bytes(b'')
(corpus/'tiny.bin').write_bytes(bytes(range(256))+b'zstd\x00\xff')
manifest={f.name:{'bytes':f.stat().st_size,'sha256':hashlib.sha256(f.read_bytes()).hexdigest()} for f in sorted(corpus.iterdir()) if f.name in ('source.tar','zeros.bin','sha256-counter.bin','empty.bin','tiny.bin')}
(corpus/'manifest.json').write_text(json.dumps(manifest,indent=2)+'\n')
(corpus/'SHA256SUMS').write_text(''.join(v['sha256']+'  '+k+'\n' for k,v in manifest.items()))
bins=sorted((p/'bin').glob('zstd-*'))+[pathlib.Path('/usr/bin/zstd')]
checks=0

def run(cmd,data=None,ok=True):
 global checks
 r=subprocess.run([str(x) for x in cmd],input=data,stdout=subprocess.PIPE,stderr=subprocess.PIPE)
 assert (r.returncode==0)==ok,(cmd,r.returncode,r.stderr.decode(errors='replace'))
 checks+=1
 return r.stdout

for name in manifest:
 data=(corpus/name).read_bytes()
 for level in (1,3,9):
  frames=[]
  for b in bins:
   frame=run([b,'--single-thread','--check',f'-{level}','-c'],data)
   frames.append(frame)
   for decoder in bins:
    assert run([decoder,'-d','-c'],frame)==data
   run([b,'-t'],frame)
   run([b,'-t'],frame[:-1],ok=False)
   damaged=bytearray(frame); damaged[-1]^=128
   run([b,'-t'],damaged,ok=False)
  assert len(set(frames))==1,('different frames',name,level)
 print('PASS cross-decode, stock equality, checksum/truncation:',name,flush=True)
# High level exercises a different match finder without a large RAM workload.
data=(corpus/'source.tar').read_bytes()[:262144]
for b in bins:
 frame=run([b,'--single-thread','-19','-c'],data)
 assert run(['/usr/bin/zstd','-dc'],frame)==data
# Concatenated frames and dictionary mode (raw dictionary deliberately fixed).
dictfile=p/'tmp/raw-dictionary.bin'; dictfile.write_bytes(data[:8192])
for b in bins:
 f=run([b,'--single-thread','-3','-c','-D',dictfile],data)
 for decoder in bins:
  assert run([decoder,'-dc','-D',dictfile],f)==data
 f=run([b,'--single-thread','-c'],b'first')+run([b,'--single-thread','-c'],b'second')
 assert run([b,'-dc'],f)==b'firstsecond'
# All actual compile inputs must carry exactly the requested ISA and optimization.
import shlex
for variant,opt,tune in [('armv8-o2','-O2',None),('a72-tune-o2','-O2','-mtune=cortex-a72'),('armv8-o3','-O3',None)]:
 lines=(p/f'logs/{variant}.commands').read_text().splitlines()
 compiled=[shlex.split(s) for s in lines if ' -c ' in s]
 assert compiled
 for args in compiled:
  assert set(a for a in args if a.startswith('-O'))=={opt},args
  assert set(a for a in args if a.startswith('-march='))=={'-march=armv8-a'},args
  assert set(a for a in args if a.startswith('-mtune='))==({tune} if tune else set()),args
  assert not any(a.startswith('-mcpu=') or a=='-flto' for a in args)
 print('PASS actual compiler argv:',variant,len(compiled),'compile calls (including probes)',flush=True)
print('PASS',checks,'CLI invocations; no throughput measurement')
ZSTD_CORRECTNESS_PY
  cat >"$out/parent-benchmark.sh" <<'ZSTD_PARENT_BENCH'
#!/bin/bash
# Parent only, on the physical Pi. Run from the artifact directory after review.
# No settings are changed. Stop this script if session contention or health is poor.
set -euo pipefail
[[ $(pacman -Q zstd) == "zstd 1.5.7-3" ]]
sha256sum -c bin/SHA256SUMS
(cd corpus && sha256sum -c SHA256SUMS)
mkdir -p parent-results
out="parent-results/$(date -u +%Y%m%dT%H%M%SZ)"
mkdir "$out"
{
  pacman -Q zstd glibc
  /usr/bin/zstd -vvV
  sha256sum /usr/bin/zstd
  for b in bin/zstd-*; do "$b" -vvV; ldd "$b"; done
  cat /proc/sys/kernel/random/boot_id
} >"$out/provenance.txt" 2>&1
bins=(bin/zstd-armv8-o2 bin/zstd-a72-tune-o2 bin/zstd-armv8-o3 /usr/bin/zstd)
# Eight blocks, alternating order, each variant at every level and corpus.
for block in 0 1 2 3 4 5 6 7; do
  if (( block % 2 == 0 )); then order=(0 1 2 3); else order=(3 2 1 0); fi
  for idx in "${order[@]}"; do
    b=${bins[$idx]}
    for corpus in source.tar zeros.bin sha256-counter.bin; do
      for level in 1 3 9; do
        name="$block-$idx-$corpus-$level"
        # Parent must use matching telemetry alongside this run. This is a stop gate.
        temp=$(cat /sys/class/thermal/thermal_zone0/temp)
        (( temp < 55000 )) || { echo "Cool board and start a new full run"; exit 1; }
        for alarm in /sys/class/hwmon/hwmon*/in*_alarm; do
          if [[ -f $alarm ]]; then [[ $(cat "$alarm") == "0" ]]; fi
        done
        { date -u; cat /proc/loadavg; cat /sys/devices/system/cpu/cpufreq/policy0/{scaling_governor,scaling_cur_freq}; echo "temp_mC=$temp"; } >"$out/$name.before"
        # Explicit single thread avoids upstream v1.5.7's automatic worker count.
        taskset -c "${BENCH_CPU:-2}" "$b" --single-thread -b"$level" -i3 "corpus/$corpus" >"$out/$name.log" 2>&1
        cat /sys/class/thermal/thermal_zone0/temp >"$out/$name.after-temp"
      done
    done
  done
done
ZSTD_PARENT_BENCH
  expected=eb33e51f49a15e023950cd7825ca74a4a2b43db8354825ac24fc1b7ee09e6fa3
  if [[ ! -f $out/source/zstd-1.5.7.tar.gz ]]; then
    curl -fL --connect-timeout 15 --max-time 120 -H 'Accept: application/octet-stream' https://api.github.com/repos/meta/zstd/releases/assets/230758919 -o "$out/source/zstd-1.5.7.tar.gz"
  fi
  printf '%s  %s\n' "$expected" "$out/source/zstd-1.5.7.tar.gz" | shasum -a 256 -c -
  image=sha256:3862c9a52166b7310e7de0b08131f4e69fbd0cbebba29c9510bf3085908417bd
  docker image inspect "$image" >"$out/image-inspect.json"
  # No other substantive build should run in this lane at the same time.
  docker run --name zstd-compiler-candidates --network none --cpus 1 --memory 768m --memory-swap 768m --pids-limit 128 --user 1000:1000 --entrypoint /bin/bash -e TMPDIR=/work/tmp -v "$out:/work" -v "$repo/tools/pi-experiments/build-zstd-candidates.sh:/experiment.sh:ro" "$image" /experiment.sh --inner >"$out/container.log" 2>&1
  docker inspect zstd-compiler-candidates >"$out/container-inspect.json"
  docker rm zstd-compiler-candidates >/dev/null
else
  cd /work
  mkdir -p tmp bin logs variants corpus
  export LC_ALL=C TZ=UTC SOURCE_DATE_EPOCH=1740000000
  unset CFLAGS CPPFLAGS CXXFLAGS LDFLAGS MAKEFLAGS
  { id; gcc -v; ld --version; make --version; pacman -Q gcc glibc binutils make zstd; cat /sys/fs/cgroup/{cpu.max,memory.max,memory.swap.max}; df -T /work /work/tmp; } >logs/toolchain.txt 2>&1
  sha256sum source/zstd-1.5.7.tar.gz >source/SHA256SUMS
  # Exact GCC argv are logged before each real invocation, including probes.
  cat > /work/cc-record <<'WRAPPER'
#!/bin/bash
set -euo pipefail
printf '%q ' /usr/bin/gcc "$@" >>"$CC_LOG"
printf '\n' >>"$CC_LOG"
/usr/bin/gcc "$@"
WRAPPER
  chmod +x /work/cc-record
  tar -xzf source/zstd-1.5.7.tar.gz -C source
  make -n -C source/zstd-1.5.7/programs zstd-release HAVE_ZLIB=0 HAVE_LZMA=0 HAVE_LZ4=0 >logs/upstream-default-dry-run.txt 2>&1
  for variant in armv8-o2 a72-tune-o2 armv8-o3; do
    case $variant in
      armv8-o2) flags='-march=armv8-a -O2' ;;
      a72-tune-o2) flags='-march=armv8-a -mtune=cortex-a72 -O2' ;;
      armv8-o3) flags='-march=armv8-a -O3' ;;
    esac
    flags="$flags -g0 -fno-lto -frecord-gcc-switches"
    [[ ! -e variants/$variant ]] || { echo "Refusing existing variant $variant"; exit 1; }
    mkdir "variants/$variant"
    tar -xzf source/zstd-1.5.7.tar.gz -C "variants/$variant" --strip-components=1
    export CC_LOG="/work/logs/$variant.commands"
    gcc $flags -Q --help=target >"logs/$variant.target.txt"
    printf '#include "portability_macros.h"\n' | gcc $flags -I source/zstd-1.5.7/lib/common -dM -E - >"logs/$variant.macros.txt"
    make -j1 -C "variants/$variant/programs" zstd-release CC=/work/cc-record CFLAGS="$flags" HAVE_ZLIB=0 HAVE_LZMA=0 HAVE_LZ4=0 V=1 >"logs/$variant.build.txt" 2>&1
    cp "variants/$variant/programs/zstd" "bin/zstd-$variant"
    { "bin/zstd-$variant" -vvV; size "bin/zstd-$variant"; readelf -h -d -n "bin/zstd-$variant"; readelf --version-info "bin/zstd-$variant"; readelf -p .GCC.command.line "bin/zstd-$variant"; ldd "bin/zstd-$variant"; } >"logs/$variant.binary.txt" 2>&1
  done
  sha256sum bin/* >bin/SHA256SUMS
  stat -c '%n %s' bin/zstd-* >logs/file-sizes.txt
  python /work/correctness.py >logs/correctness.txt 2>&1
  cat /sys/fs/cgroup/{memory.peak,memory.events,cpu.stat} >logs/resource-final.txt
fi
