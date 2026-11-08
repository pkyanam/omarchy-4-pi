from pathlib import Path
import subprocess,sys
r=Path(__file__).resolve().parents[1];u=r/'import-unit';p=r/sys.argv[1]/'drivers/platform/raspberrypi/vc-sm-cma';o=u/sys.argv[2];o.mkdir()
shim=(r/'smio-unit/shim.c').read_text().replace('c->done--;','if(c->done!=UINT_MAX)c->done--;')
pos=shim.index('typedef struct { atomic_int n; } refcount_t;')
shim=shim[:pos]+'''static atomic_int sync_waiters;
static void wait_for_completion(struct completion *c){atomic_fetch_add(&sync_waiters,1);bool old=interrupt_wait;interrupt_wait=false;assert(!wait_for_completion_interruptible(c));interrupt_wait=old;}
static void complete_all(struct completion *c){pthread_mutex_lock(&c->m);c->done=UINT_MAX;pthread_cond_broadcast(&c->c);pthread_mutex_unlock(&c->m);}
'''+shim[pos:]
shim+='''\nstruct vchiq_service_owner {bool open;};
static int vchiq_open_service_owned(struct vchiq_instance *v,struct vchiq_service_params_kernel *p,unsigned *h,struct vchiq_service_owner *o){int e=vchiq_open_service(v,p,h);o->open=!e;return e;}
static void vchiq_remove_service_sync(struct vchiq_service_owner *o){if(o->open){assert(!vchiq_close_service(NULL,1));o->open=false;}}
'''
def strip(s):return '\n'.join(l for l in s.splitlines() if not l.startswith('#include'))
code=shim+'\n'+strip((p/'vc_sm_defs.h').read_text())+'\n'+strip((p/'vc_sm_cma_vchi.h').read_text())+'\n'+strip((p/'vc_sm_cma_vchi.c').read_text())+'\n'+(u/'smio-cases.c').read_text()
if '--mutant-interrupt' in sys.argv:code=code.replace('if (import_done) {','if (false) {')
(o/'generated.c').write_text(code)
subprocess.run(['cc','-std=gnu11','-pthread','-Wall','-Wextra','-Werror','-Wno-unused-parameter','-Wno-unused-function','-fsanitize=address,undefined','-fno-sanitize-recover=all','-g',str(o/'generated.c'),'-o',str(o/'test')],check=True)
subprocess.run([str(o/'test')],check=True,timeout=15)
