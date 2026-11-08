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
#include <unistd.h>
typedef uint32_t u32;
typedef int pid_t;
#define GFP_KERNEL 0
#define MISC_DYNAMIC_MINOR 1
#define DEVICE_NAME "vcsm-cma"
#define VC_SM_DIR_ROOT_NAME "vcsm-cma"
#define VC_SM_STATE "state"
#define DMA_BIT_MASK(n) ((1ULL<<(n))-1)
#define container_of(p,t,m) ((t *)((char *)(p)-offsetof(t,m)))
#define pr_debug(...) ((void)0)
#define pr_info(...) ((void)0)
#define pr_err(...) ((void)0)
#define dev_err(...) ((void)0)
struct mutex { pthread_mutex_t m; };
#define DEFINE_MUTEX(n) struct mutex n = { PTHREAD_MUTEX_INITIALIZER }
static void mutex_init(struct mutex *m) { assert(!pthread_mutex_init(&m->m,NULL)); }
static void mutex_destroy(struct mutex *m) { assert(!pthread_mutex_destroy(&m->m)); }
static void mutex_lock(struct mutex *m) { assert(!pthread_mutex_lock(&m->m)); }
static void mutex_unlock(struct mutex *m) { assert(!pthread_mutex_unlock(&m->m)); }
struct kref { atomic_int count; };
static void kref_init(struct kref *r) { atomic_init(&r->count,1); }
static void kref_get(struct kref *r) { assert(atomic_fetch_add(&r->count,1)>0); }
static void kref_put(struct kref *r, void (*release)(struct kref *)) { if(atomic_fetch_sub(&r->count,1)==1) release(r); }
static void *kzalloc(size_t n,int flags) { return calloc(1,n); }
static void kfree(void *p) { free(p); }
struct device { struct device *parent; void *data; void *dma_parms; };
struct vchiq_device { struct device dev; };
struct vchiq_drv_mgmt { int state; };
struct vchiq_instance { int connected; };
struct sm_instance { int dummy; };
struct miscdevice { int minor; const char *name; const void *fops; struct device *parent; int mode; };
struct idr { int dummy; };
struct list_head { int dummy; };
struct dentry { int dummy; };
struct seq_file { int dummy; };
struct inode { int dummy; };
struct file { void *private_data; };
enum vc_sm_msg_type { DUMMY };
struct vc_sm_version { int version; };
struct vc_sm_result_t { int dummy; };
static struct { int tgid; } task = {123};
#define current (&task)
static int vc_sm_ops, vc_sm_cma_debug_fs_fops;
static int init_error,connect_error,open_error,register_error,misc_error;
static int transports,stops,shutdowns,registered;
static void *dev_get_drvdata(struct device *d) { return d->data; }
static void dev_set_drvdata(struct device *d, void *p) { d->data=p; }
static int vchiq_initialise(int *s, struct vchiq_instance **out) { if(init_error)return init_error; *out=calloc(1,sizeof(**out)); transports++; return 0; }
static int vchiq_connect(struct vchiq_instance *v) { v->connected=!connect_error; return connect_error; }
static struct sm_instance *vc_sm_cma_vchi_init(struct vchiq_instance *v,unsigned int n,void (*event)(struct sm_instance *,struct vc_sm_result_t *,int)) { return open_error?NULL:calloc(1,sizeof(struct sm_instance)); }
static int vchiq_shutdown(struct vchiq_instance *v) { transports--;shutdowns++;free(v);return 0; }
static int vc_sm_cma_vchi_stop(struct vchiq_instance *v,struct sm_instance **s) { stops++;free(*s);*s=NULL;return 0; }
static int vc_sm_cma_vchi_client_version(struct sm_instance *s,struct vc_sm_version *v,struct vc_sm_result_t *r,u32 *id) { return 0; }
static int dma_set_mask_and_coherent(struct device *d,uint64_t n) { return 0; }
static void dma_set_max_seg_size(struct device *d,int n) { }
static void *devm_kzalloc(struct device *d,size_t n,int f);
static void idr_init_base(struct idr *i,int b) { }
static void idr_destroy(struct idr *i) { }
#define INIT_LIST_HEAD(p) ((void)0)
static int misc_register(struct miscdevice *m) { registered=!misc_error;return misc_error; }
static void misc_deregister(struct miscdevice *m) { registered=0; }
static struct dentry debug;
static struct dentry *debugfs_create_dir(const char *s,void *p) { return &debug; }
static struct dentry *debugfs_create_file(const char *s,int mode,void *p,void *v,void *ops) { return &debug; }
static void debugfs_remove_recursive(struct dentry *d) { }
static int vc_sm_cma_global_state_show(struct seq_file *s,void *v) { return 0; }
static int vchiq_register_connected_callback(struct vchiq_device *d,void (*cb)(void)) { if(!register_error)cb();return register_error; }
static void vchiq_remove_connected_callback(struct vchiq_device *d,void (*cb)(void)) { }
static void vc_sm_vpu_event(struct sm_instance *i,struct vc_sm_result_t *r,int n) { }
static atomic_int entered,allow_return;
static long vc_sm_cma_ioctl_admitted(struct file *f,unsigned int c,unsigned long a) { atomic_store(&entered,1);while(!atomic_load(&allow_return))usleep(100);return 42; }
