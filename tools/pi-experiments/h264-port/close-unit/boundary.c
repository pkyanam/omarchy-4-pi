/* Slot scheduling/OPEN exchange are injected, not a substitute close lifecycle.
 * This boundary owns the same reference a slot/sync handler owns across callback.
 */
static void mark_service_closing(struct vchiq_service *s){pthread_mutex_lock(&gate);closed=true;pthread_cond_broadcast(&changed);pthread_mutex_unlock(&gate);}
static void *remove_slot(void *p){struct vchiq_service *s=p;
 if(atomic_load(&hold_callback)){atomic_store(&callback_entered,true);while(!atomic_load(&allow_callback))sched_yield();}
 s->base.callback(s->instance,VCHIQ_SERVICE_CLOSED,NULL,s->handle,NULL,NULL);
 atomic_fetch_add(&callback_count,1);
 set_service_state(s,VCHIQ_SRVSTATE_CLOSED);vchiq_free_service_internal(s);vchiq_service_put(s);atomic_fetch_sub(&removal_threads,1);return NULL;}
static void request_poll(struct vchiq_state *state,struct vchiq_service *s,int type){
 vchiq_service_get(s);atomic_fetch_add(&removal_threads,1);pthread_t t;pthread_create(&t,NULL,remove_slot,s);pthread_detach(t);
}
static int vchiq_open_service_internal(struct vchiq_service *s,int pid){
 service_userdata=s->base.userdata;open_count++;if(open_error || open_count==fail_open_number)return open_error?open_error:-EIO;set_service_state(s,VCHIQ_SRVSTATE_OPEN);return 0;
}
static int vchiq_queue_kernel_message(struct vchiq_instance *v,unsigned h,void *p,unsigned n){pthread_mutex_lock(&gate);queued++;pthread_cond_broadcast(&changed);while(block_queue&&!closed)pthread_cond_wait(&changed,&gate);while(block_queue&&closed&&!atomic_load(&join_started)){pthread_mutex_unlock(&gate);sched_yield();pthread_mutex_lock(&gate);}int e=closed?-ESHUTDOWN:queue_error;pthread_mutex_unlock(&gate);return e;}
static int vchiq_release_service(struct vchiq_instance *v,unsigned h){return 0;}
static int vchiq_use_service(struct vchiq_instance *v,unsigned h){return 0;}
static struct vchiq_header *vchiq_msg_hold(struct vchiq_instance *v,unsigned h){return NULL;}
static void vchiq_release_message(struct vchiq_instance *v,unsigned h,struct vchiq_header *p){}
static void *vchiq_get_service_userdata(struct vchiq_instance *v,unsigned h){if(stall_callback){atomic_store(&callback_entered,true);while(!atomic_load(&allow_callback))sched_yield();}return service_userdata;}
static void vchiq_msg_queue_push(struct vchiq_instance *v,unsigned h,struct vchiq_header *p){}
