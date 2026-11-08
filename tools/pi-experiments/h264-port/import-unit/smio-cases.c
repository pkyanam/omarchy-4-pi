struct args {struct sm_instance *s;int ret;u32 handle;atomic_bool returned;};
static void done(void *p,u32 h){((struct args *)p)->handle=h;}
static void *send(void *p){struct args *a=p;struct vc_sm_import m={0};struct vc_sm_import_result r={0};interrupt_wait=true;a->ret=vc_sm_cma_vchi_import(a->s,&m,&r,NULL,done,a);if(!a->ret)assert(r.res_handle==a->handle);atomic_store(&a->returned,true);return NULL;}
static void *stop(void *p){struct sm_instance **s=p;vc_sm_cma_vchi_stop(NULL,s);return NULL;}
static void wait_queued(int n){pthread_mutex_lock(&gate);while(queued<n)pthread_cond_wait(&changed,&gate);pthread_mutex_unlock(&gate);}
static void reset(void){assert(!allocations&&!workers);closed=false;queued=0;queue_error=0;atomic_store(&sync_waiters,0);}
int main(void){struct vchiq_instance v={0};pthread_t t,st;
 reset();struct sm_instance *s=vc_sm_cma_vchi_init(&v,1,NULL,NULL);struct args a={.s=s};pthread_create(&t,0,send,&a);wait_queued(1);while(!atomic_load(&sync_waiters))sched_yield();assert(!atomic_load(&a.returned));
 struct vc_sm_import_result r={.trans_id=1,.res_handle=77};vc_sm_cma_vchi_rx_ack(s,(void *)&r,sizeof(r)-1);vc_sm_cma_vchi_rx_ack(s,(void *)&r,sizeof(r)+1);assert(!atomic_load(&a.returned)&&!a.handle);
 /* Teardown must not close the service to synthesize failure. Both waits
  * resolve from the same definitive reply, including a signalled caller. */
 pthread_create(&st,0,stop,&s);while(atomic_load(&sync_waiters)<2)sched_yield();pthread_mutex_lock(&gate);assert(!closed);pthread_mutex_unlock(&gate);vc_sm_cma_vchi_rx_ack(a.s,(void *)&r,sizeof(r));pthread_join(t,0);pthread_join(st,0);assert(!a.ret&&a.handle==77&&!s);reset();
 s=vc_sm_cma_vchi_init(&v,1,NULL,NULL);a=(struct args){.s=s};pthread_create(&t,0,send,&a);wait_queued(1);r.res_handle=0;vc_sm_cma_vchi_rx_ack(s,(void *)&r,sizeof(r));pthread_join(t,0);assert(!a.ret&&!a.handle);vc_sm_cma_vchi_rx_ack(s,(void *)&r,sizeof(r));r.res_handle=88;vc_sm_cma_vchi_rx_ack(s,(void *)&r,sizeof(r));assert(!a.handle);vc_sm_cma_vchi_stop(&v,&s);reset();
 s=vc_sm_cma_vchi_init(&v,1,NULL,NULL);queue_error=-EIO;a=(struct args){.s=s};pthread_create(&t,0,send,&a);pthread_join(t,0);assert(a.ret==-EIO&&!a.handle);vc_sm_cma_vchi_stop(&v,&s);reset();
 s=vc_sm_cma_vchi_init(&v,1,NULL,NULL);s->trans_id=0x7fffffff;a=(struct args){.s=s};send(&a);assert(a.ret==-ENOSPC&&!queued);vc_sm_cma_vchi_stop(&v,&s);reset();
 puts("PASS actual SMIO sender/worker/ack/stop: signalled IMPORT retained, malformed ignored, definitive reply before close, dual completion, rejection, duplicate/late reply, nonpublication, ID exhaustion");return 0;}
