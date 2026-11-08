static int vc_sm_cma_vchi_free(struct sm_instance *s,struct vc_sm_free_t *f,u32 *id){frees++;last_service=s;return free_status;}
static void dma_buf_unmap_attachment_unlocked(struct dma_buf_attachment *a,struct sg_table *s,int d){assert(a->mapped);a->mapped=0;unmaps++;free(s);}
static void dma_buf_detach(struct dma_buf *b,struct dma_buf_attachment *a){assert(!a->mapped);detaches++;free(a);}
static void dma_free_coherent(struct device *d,size_t s,void *p,dma_addr_t a){last_dma_device=d;free(p);}
static int vc_sm_cma_vpu_alloc(struct sm_state_t *s,u32 size,u32 align,const char *name,u32 h,struct vc_sm_buffer **b){assert(!"allocation boundary not exercised");return -ENOMEM;}
static int vc_sm_vchi_client_vc_mem_req_reply(struct sm_instance *s,struct vc_sm_vc_mem_request_result *r,u32 *id){assert(!r->addr&&!r->kernel_id);return 0;}
static void *dev_get_drvdata(struct device *d){return d->data;}
static void vc_sm_connected_init(void){}
static void vchiq_remove_connected_callback(struct vchiq_device *d,void (*cb)(void)){}
static void misc_deregister(int *m){}
static void debugfs_remove_recursive(void *p){}
static int vc_sm_cma_vchi_stop(void *v,struct sm_instance **s){stops++;*s=NULL;return 0;}
static void vc_sm_generation_put(struct vc_sm_generation *g){}
