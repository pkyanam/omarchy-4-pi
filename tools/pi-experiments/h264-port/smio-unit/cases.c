struct send_args { struct sm_instance *s; int ret; bool interrupt; };
static void *send_import(void *p) { struct send_args *a=p; struct vc_sm_import msg={0};struct vc_sm_import_result result;interrupt_wait=a->interrupt;a->ret=vc_sm_cma_vchi_import(a->s,&msg,&result,NULL);return NULL; }
static void reset(void) { assert(!allocations);assert(!workers);atomic_store(&join_started,false);queued=0;closed=false;block_queue=false;queue_error=0;open_error=0; }
static void wait_queued(int n) { pthread_mutex_lock(&gate);while(queued<n)pthread_cond_wait(&changed,&gate);pthread_mutex_unlock(&gate); }
int main(void) {
 struct vchiq_instance v={0};struct sm_instance *s;
 reset();fail_alloc=1;assert(!vc_sm_cma_vchi_init(&v,1,NULL));assert(!allocations);puts("PASS instance allocation failure");
 reset();open_error=-EIO;assert(!vc_sm_cma_vchi_init(&v,1,NULL));assert(!allocations);puts("PASS service-open failure (transport boundary injected)");
 reset();fail_thread=1;assert(!vc_sm_cma_vchi_init(&v,1,NULL));assert(!allocations);puts("PASS thread-create failure");
 reset();s=vc_sm_cma_vchi_init(&v,1,NULL);assert(s);assert(!vc_sm_cma_vchi_stop(&v,&s));assert(!s);puts("PASS idle worker stop joins actual production worker");
 reset();s=vc_sm_cma_vchi_init(&v,1,NULL);block_queue=true;
 struct send_args a={.s=s};pthread_t t;pthread_create(&t,NULL,send_import,&a);wait_queued(1);
 close_error=-EAGAIN;assert(vc_sm_cma_vchi_stop(&v,&s)==-EAGAIN);assert(s);
 struct vc_sm_import msg={0};struct vc_sm_import_result result;
 assert(vc_sm_cma_vchi_import(s,&msg,&result,NULL)==-ESHUTDOWN);
 assert(!vc_sm_cma_vchi_stop(&v,&s));pthread_join(t,NULL);assert(a.ret==-ESHUTDOWN);assert(!allocations);puts("PASS blocked queue + outstanding IMPORT cancellation, close interruption/retry, admission closure");
 reset();s=vc_sm_cma_vchi_init(&v,1,NULL);a=(struct send_args){.s=s,.interrupt=true};pthread_create(&t,NULL,send_import,&a);pthread_join(t,NULL);assert(a.ret==-EINTR);assert(!vc_sm_cma_vchi_stop(&v,&s));assert(!allocations);puts("PASS interrupted caller retains queued-command ownership until stop");
 reset();s=vc_sm_cma_vchi_init(&v,1,NULL);queue_error=-EIO;a=(struct send_args){.s=s};pthread_create(&t,NULL,send_import,&a);pthread_join(t,NULL);assert(a.ret==-EIO);assert(!vc_sm_cma_vchi_stop(&v,&s));assert(!allocations);puts("PASS queue error propagates without fabricated IMPORT result");
 reset();s=vc_sm_cma_vchi_init(&v,1,NULL);a=(struct send_args){.s=s};pthread_create(&t,NULL,send_import,&a);wait_queued(1);
 struct vc_sm_result_t reply={.trans_id=1,.success=0};vc_sm_cma_vchi_rx_ack(s,&reply,sizeof(reply));pthread_join(t,NULL);assert(!a.ret);assert(!vc_sm_cma_vchi_stop(&v,&s));assert(!allocations);puts("PASS production reply delivery then fresh service generation");
 reset();s=vc_sm_cma_vchi_init(&v,1,NULL);
 struct send_args many[40];pthread_t threads[40];
 for(int i=0;i<40;i++){many[i]=(struct send_args){.s=s};pthread_create(&threads[i],NULL,send_import,&many[i]);}
 wait_queued(40);assert(!vc_sm_cma_vchi_stop(&v,&s));
 for(int i=0;i<40;i++){pthread_join(threads[i],NULL);assert(many[i].ret==-ESHUTDOWN);}
 assert(!allocations);puts("PASS 40 outstanding production IMPORT requests drain without command-pool deadlock");
 reset();s=vc_sm_cma_vchi_init(&v,1,NULL);struct vc_sm_free_t f={0};assert(!vc_sm_cma_vchi_free(s,&f,NULL));assert(!vc_sm_cma_vchi_stop(&v,&s));assert(!allocations);puts("PASS fire-and-forget FREE command ownership (not firmware RELEASED ownership)");
 reset();s=vc_sm_cma_vchi_init(&v,1,NULL);fail_alloc=1;assert(vc_sm_cma_vchi_import(s,&msg,&result,NULL)==-ENOMEM);assert(!vc_sm_cma_vchi_stop(&v,&s));assert(!allocations);puts("PASS command allocation failure releases instance reference");
 reset();puts("All SMIO implementation cases passed; NOT VCSM dma-buf/remove/reprobe proof");return 0;
}
