#define EXPORT_SYMBOL_GPL(x)
#define BIT(n) (1U<<(n))
#define BITSET_WORD(n) ((n)>>5)
#define TYPE_SHIFT 24
#define VCHIQ_MSG_TYPE(id) ((id)>>TYPE_SHIFT)
#define VCHIQ_MSG_DSTPORT(id) ((id)&0xfff)
#define VCHIQ_MSG_SRCPORT(id) (((id)>>12)&0xfff)
enum {VCHIQ_MSG_PADDING,VCHIQ_MSG_CONNECT,VCHIQ_MSG_OPEN,VCHIQ_MSG_OPENACK,VCHIQ_MSG_CLOSE,VCHIQ_MSG_DATA,VCHIQ_MSG_BULK_RX,VCHIQ_MSG_BULK_TX,VCHIQ_MSG_BULK_RX_DONE,VCHIQ_MSG_BULK_TX_DONE,VCHIQ_MSG_PAUSE,VCHIQ_MSG_RESUME,VCHIQ_MSG_REMOTE_USE,VCHIQ_MSG_REMOTE_RELEASE,VCHIQ_MSG_REMOTE_USE_ACTIVE};
#define MAKE_CLOSE(s,d) ((VCHIQ_MSG_CLOSE<<TYPE_SHIFT)|((s)<<12)|(d))
#define MAKE_OPEN(s) ((VCHIQ_MSG_OPEN<<TYPE_SHIFT)|((s)<<12))
#define MAKE_PAUSE (VCHIQ_MSG_PAUSE<<TYPE_SHIFT)
#define VCHIQ_MSGID_CLAIMED 0x40000000
#define VCHIQ_SLOT_MASK 4095
#define VCHIQ_SLOT_SIZE 4096
#define SLOT_DATA_FROM_INDEX(s,i) (&(s)->sync_header)
#define VCHIQ_FOURCC_INVALID 0
#define VCHIQ_PORT_FREE 0
#define VCHIQ_MAKE_FOURCC(a,b,c,d) 1
#define QMFLAGS_NO_MUTEX_LOCK 4
#define QMFLAGS_IS_BLOCKING 1
#define QMFLAGS_NO_MUTEX_UNLOCK 2
#define NO_CLOSE_RECVD 0
#define CLOSE_RECVD 1
#define RETRY_POLL 1
#define BULK_INDEX(x) ((x)%4)
#define min(a,b) ((a)<(b)?(a):(b))
#define DEBUG_INITIALISE(x) ((void)0)
#define DEBUG_VALUE(a,b) ((void)0)
#define DEBUG_TRACE(x) ((void)0)
#define VCHIQ_STATS_INC(a,b) ((void)0)
#define VCHIQ_SERVICE_STATS_INC(a,b) ((void)0)
#define VCHIQ_SERVICE_STATS_ADD(a,b,c) ((void)0)
#define dev_dbg(dev,...) ((void)(dev))
#define dev_err(...) ((void)0)
#define dev_warn(...) ((void)0)
#define WARN_ON(x) assert(!(x))
#define WARN(x,...) assert(!(x))
#define fallthrough __attribute__((fallthrough))
#define current ((void*)1)
typedef pthread_mutex_t spinlock_t;
#define spin_lock_init(p) pthread_mutex_init(p,NULL)
#define spin_lock(p) pthread_mutex_lock(p)
#define spin_unlock(p) pthread_mutex_unlock(p)
#define atomic_read(p) atomic_load(p)
#define atomic_xchg(p,v) atomic_exchange(p,v)
static unsigned atomic_cmpxchg(atomic_uint *p,unsigned old,unsigned n){atomic_compare_exchange_strong(p,&old,n);return old;}
#define wmb() atomic_thread_fence(memory_order_seq_cst)
#define rmb() atomic_thread_fence(memory_order_seq_cst)
enum {VCHIQ_SRVSTATE_FREE,VCHIQ_SRVSTATE_OPENING,VCHIQ_SRVSTATE_OPEN,VCHIQ_SRVSTATE_OPENSYNC,VCHIQ_SRVSTATE_CLOSED,VCHIQ_SRVSTATE_HIDDEN,VCHIQ_SRVSTATE_LISTENING,VCHIQ_SRVSTATE_CLOSEWAIT,VCHIQ_SRVSTATE_CLOSESENT,VCHIQ_SRVSTATE_CLOSERECVD};
enum {VCHIQ_POLL_REMOVE,VCHIQ_POLL_TERMINATE,VCHIQ_POLL_TXNOTIFY,VCHIQ_POLL_RXNOTIFY};
enum {VCHIQ_CONNSTATE_PAUSED,VCHIQ_CONNSTATE_PAUSE_SENT,VCHIQ_CONNSTATE_CONNECTED};
enum {VCHIQ_SERVICE_CLOSED,VCHIQ_MESSAGE_AVAILABLE};
struct vchiq_service;
struct vchiq_service_owner {struct vchiq_service *service;struct completion retired,released;};
struct vchiq_header {int msgid,size;_Alignas(8) char data[64];};
struct vchiq_shared_state {int sync_trigger,trigger,slot_sync,tx_pos;};
struct vchiq_slot_zero {int version;};
struct vchiq_open_payload {int fourcc,client_id;short version,version_min;};
struct vchiq_openack_payload {short version;};
struct vchiq_bulk {int actual,dma_addr;};
struct vchiq_bulk_queue {unsigned remote_insert,local_insert,process;struct vchiq_bulk bulks[4];};
struct vchiq_service_quota {int message_use_count,message_quota,previous_tx_index,slot_use_count,slot_quota;struct completion quota_event;};
struct vchiq_state {int id,version_common,conn_state;void *dev,*slot_data,*rx_info,*slot_handler_thread;struct vchiq_shared_state *local,*remote;struct mutex sync_mutex,slot_mutex;struct completion connect;atomic_uint poll_services[1];int poll_needed,trigger_event,sync_trigger_event;int local_tx_pos,previous_data_index,data_use_count,data_quota;spinlock_t quota_spinlock;struct completion data_quota_event,slot_available_event;struct vchiq_service_quota service_quotas[16];struct vchiq_header sync_header;struct vchiq_service *service;};
struct vchiq_service {struct {int fourcc;}base;struct vchiq_state *state;struct vchiq_service_owner *owner;void *instance;int srvstate,remoteport,localport,peer_version,client_id,public_fourcc,auto_close,sync,closing,service_use_count,version,version_min;struct {atomic_uint n;}ref_count;atomic_uint poll_flags;spinlock_t owned_remove_lock;bool owned_remove_requested;struct completion remove_event;struct mutex bulk_mutex;struct vchiq_bulk_queue bulk_tx,bulk_rx;};
static void vchiq_free_service_internal(struct vchiq_service *s);
int vchiq_close_service_internal(struct vchiq_service *s,int recv);
static void complete_all(struct completion *c){pthread_mutex_lock(&c->m);c->done=UINT_MAX;pthread_cond_broadcast(&c->c);pthread_mutex_unlock(&c->m);}
static void wait_for_completion(struct completion *c){pthread_mutex_lock(&c->m);while(!c->done)pthread_cond_wait(&c->c,&c->m);if(c->done!=UINT_MAX)c->done--;pthread_mutex_unlock(&c->m);}
static void set_service_state(struct vchiq_service *s,int v){WRITE_ONCE(s->srvstate,v);}
static void vchiq_service_put(struct vchiq_service *s){assert(atomic_load(&s->ref_count.n));if(atomic_fetch_sub(&s->ref_count.n,1)==1)complete_all(&s->owner->released);}
static struct vchiq_service *find_service_by_port(struct vchiq_state *s,unsigned port){struct vchiq_service *v=s->service;if(!v||v->localport!=(int)port||v->srvstate==VCHIQ_SRVSTATE_FREE)return NULL;v->ref_count.n++;return v;}
static struct vchiq_service *get_connected_service(struct vchiq_state *s,unsigned port){assert(0);return NULL;}
static void mark_service_closing(struct vchiq_service *s){s->closing=1;}
static void mark_service_closing_internal(struct vchiq_service *s,int lock){mark_service_closing(s);}
static int vchiq_use_service_internal(struct vchiq_service *s){s->service_use_count++;return 0;}
static int vchiq_release_service_internal(struct vchiq_service *s){assert(s->service_use_count>0);s->service_use_count--;return 0;}
static int queue_error,close_sends,callbacks,released_sync;
static atomic_int open_sends;
static bool sync_once;
static int kref_read(void *p){return 1;}
static int do_abort_bulks(struct vchiq_service *s){return 1;}
static void release_service_messages(struct vchiq_service *s){}
static int make_service_callback(struct vchiq_service *s,int why,struct vchiq_header *h,void *p){assert(why==VCHIQ_SERVICE_CLOSED);callbacks++;return 0;}
static void remote_event_signal_local(int *e,int *trigger){}
static int notify_bulks(struct vchiq_service *s,struct vchiq_bulk_queue *q,int retry){return 0;}
static void vchiq_log_dump_mem(void *d,char *s,int a,void *p,int n){}
static int calc_stride(int n){return n+8;}
static int parse_open(struct vchiq_state *s,struct vchiq_header *h){assert(0);return 0;}
static void claim_slot(void *p){assert(0);}
static int mutex_lock_killable(struct mutex *m){mutex_lock(m);return 0;}
static void vchiq_complete_bulk(void *i,struct vchiq_bulk *b){assert(0);}
static void vchiq_set_conn_state(struct vchiq_state *s,int v){assert(0);}
static void vchiq_on_remote_use(struct vchiq_state *s){assert(0);}
static void vchiq_on_remote_release(struct vchiq_state *s){assert(0);}
static int remote_event_wait(int *e,int *v){return 0;}
static int kthread_should_stop(void){bool old=sync_once;sync_once=true;return old;}
static void release_message_sync(struct vchiq_state *s,struct vchiq_header *h){released_sync++;}

#define SLOT_QUEUE_INDEX_FROM_POS(n) ((n)/4096)
#define min_t(t,a,b) min(a,b)
static ssize_t memcpy_copy_callback(void *,void *,size_t,size_t);
static void remote_event_signal(struct vchiq_state *s,int *event){
 int type=VCHIQ_MSG_TYPE(s->sync_header.msgid);
 if(type==VCHIQ_MSG_OPEN)open_sends++;
 else if(type==VCHIQ_MSG_CLOSE)close_sends++;
 else assert(0);
}
static struct vchiq_header *reserve_space(struct vchiq_state *s,size_t stride,int blocking){
 if(queue_error)return NULL;
 s->local_tx_pos+=stride;
 return &s->sync_header;
}
static int wait_for_completion_killable(struct completion *c){return wait_for_completion_interruptible(c);}
