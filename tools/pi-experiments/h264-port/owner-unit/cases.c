static void *managed[16];static int managed_count;
static void *devm_kzalloc(struct device *d,size_t n,int f) { void *p=calloc(1,n);managed[managed_count++]=p;return p; }
static void clean_devm(struct vchiq_device *d) { for(int i=0;i<managed_count;i++)free(managed[i]);managed_count=0;d->dev.data=NULL; }
/* Clean inherited successful-remove transport/tracker leaks explicitly in the
 * harness; they are not silently credited to the production remove function. */
static void remove_no_buffers(struct vchiq_device *d) {
 struct sm_state_t *s=d->dev.data;
 bcm2835_vc_sm_cma_remove(d);
 if(s->vchiq_instance)vchiq_shutdown(s->vchiq_instance);
 free(s->data_knl);
 mutex_destroy(&s->kernelid_map_lock);
 clean_devm(d);
}
static void *ioctl_thread(void *p) { assert(vc_sm_cma_ioctl(p,0,0)==42);return NULL; }
static void *remove_thread(void *p) { bcm2835_vc_sm_cma_remove(p);return NULL; }
int main(void) {
 struct vchiq_drv_mgmt mgmt={0};struct device parent={.data=&mgmt};struct vchiq_device d={.dev={.parent=&parent}};
 for(int which=0;which<3;which++) {
  init_error=which==0?-ENOMEM:0;connect_error=which==1?-EIO:0;open_error=which==2;
  int before=shutdowns;
  assert(bcm2835_vc_sm_cma_probe(&d)==0);assert(!sm_state->generation->ready);assert(!transports);
  assert(shutdowns-before==(which!=0));
  remove_no_buffers(&d);
 }
 init_error=connect_error=open_error=0;
 misc_error=-ENOMEM;int before=shutdowns;assert(!bcm2835_vc_sm_cma_probe(&d));
 assert(!sm_state->generation->ready);assert(!transports);assert(shutdowns==before+1);assert(stops==1);
 remove_no_buffers(&d);misc_error=0;stops=0;
 assert(bcm2835_vc_sm_cma_probe(&d)==0);assert(sm_state->generation->ready);
 struct file old={.private_data=&sm_state->misc_dev};assert(!vc_sm_cma_open(NULL,&old));
 struct vc_sm_privdata_t *private=old.private_data;
 assert(atomic_load(&private->generation->refs.count)==2);
 pthread_t io,rm;atomic_store(&allow_return,0);pthread_create(&io,NULL,ioctl_thread,&old);
 while(!atomic_load(&entered))usleep(100);
 pthread_create(&rm,NULL,remove_thread,&d);
 /* A held admission mutex prevents remove's ready=false/host-stop. */
 usleep(10000);assert(stops==0);
 atomic_store(&allow_return,1);pthread_join(io,NULL);pthread_join(rm,NULL);
 assert(!private->generation->ready);assert(stops==1);
 struct sm_state_t *s=d.dev.data;vchiq_shutdown(s->vchiq_instance);free(s->data_knl);mutex_destroy(&s->kernelid_map_lock);clean_devm(&d);
 assert(vc_sm_cma_ioctl(&old,0,0)==-ENODEV);
 assert(!bcm2835_vc_sm_cma_probe(&d));
 assert(vc_sm_cma_ioctl(&old,0,0)==-ENODEV);
 struct file fresh={.private_data=&sm_state->misc_dev};assert(!vc_sm_cma_open(NULL,&fresh));
 assert(vc_sm_cma_ioctl(&fresh,0,0)==42);
 assert(!vc_sm_cma_release(NULL,&old));assert(!vc_sm_cma_release(NULL,&fresh));
 remove_no_buffers(&d);assert(!transports);
 puts("PASS: actual failed-connect/open unwind; production probe/remove/reprobe with old file; admitted ioctl blocks host stop (no buffers/DMA)");
 return 0;
}
