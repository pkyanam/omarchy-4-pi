#include <fcntl.h>
#define IS_ERR(p) ((uintptr_t)(p)>(uintptr_t)-4096)
#define IS_ERR_OR_NULL(p) (!(p)||IS_ERR(p))
#define PTR_ERR(p) ((int)(intptr_t)(p))
#define ERR_PTR(e) ((void *)(intptr_t)(e))
#define kzalloc(n,f) calloc(1,n)
#define kmalloc(n,f) malloc(n)
#define min(a,b) ((a)<(b)?(a):(b))
#define pr_warn_once(...) ((void)0)
#define VC_SM_ALLOC_NON_CACHED 0
#define VC_SM_RESOURCE_NAME_DEFAULT "test"
#define PAGE_ALIGN(n) (((n)+4095)&~4095)
struct {int tgid;} task={1};
#define current (&task)
struct vc_sm_privdata_t { int unused; };
struct vc_sm_import {u32 type,addr,size,allocator,kernel_id;char name[32];};
struct vc_sm_import_result {u32 trans_id,res_handle;};
struct vc_sm_cma_ioctl_alloc {u32 size;char name[32];int handle;u32 vc_handle;dma_addr_t dma_addr;};
struct export_info {const void *ops;size_t size;int flags;void *priv;};
#define DEFINE_DMA_BUF_EXPORT_INFO(n) struct export_info n={0}
static const int dma_buf_import_ops=1,dma_buf_ops=2;
static int export_fail,fd_fail,sg_fail,import_status,reply_handle=77,early_event,close_in_fd;
static int last_id,coherent_frees;
static void event(struct sm_state_t *,int,int,int);
static void sg_free_table(struct sg_table *s){}
static void get_dma_buf(struct dma_buf *b){b->refs++;}
static struct dma_buf *dma_buf_get(int fd){return ERR_PTR(-EBADF);}
static struct dma_buf_attachment *dma_buf_attach(struct dma_buf *b,struct device *d){return calloc(1,sizeof(struct dma_buf_attachment));}
static struct sg_table *dma_buf_map_attachment_unlocked(struct dma_buf_attachment *a,int dir){a->mapped=1;struct sg_table *s=calloc(1,sizeof(*s));s->nents=1;return s;}
#define sg_dma_address(s) ((dma_addr_t)0xc0100000)
#define sg_dma_len(s) 4096
static void *dma_alloc_coherent(struct device *d,size_t size,dma_addr_t *addr,int f){*addr=0xc0100000;return malloc(size);}
static int dma_get_sgtable(struct device *d,struct sg_table *s,void *p,dma_addr_t a,size_t n){if(sg_fail)return -ENOMEM;memset(s,0,sizeof(*s));return 0;}
static struct dma_buf *dma_buf_export(struct export_info *e){if(export_fail)return ERR_PTR(-ENOMEM);struct dma_buf *b=calloc(1,sizeof(*b));b->priv=e->priv;b->refs=1;b->exported=true;return b;}
static void dma_buf_put(struct dma_buf *b);
static int dma_buf_fd(struct dma_buf *b,int flags){if(close_in_fd)dma_buf_put(b);return fd_fail?-EMFILE:9;}
