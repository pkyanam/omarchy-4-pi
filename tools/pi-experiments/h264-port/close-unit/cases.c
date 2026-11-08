struct send_args {struct sm_instance *s;int ret;};
static void *send_import(void *p){struct send_args *a=p;struct vc_sm_import m={0};struct vc_sm_import_result r;a->ret=vc_sm_cma_vchi_import(a->s,&m,&r,NULL);return NULL;}
struct stop_args {struct vchiq_instance *v;struct sm_instance **s;};
static void *stop(void *p){struct stop_args *a=p;assert(!vc_sm_cma_vchi_stop(a->v,a->s));atomic_store(&stop_done,true);return NULL;}
static void drain(void){while(atomic_load(&removal_threads))sched_yield();assert(!allocations);assert(!workers);}
static void reset(struct vchiq_instance *v,struct vchiq_state *state){drain();memset(state,0,sizeof(*state));mutex_init(&state->mutex);state->slot_handler_thread=(void *)1;v->state=state;release_wait_target=NULL;closed=false;queued=0;open_error=0;open_count=0;fail_open_number=0;block_queue=false;atomic_store(&join_started,false);atomic_store(&hold_callback,false);atomic_store(&callback_entered,false);atomic_store(&allow_callback,false);atomic_store(&stop_done,false);}
static void *held_callback(void *p){struct vchiq_service *s=p;stall_callback=true;s->base.callback(s->instance,VCHIQ_MESSAGE_AVAILABLE,NULL,s->handle,NULL,NULL);vchiq_service_put(s);return NULL;}
int main(void){struct vchiq_instance v;struct vchiq_state state;struct sm_instance *s;struct task_struct task={.pid=1};current_task=&task;
 reset(&v,&state);fail_alloc=1;assert(!vc_sm_cma_vchi_init(&v,1,NULL));drain();puts("PASS allocation failure");
 reset(&v,&state);open_error=-EAGAIN;assert(!vc_sm_cma_vchi_init(&v,1,NULL));drain();puts("PASS interrupted OPEN: actual owned-open error path + production constructor/removal/final release");
 reset(&v,&state);fail_open_number=2;assert(!vc_sm_cma_vchi_init(&v,2,NULL));drain();puts("PASS second OPEN fails: failed service and first service unwind drain before userdata free");
 reset(&v,&state);fail_thread=1;assert(!vc_sm_cma_vchi_init(&v,1,NULL));drain();puts("PASS worker-create failure drains opened service");
 reset(&v,&state);s=vc_sm_cma_vchi_init(&v,1,NULL);assert(s);
 struct vchiq_service *service=s->service_owner[0].service;
 /* A real production callback enters, retaining its handler's service ref. */
 vchiq_service_get(service);pthread_t cb;atomic_store(&callback_entered,false);atomic_store(&allow_callback,false);pthread_create(&cb,NULL,held_callback,service);while(!atomic_load(&callback_entered))sched_yield();
 /* Actual legacy close is interrupted; the transport slot boundary later
  * calls the production free function and retires the handle. */
 interrupt_wait=true;assert(vchiq_close_service(&v,service->handle)==-EAGAIN);interrupt_wait=false;
 wait_for_completion(&s->service_owner[0].retired);
 assert(!find_service_by_handle(&v,service->handle));assert(vchiq_close_service(&v,service->handle)==-EINVAL);
 release_wait_target=&s->service_owner[0].released;atomic_store(&release_wait_entered,false);
 pthread_t st;struct stop_args a={&v,&s};pthread_create(&st,NULL,stop,&a);
 /* Synchronize exactly when sync removal is waiting for final references. */
 while(!atomic_load(&release_wait_entered) && !atomic_load(&stop_done))sched_yield();assert(!atomic_load(&stop_done));
 atomic_store(&allow_callback,true);pthread_join(cb,NULL);pthread_join(st,NULL);assert(!s);drain();puts("PASS actual interrupted close -> later FREE -> invalid handle; owned stop waits concurrent production callback's reference");
 reset(&v,&state);s=vc_sm_cma_vchi_init(&v,1,NULL);assert(s);block_queue=true;
 struct send_args sender={s,0};pthread_t t;pthread_create(&t,NULL,send_import,&sender);pthread_mutex_lock(&gate);while(!queued)pthread_cond_wait(&changed,&gate);pthread_mutex_unlock(&gate);
 assert(!vc_sm_cma_vchi_stop(&v,&s));pthread_join(t,NULL);assert(sender.ret==-ESHUTDOWN);assert(!s);drain();puts("PASS blocked production queue/send cancellation and actual SMIO worker join");
 puts("NONDEPLOYABLE: injected slot scheduling/OPEN/queue; no firmware DMA, VCSM generation or hardware proof");return 0;
}
