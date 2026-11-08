static struct vchiq_state state;
static struct vchiq_service service;
static struct vchiq_service_owner owner;
static struct vchiq_shared_state shared;
static atomic_bool done;
static void setup(void){
 memset(&state,0,sizeof(state));memset(&service,0,sizeof(service));memset(&owner,0,sizeof(owner));
 state.local=state.remote=&shared;state.service=&service;state.slot_handler_thread=(void*)2;
 mutex_init(&state.slot_mutex);mutex_init(&state.sync_mutex);init_completion(&state.connect);
 service.state=&state;service.owner=&owner;service.srvstate=VCHIQ_SRVSTATE_OPENING;service.localport=1;service.ref_count.n=2;
 spin_lock_init(&service.owned_remove_lock);init_completion(&service.remove_event);mutex_init(&service.bulk_mutex);
 owner.service=&service;init_completion(&owner.retired);init_completion(&owner.released);
 close_sends=open_sends=callbacks=released_sync=queue_error=0;atomic_store(&done,false);
}
static void teardown(void){
 pthread_mutex_destroy(&state.slot_mutex.m);pthread_mutex_destroy(&state.sync_mutex.m);pthread_mutex_destroy(&service.bulk_mutex.m);pthread_mutex_destroy(&service.owned_remove_lock);
 struct completion *cs[]={&state.connect,&service.remove_event,&owner.retired,&owner.released};
 for(unsigned i=0;i<sizeof(cs)/sizeof(cs[0]);i++){pthread_mutex_destroy(&cs[i]->m);pthread_cond_destroy(&cs[i]->c);}
}
static void *remove_owner(void *p){vchiq_remove_service_sync(&owner);atomic_store(&done,true);return NULL;}
static pthread_t begin_remove(void){pthread_t t;assert(!pthread_create(&t,NULL,remove_owner,NULL));
 while(!atomic_load(&service.poll_flags))sched_yield();
 return t;
}
static void poll_remove(void){poll_services_of_group(&state,0);}
static void receive(int type,bool sync){
 struct vchiq_header h={.msgid=(type<<TYPE_SHIFT)|(7<<12)|1,.size=0};
 if(sync){state.sync_header=h;sync_once=false;assert(!sync_func(&state));}
 else assert(parse_message(&state,&h)==0);
}
static void finish(pthread_t t){pthread_join(t,NULL);assert(atomic_load(&done));assert(service.srvstate==VCHIQ_SRVSTATE_FREE);assert(service.service_use_count==0);assert(service.ref_count.n==0);assert(!owner.service);teardown();}
static void interrupted_open(void){interrupt_wait=true;assert(vchiq_open_service_internal(&service,42)==-EAGAIN);interrupt_wait=false;assert(open_sends==1);assert(service.service_use_count==0);}
static void *successful_open(void *p){assert(!vchiq_open_service_internal(&service,42));return NULL;}
int main(void){
 // Actual queue_message commits CLOSESENT: late rejection then completes close.
 setup();interrupted_open();pthread_t t=begin_remove();poll_remove();assert(close_sends==1);assert(service.srvstate==VCHIQ_SRVSTATE_CLOSESENT);assert(!atomic_load(&done));assert(!atomic_load(&service.poll_flags));
 receive(VCHIQ_MSG_CLOSE,false);assert(callbacks==1);finish(t);
 // Both parser paths: late ACK after CLOSESENT is ignored; peer CLOSE retires.
 for(int sync=0;sync<2;sync++){
 setup();interrupted_open();t=begin_remove();poll_remove();receive(VCHIQ_MSG_OPENACK,sync);
 assert(service.srvstate==VCHIQ_SRVSTATE_CLOSESENT);assert(!atomic_load(&done));assert(!atomic_load(&service.poll_flags));
 assert(close_sends==1);receive(VCHIQ_MSG_CLOSE,false);assert(callbacks==1);finish(t);
 }
 // Rejection before REMOVE: CLOSEWAIT is retired by the initial poll.
 setup();interrupted_open();receive(VCHIQ_MSG_CLOSE,false);assert(service.srvstate==VCHIQ_SRVSTATE_CLOSEWAIT);t=begin_remove();poll_remove();assert(close_sends==0);finish(t);
 // ACK before REMOVE: OPEN/OPENSYNC takes the normal CLOSE handshake.
 for(int sync=0;sync<2;sync++){
 setup();interrupted_open();receive(VCHIQ_MSG_OPENACK,sync);assert(service.srvstate==(sync?VCHIQ_SRVSTATE_OPENSYNC:VCHIQ_SRVSTATE_OPEN));t=begin_remove();poll_remove();assert(service.srvstate==VCHIQ_SRVSTATE_CLOSESENT);assert(close_sends==1);receive(VCHIQ_MSG_CLOSE,false);finish(t);
 }
 // Failed OPEN enqueue has no wire peer. Retire without inventing a CLOSE reply.
 setup();queue_error=1;assert(vchiq_open_service_internal(&service,42)==-EAGAIN);assert(open_sends==0);assert(service.service_use_count==0);assert(service.srvstate==VCHIQ_SRVSTATE_CLOSED);queue_error=0;t=begin_remove();poll_remove();assert(close_sends==0);finish(t);
 // A successful OPEN's use remains until the actual close-complete drain.
 setup();pthread_t opener;assert(!pthread_create(&opener,NULL,successful_open,NULL));while(!atomic_load(&open_sends))sched_yield();receive(VCHIQ_MSG_OPENACK,false);pthread_join(opener,NULL);assert(service.service_use_count==1);t=begin_remove();poll_remove();receive(VCHIQ_MSG_CLOSE,false);finish(t);
 // CLOSE enqueue failure is requeued by the actual poll implementation.
 setup();interrupted_open();t=begin_remove();queue_error=1;poll_remove();assert(service.srvstate==VCHIQ_SRVSTATE_OPENING);assert(atomic_load(&service.poll_flags)&BIT(VCHIQ_POLL_REMOVE));queue_error=0;poll_remove();assert(service.srvstate==VCHIQ_SRVSTATE_CLOSESENT);receive(VCHIQ_MSG_CLOSE,false);finish(t);
 puts("PASS: production queue/OPEN/full parser/full sync/poll/close/removal; delayed ACK/CLOSE and unsent OPEN accounting");return 0;
}
