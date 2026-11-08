from pathlib import Path
import re,subprocess,sys
r=Path(__file__).resolve().parents[1];u=r/'buffer-unit';s=r/sys.argv[1];out=u/sys.argv[2];out.mkdir(exist_ok=False)
t=(s/'drivers/platform/raspberrypi/vc-sm-cma/vc_sm.c').read_text()
def fn(n):
 m=re.search(r'(?m)^[\w *]*\b'+n+r'\([^;{]*\)\s*\{',t);assert m,n
 a=t.index('{',m.start());b=a+1;d=1
 while d:d+=(t[b]=='{')-(t[b]=='}');b+=1
 return ('static void\n' if n=='vc_sm_vpu_event' else '')+t[m.start():b]+'\n'
code=(u/'shim.c').read_text()
h=(s/'drivers/platform/raspberrypi/vc-sm-cma/vc_sm.h').read_text();code+=h[h.index('enum vc_sm_vpu_mapping_state'):h.index('\n#endif')]
code+=(u/'boundaries.c').read_text()
for n in ['vc_sm_buffer_init','vc_sm_buffer_destroy','get_kernel_id','free_kernel_id','vc_sm_add_resource','vc_sm_clean_up_dmabuf','vc_sm_vpu_free','vc_sm_release_resource','vc_sm_dma_buf_release','vc_sm_vpu_event','bcm2835_vc_sm_cma_remove']:
 code+=fn(n)

if '--mutant-early-unmap' in sys.argv:
 code=code.replace('/* Unmap on the VPU */', 'vc_sm_clean_up_dmabuf(buffer); /* mutant */\n/* Unmap on the VPU */')
code+=(u/'cases.c').read_text();(out/'generated.c').write_text(code)
subprocess.run(['cc','-std=gnu11','-pthread','-Wall','-Wextra','-Werror','-Wno-unused-parameter','-Wno-unused-function','-Wno-unused-variable','-fsanitize=address,undefined','-fno-sanitize-recover=all','-g',str(out/'generated.c'),'-o',str(out/'test')],check=True)
subprocess.run([str(out/'test')],check=True,timeout=20)
