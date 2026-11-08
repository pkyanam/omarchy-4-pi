from pathlib import Path
import re,subprocess,sys
r=Path(__file__).resolve().parents[1];u=r/'import-unit';s=r/sys.argv[1];o=u/sys.argv[2];o.mkdir()
t=(s/'drivers/platform/raspberrypi/vc-sm-cma/vc_sm.c').read_text()
def fn(n):
 m=re.search(r'(?m)^[\w *]*\b'+n+r'\([^;{]*\)\s*\{',t);assert m,n
 a=t.index('{',m.start());b=a+1;d=1
 while d:d+=(t[b]=='{')-(t[b]=='}');b+=1
 return ('static void\n' if n=='vc_sm_vpu_event' else 'static int\n' if n=='vc_sm_cma_import_dmabuf_internal' else '')+t[m.start():b]+'\n'
code=(r/'buffer-unit/shim.c').read_text().replace('struct sg_table { int dummy; };','struct scatterlist { int dummy; };\nstruct sg_table { int nents; struct scatterlist *sgl; };')
code+=(u/'producer-shim.c').read_text()
h=(s/'drivers/platform/raspberrypi/vc-sm-cma/vc_sm.h').read_text();code+=h[h.index('enum vc_sm_vpu_mapping_state'):h.index('\n#endif')]
code+=(r/'buffer-unit/boundaries.c').read_text()
code+=(u/'producer-boundaries.c').read_text()
for n in ['vc_sm_buffer_init','vc_sm_buffer_destroy','get_kernel_id','free_kernel_id','vc_sm_add_resource','vc_sm_clean_up_dmabuf','vc_sm_vpu_free','vc_sm_release_resource','vc_sm_dma_buf_release','vc_sm_import_done','vc_sm_import_unpublish','vc_sm_import_abort','vc_sm_import_finish','vc_sm_cma_import_dmabuf_internal','vc_sm_cma_ioctl_alloc','vc_sm_vpu_event','bcm2835_vc_sm_cma_remove']:code+=fn(n)

if '--mutant-no-setup' in sys.argv:code=code.replace('buffer->in_use || buffer->setup_pending','buffer->in_use')
if '--mutant-early-free' in sys.argv:code=code.replace('buffer->in_use = false;', 'buffer->vc_handle = 0; buffer->in_use = false;')
code+=(u/'producer-cases.c').read_text();(o/'generated.c').write_text(code)
subprocess.run(['cc','-std=gnu11','-pthread','-Wall','-Wextra','-Werror','-Wno-unused-parameter','-Wno-unused-function','-Wno-unused-variable','-fsanitize=address,undefined','-fno-sanitize-recover=all','-g',str(o/'generated.c'),'-o',str(o/'test')],check=True)
subprocess.run([str(o/'test')],check=True,timeout=20)
