from pathlib import Path
import subprocess,sys
r=Path(__file__).resolve().parents[1];unit=r/'smio-unit'
source=r/(sys.argv[1] if len(sys.argv)>1 else 'replayed-smio-01')/'drivers/platform/raspberrypi/vc-sm-cma'
def strip(s):return '\n'.join(l for l in s.splitlines() if not l.startswith('#include'))
s=(unit/'shim.c').read_text()+'\n'+strip((source/'vc_sm_defs.h').read_text())+'\n'+strip((source/'vc_sm_cma_vchi.h').read_text())+'\n'+strip((source/'vc_sm_cma_vchi.c').read_text())+'\n'+(unit/'cases.c').read_text()
mutant='--mutant-no-join' in sys.argv
if mutant: s=s.replace('kthread_stop(instance->io_thread);','if (0) kthread_stop(instance->io_thread); /* mutant */')
p=unit/('generated-smio-mutant.c' if mutant else 'generated-smio.c');p.write_text(s)
subprocess.run(['cc','-std=gnu11','-pthread','-Wall','-Wextra','-Werror','-Wno-unused-parameter','-fsanitize=address,undefined','-fno-sanitize-recover=all','-g',str(p),'-o',str(p.with_suffix(''))],check=True)
subprocess.run([str(p.with_suffix(''))],check=True,timeout=30)
