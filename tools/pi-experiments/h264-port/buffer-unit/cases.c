static void dma_buf_put(struct dma_buf *b){assert(b->refs>0);if(!--b->refs){put_count++;if(b->exported)vc_sm_dma_buf_release(b);free(b);}}
static void state_init(struct sm_state_t *s,struct vchiq_device *d,struct sm_instance *i,struct vc_sm_generation *g){memset(s,0,sizeof(*s));s->device=d;s->sm_handle=i;s->generation=g;g->ready=true;d->dev.data=s;s->next_kernel_id=1;mutex_init(&s->kernelid_map_lock);mutex_init(&s->map_lock);mutex_init(&s->firmware_lock);INIT_LIST_HEAD(&s->buffer_list);pthread_mutex_init(&s->buffer_drain.lock,0);pthread_cond_init(&s->buffer_drain.cond,0);}
static void state_done(struct sm_state_t *s){mutex_destroy(&s->kernelid_map_lock);mutex_destroy(&s->firmware_lock);pthread_mutex_destroy(&s->buffer_drain.lock);pthread_cond_destroy(&s->buffer_drain.cond);}
static struct dma_buf *make_buffer(struct sm_state_t *s,int imported){struct vc_sm_buffer *b=calloc(1,sizeof(*b));vc_sm_buffer_init(b,s);mutex_init(&b->lock);b->vc_handle=77;b->in_use=true;b->vpu_state=VPU_MAPPED;b->size=4096;b->kernel_id=get_kernel_id(b);assert(b->kernel_id>0);b->imported=imported;if(imported){b->import.dma_buf=calloc(1,sizeof(struct dma_buf));b->import.dma_buf->refs=1;b->import.attach=calloc(1,sizeof(struct dma_buf_attachment));b->import.attach->mapped=1;b->import.sgt=calloc(1,sizeof(struct sg_table));}else b->cookie=malloc(4096);b->dma_buf=calloc(1,sizeof(struct dma_buf));b->dma_buf->refs=1;b->dma_buf->exported=true;b->dma_buf->priv=b;vc_sm_add_resource(NULL,b);return b->dma_buf;}
static void event(struct sm_state_t *s,int id,int h,int len){struct vc_sm_released r={.cmd=0x80000000|VC_SM_MSG_TYPE_RELEASED,.kernel_id=id,.vc_handle=h};vc_sm_vpu_event(s,s->sm_handle,(void *)&r,len);}
static void *remove_thread(void *d){bcm2835_vc_sm_cma_remove(d);return NULL;}
int main(void){
 struct sm_state_t old,new;struct vchiq_device od={0},nd={0};struct sm_instance oi={1},ni={2};struct vc_sm_generation og,ng;
 state_init(&old,&od,&oi,&og);state_init(&new,&nd,&ni,&ng);sm_state=&old;
 struct dma_buf *db=make_buffer(&old,1);int id=((struct vc_sm_buffer *)db->priv)->kernel_id;
 dma_buf_put(db);assert(frees==1&&last_service==&oi&&unmaps==0&&atomic_read(&old.live_buffers)==1);
 /* Change the selector: old events and FREE must stay in their own IDR. */
 sm_state=&new;struct dma_buf *nb=make_buffer(&new,0);assert(((struct vc_sm_buffer *)nb->priv)->kernel_id==id);
 event(&old,id,77,4);event(&old,id,78,sizeof(struct vc_sm_released));event(&old,INT_MAX,77,sizeof(struct vc_sm_released));assert(unmaps==0);
 event(&old,id,77,sizeof(struct vc_sm_released));assert(unmaps==1&&detaches==1&&atomic_read(&old.live_buffers)==0);assert(atomic_read(&new.live_buffers)==1);
 event(&old,id,77,sizeof(struct vc_sm_released));assert(unmaps==1);
 /* No ID reuse: stale event cannot retire the following buffer. */
 db=make_buffer(&old,1);int next=((struct vc_sm_buffer *)db->priv)->kernel_id;assert(next>id);dma_buf_put(db);event(&old,id,77,sizeof(struct vc_sm_released));assert(unmaps==1);event(&old,next,77,sizeof(struct vc_sm_released));assert(unmaps==2);
 /* Failed FREE is retained with original IDR/mapping, never acknowledged locally. */
 db=make_buffer(&old,1);next=((struct vc_sm_buffer *)db->priv)->kernel_id;free_status=-ENOMEM;dma_buf_put(db);free_status=0;assert(unmaps==2&&atomic_read(&old.live_buffers)==1);event(&old,next,77,sizeof(struct vc_sm_released));assert(unmaps==3);
 /* RELEASED while client still holds dma_buf: cleanup awaits last client. */
 event(&new,id,77,sizeof(struct vc_sm_released));assert(atomic_read(&new.live_buffers)==1);dma_buf_put(nb);assert(last_dma_device==&nd.dev&&atomic_read(&new.live_buffers)==0);
 /* Actual remove waits with transport available for last release/event. */
 sm_state=&old;db=make_buffer(&old,1);id=((struct vc_sm_buffer *)db->priv)->kernel_id;pthread_t thread;atomic_store(&waiting,0);pthread_create(&thread,0,remove_thread,&od);while(!atomic_load(&waiting))sched_yield();assert(!og.ready&&old.closing&&stops==0);dma_buf_put(db);assert(unmaps==3&&last_service==&oi);event(&old,id,77,sizeof(struct vc_sm_released));pthread_join(thread,0);assert(stops==1&&unmaps==4&&atomic_read(&old.live_buffers)==0);
 state_done(&old);sm_state=&new;bcm2835_vc_sm_cma_remove(&nd);state_done(&new);
 puts("PASS production VCSM dma_buf release/FREE/event/remove: delayed mapping cleanup, immutable IDR, duplicate/stale/malformed replies, retained client and concurrent remove");return 0;
}
