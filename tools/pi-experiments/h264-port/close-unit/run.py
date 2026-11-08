from pathlib import Path
import subprocess,sys,re
r=Path(__file__).resolve().parents[1];u=r/'close-unit';s=r/(sys.argv[1] if len(sys.argv)>1 else 'replayed-close-01')
def body(file,name):
 t=(s/file).read_text();i=re.search(r'(?m)^(?:[a-zA-Z_][a-zA-Z_ *]*[ *])?'+name+r'\(',t).start();a=t.index('{',i);n=1;b=a+1
 while n:
  n+=(t[b]=='{')-(t[b]=='}');b+=1
 # Include signature starting at preceding empty line (or standalone return type).
 start=t.rfind('\n\n',0,i)+2
 return t[start:b]+'\n'
c='drivers/platform/raspberrypi/vchiq-interface/vchiq_core.c';a='drivers/platform/raspberrypi/vchiq-interface/vchiq_arm.c'
shim=(r/'smio-unit/shim.c').read_text();shim=shim[:shim.index('struct vchiq_instance {')].replace('struct task_struct { pthread_t t;', 'struct task_struct { int pid; pthread_t t;')+(u/'transport.c').read_text()
names=['service_release','vchiq_service_put','vchiq_service_get','handle_to_service','find_service_by_handle','vchiq_validate_params','vchiq_add_service_internal_owned','vchiq_free_service_internal','vchiq_close_service','vchiq_remove_service_sync']
code=shim+'\n'+''.join(body(c,n) for n in names)+body(a,'vchiq_open_service_owned')+(u/'boundary.c').read_text()
def strip(t):return '\n'.join(l for l in t.splitlines() if not l.startswith('#include'))
p=s/'drivers/platform/raspberrypi/vc-sm-cma'
code+='\n'+strip((p/'vc_sm_defs.h').read_text())+'\n'+strip((p/'vc_sm_cma_vchi.h').read_text())+'\n'+strip((p/'vc_sm_cma_vchi.c').read_text())+'\n'+(u/'cases.c').read_text()
if '--mutant-no-drain' in sys.argv:code=code.replace('wait_for_completion(&owner->released);','/* mutant: missing final reference drain */')
f=u/('generated-mutant.c' if '--mutant-no-drain' in sys.argv else 'generated.c');f.write_text(code)
subprocess.run(['cc','-std=gnu11','-pthread','-Wall','-Wextra','-Werror','-Wno-unused-parameter','-Wno-unused-function','-fsanitize=address,undefined','-fno-sanitize-recover=all','-g',str(f),'-o',str(f.with_suffix(''))],check=True)
subprocess.run([str(f.with_suffix(''))],check=True,timeout=30)
