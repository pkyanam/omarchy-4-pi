#include <assert.h>
#include <errno.h>
#include <pthread.h>
#include <stdatomic.h>
#include <stdbool.h>
#include <stdint.h>
#include <stddef.h>
#include <stdlib.h>
#include <stdio.h>
#include <string.h>
#include <sched.h>
#include <limits.h>
typedef uint32_t u32; typedef uint16_t u16; typedef uint8_t u8; typedef int32_t s32;
#define __user
#define GFP_KERNEL 0
#define pr_debug(...) ((void)0)
#define pr_info(...) ((void)0)
#define pr_err(...) ((void)0)
#define READ_ONCE(x) __atomic_load_n(&(x),__ATOMIC_ACQUIRE)
#define WRITE_ONCE(x,v) __atomic_store_n(&(x),v,__ATOMIC_RELEASE)
#define IS_ERR(x) ((uintptr_t)(x) > (uintptr_t)-4096)
static atomic_int allocations;
static atomic_int fail_alloc;
static void *kzalloc(size_t n, int flags) { (void)flags; if(atomic_exchange(&fail_alloc,0)) return NULL; void *p=calloc(1,n); if(p) allocations++; return p; }
static void kfree(void *p) { if(p) { allocations--; free(p); } }
struct mutex { pthread_mutex_t m; };
static void mutex_init(struct mutex *m) { assert(!pthread_mutex_init(&m->m,NULL)); }
static void mutex_lock(struct mutex *m) { assert(!pthread_mutex_lock(&m->m)); }
static void mutex_unlock(struct mutex *m) { assert(!pthread_mutex_unlock(&m->m)); }
struct completion { pthread_mutex_t m; pthread_cond_t c; unsigned done; };
static void init_completion(struct completion *c) { pthread_mutex_init(&c->m,NULL); pthread_cond_init(&c->c,NULL); c->done=0; }
static void complete(struct completion *c) { pthread_mutex_lock(&c->m); c->done++; pthread_cond_broadcast(&c->c); pthread_mutex_unlock(&c->m); }
static _Thread_local bool interrupt_wait;
static int wait_for_completion_interruptible(struct completion *c) { if(interrupt_wait) return -EINTR; pthread_mutex_lock(&c->m); while(!c->done) pthread_cond_wait(&c->c,&c->m); c->done--; pthread_mutex_unlock(&c->m); return 0; }
typedef struct { atomic_int n; } refcount_t;
static void refcount_set(refcount_t *r,int n) { atomic_init(&r->n,n); }
static void refcount_inc(refcount_t *r) { assert(atomic_fetch_add(&r->n,1)>0); }
static bool refcount_dec_and_test(refcount_t *r) { int n=atomic_fetch_sub(&r->n,1); assert(n>0); return n==1; }
struct list_head { struct list_head *next,*prev; };
#define INIT_LIST_HEAD(h) ((h)->next=(h),(h)->prev=(h))
static void list_add_tail(struct list_head *n,struct list_head *h) { n->prev=h->prev; n->next=h; h->prev->next=n; h->prev=n; }
static void list_del_init(struct list_head *n) { n->prev->next=n->next; n->next->prev=n->prev; INIT_LIST_HEAD(n); }
static void list_move(struct list_head *n,struct list_head *h) { list_del_init(n); list_add_tail(n,h); }
#define list_empty(h) ((h)->next==(h))
#define entry(p,t,m) ((t *)((char *)(p)-offsetof(t,m)))
#define list_first_entry(h,t,m) entry((h)->next,t,m)
#define list_for_each_entry(p,h,m) for(p=entry((h)->next,__typeof__(*p),m); &p->m!=(h); p=entry(p->m.next,__typeof__(*p),m))
#define list_for_each_entry_safe(p,t,h,m) for(p=entry((h)->next,__typeof__(*p),m),t=entry(p->m.next,__typeof__(*p),m); &p->m!=(h); p=t,t=entry(t->m.next,__typeof__(*t),m))
struct task_struct { pthread_t t; int (*fn)(void *); void *arg; atomic_bool stop; struct completion start; };
static _Thread_local struct task_struct *current_task;
static atomic_int workers,fail_thread;
static atomic_bool join_started;
static void *thread_boot(void *p) { struct task_struct *t=p; current_task=t; wait_for_completion_interruptible(&t->start); workers++; if(!atomic_load(&t->stop)) t->fn(t->arg); workers--; return NULL; }
static struct task_struct *kthread_create(int (*fn)(void *), void *p,const char *name) { (void)name; if(atomic_exchange(&fail_thread,0)) return (void *)(intptr_t)-ENOMEM; struct task_struct *t=calloc(1,sizeof(*t)); t->fn=fn;t->arg=p; init_completion(&t->start); pthread_create(&t->t,NULL,thread_boot,t);return t; }
static int kthread_should_stop(void) { return atomic_load(&current_task->stop); }
static void wake_up_process(struct task_struct *t) { complete(&t->start); }
static int kthread_stop(struct task_struct *t) { atomic_store(&join_started,true);atomic_store(&t->stop,true);complete(&t->start);pthread_join(t->t,NULL);free(t);return 0; }
static void set_user_nice(struct task_struct *t,int n) { (void)t;(void)n; }
struct vchiq_instance { int unused; };
struct vchiq_header { u32 size; char data[512]; };
enum vchiq_reason { VCHIQ_MESSAGE_AVAILABLE,VCHIQ_SERVICE_CLOSED };
struct vchiq_service_params_kernel { int version,version_min,fourcc; int (*callback)(struct vchiq_instance *,enum vchiq_reason,struct vchiq_header *,unsigned,void *,void *);void *userdata; };
#define VCHIQ_MAKE_FOURCC(a,b,c,d) 1
static pthread_mutex_t gate=PTHREAD_MUTEX_INITIALIZER;
static pthread_cond_t changed=PTHREAD_COND_INITIALIZER;
static int queued,close_error,open_error,queue_error;
static bool block_queue,closed;
static void *service_userdata;
static int vchiq_open_service(struct vchiq_instance *v,struct vchiq_service_params_kernel *p,unsigned *h) { (void)v; if(open_error)return open_error;service_userdata=p->userdata;*h=1;return 0; }
static int vchiq_close_service(struct vchiq_instance *v,unsigned h) { (void)v;(void)h;pthread_mutex_lock(&gate);if(close_error){int e=close_error;close_error=0;pthread_mutex_unlock(&gate);return e;}closed=true;pthread_cond_broadcast(&changed);pthread_mutex_unlock(&gate);return 0; }
static int vchiq_queue_kernel_message(struct vchiq_instance *v,unsigned h,void *p,unsigned n) { (void)v;(void)h;(void)p;(void)n;pthread_mutex_lock(&gate);queued++;pthread_cond_broadcast(&changed);while(block_queue&&!closed)pthread_cond_wait(&changed,&gate);while(block_queue && closed && !atomic_load(&join_started)) { pthread_mutex_unlock(&gate); sched_yield(); pthread_mutex_lock(&gate); } int e=closed?-ESHUTDOWN:queue_error;pthread_mutex_unlock(&gate);return e; }
static int vchiq_release_service(struct vchiq_instance *v,unsigned h) { (void)v;(void)h;return 0; }
static int vchiq_use_service(struct vchiq_instance *v,unsigned h) { (void)v;(void)h;return 0; }
static struct vchiq_header *vchiq_msg_hold(struct vchiq_instance *v,unsigned h) { (void)v;(void)h;return NULL; }
static void vchiq_release_message(struct vchiq_instance *v,unsigned h,struct vchiq_header *p) { (void)v;(void)h;(void)p; }
static void *vchiq_get_service_userdata(struct vchiq_instance *v,unsigned h) { (void)v;(void)h;return service_userdata; }
static void vchiq_msg_queue_push(struct vchiq_instance *v,unsigned h,struct vchiq_header *p) { (void)v;(void)h;(void)p; }
