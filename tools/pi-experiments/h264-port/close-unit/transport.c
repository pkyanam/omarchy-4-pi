/* Kernel/RCU/refcount and transport boundaries for extracted production bodies. */
#define EXPORT_SYMBOL(x)
#define EXPORT_SYMBOL_GPL(x)
#define VCHIQ_MAX_SERVICES 16
#define VCHIQ_MAX_STATES 1
#define VCHIQ_PORT_MAX 15
#define VCHIQ_PORT_FREE 0
#define VCHIQ_SERVICE_HANDLE_INVALID 0
#define VCHIQ_FOURCC_INVALID 0
#define VCHIQ_POLL_REMOVE 1
#define VCHIQ_POLL_TERMINATE 2
#define NO_CLOSE_RECVD 0
#define WARN_ON(x) assert(!(x))
#define WARN(x,...) assert(!(x))
#define dev_dbg(dev,...) ((void)(dev))
#define dev_warn(...) ((void)0)
#define dev_err(...) ((void)0)
#define __rcu
#define rcu_read_lock() ((void)0)
#define rcu_read_unlock() ((void)0)
#define rcu_dereference(p) READ_ONCE(p)
#define rcu_access_pointer(p) READ_ONCE(p)
#define rcu_pointer_handoff(p) (p)
#define rcu_assign_pointer(p,v) WRITE_ONCE(p,v)
#define container_of(p,t,m) entry(p,t,m)
#define kfree_rcu(p,m) kfree(p)
#define kzalloc_obj(x) kzalloc(sizeof(x),GFP_KERNEL)
#define SLOT_QUEUE_INDEX_FROM_POS(x) (x)
#define current current_task
struct kref { atomic_int n; };
static void kref_init(struct kref *r){atomic_init(&r->n,1);}
static void kref_get(struct kref *r){assert(atomic_fetch_add(&r->n,1)>0);}
static bool kref_get_unless_zero(struct kref *r){int n=atomic_load(&r->n);while(n && !atomic_compare_exchange_weak(&r->n,&n,n+1)){}return n;}
static void kref_put(struct kref *r,void (*fn)(struct kref *)){int n=atomic_fetch_sub(&r->n,1);assert(n>0);if(n==1)fn(r);}
static void complete_all(struct completion *c){pthread_mutex_lock(&c->m);c->done=UINT_MAX;pthread_cond_broadcast(&c->c);pthread_mutex_unlock(&c->m);}
static atomic_bool release_wait_entered;
static struct completion *release_wait_target;
static void wait_for_completion(struct completion *c){if(c==release_wait_target)atomic_store(&release_wait_entered,true);pthread_mutex_lock(&c->m);while(!c->done)pthread_cond_wait(&c->c,&c->m);if(c->done!=UINT_MAX)c->done--;pthread_mutex_unlock(&c->m);}
struct vchiq_header { u32 size; char data[512]; };
enum vchiq_reason { VCHIQ_MESSAGE_AVAILABLE,VCHIQ_SERVICE_CLOSED };
struct vchiq_instance;
struct vchiq_service_params_kernel { int version,version_min,fourcc; int (*callback)(struct vchiq_instance *,enum vchiq_reason,struct vchiq_header *,unsigned,void *,void *);void *userdata; };
#define VCHIQ_MAKE_FOURCC(a,b,c,d) 1
struct vchiq_service_owner {struct vchiq_service *service;struct completion retired,released;};
enum { VCHIQ_SRVSTATE_FREE,VCHIQ_SRVSTATE_OPENING,VCHIQ_SRVSTATE_OPEN,VCHIQ_SRVSTATE_CLOSED,VCHIQ_SRVSTATE_HIDDEN,VCHIQ_SRVSTATE_LISTENING,VCHIQ_SRVSTATE_CLOSEWAIT };
struct vchiq_service_quota {int slot_quota,message_quota,slot_use_count,previous_tx_index;};
struct vchiq_state {struct mutex mutex;int id,unused_service,default_slot_quota,default_message_quota,local_tx_pos;void *dev;struct task_struct *slot_handler_thread;struct vchiq_service *services[16];struct vchiq_service_quota service_quotas[16];};
struct vchiq_instance { struct vchiq_state *state; };
struct vchiq_service {struct vchiq_service_params_kernel base;struct kref ref_count;struct vchiq_state *state;struct vchiq_instance *instance;struct vchiq_service_owner *owner;int srvstate;unsigned handle;int localport,remoteport,public_fourcc,auto_close,version,version_min;atomic_int poll_flags;void (*userdata_term)(void *);struct completion remove_event,bulk_remove_event,msg_queue_pop,msg_queue_push;struct mutex bulk_mutex;};
static unsigned handle_seq;
static void set_service_state(struct vchiq_service *s,int n){WRITE_ONCE(s->srvstate,n);}
static void atomic_set(atomic_int *a,int v){atomic_store(a,v);}
static void vchiq_service_put(struct vchiq_service *s);
static void vchiq_service_get(struct vchiq_service *s);
static void vchiq_free_service_internal(struct vchiq_service *s);
static void vchiq_remove_service_sync(struct vchiq_service_owner *o);
static void mark_service_closing(struct vchiq_service *s);
static void request_poll(struct vchiq_state *s,struct vchiq_service *v,int type);
static int vchiq_close_service_internal(struct vchiq_service *s,int reason){assert(0);return 0;}
static int vchiq_open_service_internal(struct vchiq_service *s,int pid);
static bool vchiq_is_connected(struct vchiq_instance *v){return true;}
static pthread_mutex_t gate=PTHREAD_MUTEX_INITIALIZER;
static pthread_cond_t changed=PTHREAD_COND_INITIALIZER;
static int queued,open_error,queue_error;
static bool block_queue,closed;
static atomic_int removal_threads;
static atomic_bool hold_callback,callback_entered,allow_callback,stop_done;
static atomic_int callback_count;
static int open_count,fail_open_number;
static void *service_userdata;

static _Thread_local bool stall_callback;
