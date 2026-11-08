#include <assert.h>
#include <errno.h>
#include <stdbool.h>
#include <stdint.h>
#include <stddef.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <pthread.h>
#include <stdatomic.h>
#include <limits.h>
typedef uint32_t u32;
typedef uintptr_t dma_addr_t;
#define GFP_KERNEL 0
#define VC_SM_MAX_NAME_LEN 32
#define pr_debug(...) ((void)0)
#define pr_err(...) ((void)0)
#define DMA_BIDIRECTIONAL 0
#define kfree free
struct mutex { pthread_mutex_t m; };
#define DEFINE_MUTEX(n) struct mutex n = { PTHREAD_MUTEX_INITIALIZER }
static void mutex_init(struct mutex *m){assert(!pthread_mutex_init(&m->m,0));}
static void mutex_lock(struct mutex *m){assert(!pthread_mutex_lock(&m->m));}
static void mutex_unlock(struct mutex *m){assert(!pthread_mutex_unlock(&m->m));}
static void mutex_destroy(struct mutex *m){assert(!pthread_mutex_destroy(&m->m));}
typedef atomic_int atomic_t;
#define atomic_inc(p) atomic_fetch_add(p,1)
#define atomic_dec(p) atomic_fetch_sub(p,1)
#define atomic_read(p) atomic_load(p)
struct list_head { struct list_head *next,*prev; };
#define INIT_LIST_HEAD(p) ((p)->next=(p)->prev=(p))
static void list_add(struct list_head *p,struct list_head *h){p->next=h->next;p->prev=h;h->next->prev=p;h->next=p;}
static void list_del(struct list_head *p){p->prev->next=p->next;p->next->prev=p->prev;}
struct device { void *data; };
struct vchiq_device { struct device dev; };
struct dma_buf { void *priv; int refs; bool exported; };
struct dma_buf_attachment { int mapped; };
struct sg_table { int dummy; };
struct vc_sm_privdata_t;
struct sm_instance { int generation; };
struct vc_sm_generation { bool ready; };
struct idr { void *slots[128]; };
static int idr_alloc(struct idr *i,void *p,int start,int end,int flags){if(start>=128)return -ENOSPC;assert(!i->slots[start]);i->slots[start]=p;return start;}
static void *idr_find(struct idr *i,int id){return id>0&&id<128?i->slots[id]:NULL;}
static void idr_remove(struct idr *i,int id){if(id>0&&id<128)i->slots[id]=NULL;}
static void idr_destroy(struct idr *i){for(int j=0;j<128;j++)assert(!i->slots[j]);}
struct waitq { pthread_mutex_t lock; pthread_cond_t cond; };
static void wake_up_all(struct waitq *q){pthread_mutex_lock(&q->lock);pthread_cond_broadcast(&q->cond);pthread_mutex_unlock(&q->lock);}
static atomic_int waiting;
#define wait_event(q,condition) do { pthread_mutex_lock(&(q).lock);atomic_store(&waiting,1);while(!(condition))pthread_cond_wait(&(q).cond,&(q).lock);pthread_mutex_unlock(&(q).lock); }while(0)
struct sm_state_t { struct vc_sm_generation *generation; struct vchiq_device *device; struct sm_instance *sm_handle; struct mutex kernelid_map_lock,map_lock,firmware_lock; struct idr kernelid_map;int next_kernel_id;struct list_head buffer_list;bool closing,require_released_callback;struct waitq buffer_drain;atomic_t live_buffers;u32 int_trans_id;void *vchiq_instance,*dir_root;int misc_dev; };
static struct sm_state_t *sm_state;
static DEFINE_MUTEX(sm_admission_lock);
struct vc_sm_result_t {u32 trans_id,success;};
struct vc_sm_free_t {u32 handle,pad;};
struct vc_sm_released {u32 cmd,addr,size,kernel_id,vc_handle;};
struct vc_sm_vc_mem_request {u32 cmd,trans_id,size,align;char name[32];u32 vc_handle;};
struct vc_sm_vc_mem_request_result {u32 trans_id,addr,kernel_id;};
#define VC_SM_MSG_TYPE_CLIENT_VERSION 1
#define VC_SM_MSG_TYPE_RELEASED 2
#define VC_SM_MSG_TYPE_VC_MEM_REQUEST 3
static int frees,unmaps,detaches,put_count,stops,free_status;
static struct sm_instance *last_service;
static struct device *last_dma_device;
static void dma_buf_put(struct dma_buf *b);
