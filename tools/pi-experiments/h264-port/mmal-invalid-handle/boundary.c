#include <assert.h>
#include <errno.h>
#include <stddef.h>
#include <stdio.h>
#include <string.h>

struct list_head { int unused; };
struct mmal_msg_context { int unused; };
struct vchiq_mmal_instance { int unused; };
struct vchiq_mmal_port { int zero_copy, slock; struct list_head buffers; };
struct mmal_buffer {
  void *dma_buf, *vcsm_handle;
  unsigned vc_handle;
  struct mmal_msg_context *msg_context;
  struct list_head list;
};
static int import_error, free_error, vc_handle, free_calls, frees, submissions;
static int imported;
#define pr_dbg_lvl(...) ((void)0)
#define pr_err(...) ((void)0)
#define spin_lock_irqsave(lock, flags) do { (void)(lock); (void)(flags); } while (0)
#define spin_unlock_irqrestore(lock, flags) do { (void)(lock); (void)(flags); } while (0)
static void list_add_tail(struct list_head *a, struct list_head *b) { (void)a; (void)b; }
static void release_msg_context(struct mmal_msg_context *context) { (void)context; }
static int vc_sm_cma_import_dmabuf(void *dma_buf, void **handle) {
  assert(dma_buf);
  if (!import_error) *handle = &imported;
  return import_error;
}
static int vc_sm_cma_int_handle(void *handle) { assert(handle == &imported); return vc_handle; }
static int vc_sm_cma_free(void *handle) {
  assert(handle == &imported);
  ++free_calls;
  if (!free_error) { assert(frees == 0); ++frees; }
  return free_error;
}
static int buffer_from_host(struct vchiq_mmal_instance *instance, struct vchiq_mmal_port *port, struct mmal_buffer *buffer) {
  (void)instance; (void)port; (void)buffer; ++submissions; return 0;
}

/* PRODUCTION_FUNCTIONS */

static struct mmal_buffer fresh(void) {
  import_error = free_error = vc_handle = free_calls = frees = submissions = 0;
  struct mmal_buffer buffer = { .dma_buf = &imported };
  return buffer;
}
int main(void) {
  struct vchiq_mmal_instance instance = {0};
  struct vchiq_mmal_port port = { .zero_copy = 1 };
  struct mmal_buffer buffer = fresh();
  assert(vchiq_mmal_submit_buffer(&instance, &port, &buffer) == -EIO);
  assert(!buffer.vcsm_handle && frees == 1 && submissions == 0);
  assert(mmal_vchi_buffer_cleanup(&buffer) == 0 && free_calls == 1);

  buffer = fresh(); free_error = -EPERM;
  assert(vchiq_mmal_submit_buffer(&instance, &port, &buffer) == -EPERM);
  assert(buffer.vcsm_handle == &imported && frees == 0 && submissions == 0);
  free_error = 0;
  assert(mmal_vchi_buffer_cleanup(&buffer) == 0 && frees == 1 && free_calls == 2);

  buffer = fresh(); import_error = -ENOMEM;
  assert(vchiq_mmal_submit_buffer(&instance, &port, &buffer) == -ENOMEM);
  assert(!buffer.vcsm_handle && !free_calls && !submissions);

  buffer = fresh(); vc_handle = 37;
  assert(vchiq_mmal_submit_buffer(&instance, &port, &buffer) == 0 && submissions == 1);
  assert(mmal_vchi_buffer_cleanup(&buffer) == 0 && frees == 1);
  puts("PASS actual submit/cleanup: invalid handle, cleanup, free/import error, valid submission");
  return 0;
}
