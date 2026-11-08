from pathlib import Path
import re,subprocess,sys
r=Path(__file__).resolve().parents[1];u=r/'owner-unit';s=r/sys.argv[1];out=u/sys.argv[2];out.mkdir(exist_ok=False)
t=(s/'drivers/platform/raspberrypi/vc-sm-cma/vc_sm.c').read_text()
def function(n):
 m=re.search(r'(?m)^[\w *]*\b'+n+r'\(',t);assert m,n
 a=t.index('{',m.start());b=a+1;depth=1
 while depth:depth+=(t[b]=='{')-(t[b]=='}');b+=1
 return t[m.start():b]+'\n'
code=(u/'shim.c').read_text()
for start,end in [('struct vc_sm_generation {','typedef int (*VC_SM_SHOW)'),('typedef int (*VC_SM_SHOW)', 'struct vc_sm_dma_buf_attachment {')]:
 code+=t[t.index(start):t.index(end)]
code+='static struct sm_state_t *sm_state;\nstatic DEFINE_MUTEX(sm_admission_lock);\n'
for n in ['vc_sm_generation_release','vc_sm_generation_put','vc_sm_file_ready','vc_sm_connect','vc_sm_cma_create_priv_data','vc_sm_cma_open','vc_sm_cma_release','vc_sm_cma_ioctl','vc_sm_connected_init','bcm2835_vc_sm_cma_probe','bcm2835_vc_sm_cma_remove']:
 code+=function(n)
if '--mutant-ready' in sys.argv:
 code=code.replace('state->generation->ready = false;', '/* mutant: admission left open */')
code+=(u/'cases.c').read_text()
(out/'generated.c').write_text(code)
subprocess.run(['cc','-std=gnu11','-pthread','-Wall','-Wextra','-Werror','-Wno-unused-parameter','-Wno-unused-function','-Wno-unused-variable','-fsanitize=address,undefined','-fno-sanitize-recover=all','-g',str(out/'generated.c'),'-o',str(out/'test')],check=True)
subprocess.run([str(out/'test')],check=True,timeout=20)
