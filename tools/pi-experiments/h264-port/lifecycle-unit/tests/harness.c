#include <assert.h>
#include <errno.h>
#include <pthread.h>
#include <stdatomic.h>
#include <stdbool.h>
#include <stdio.h>
#include <stddef.h>
#define VCHIQ_DRV_MAX_CALLBACKS 10
struct mutex { pthread_mutex_t value; };
struct vchiq_drv_mgmt {
  bool connected;
  int num_deferred_callbacks;
  struct mutex connected_mutex;
  void (*deferred_callback[VCHIQ_DRV_MAX_CALLBACKS])(void);
};
struct vchiq_device { struct vchiq_drv_mgmt *drv_mgmt; };
static _Thread_local bool cancelling;
static pthread_mutex_t gate = PTHREAD_MUTEX_INITIALIZER;
static pthread_cond_t changed = PTHREAD_COND_INITIALIZER;
static bool entered, release_callback, cancel_waiting;
static atomic_bool cancelled;
static int calls;
static void mutex_lock(struct mutex *m)
{
  if (cancelling) {
    pthread_mutex_lock(&gate);
    cancel_waiting = true;
    pthread_cond_broadcast(&changed);
    pthread_mutex_unlock(&gate);
  }
  assert(!pthread_mutex_lock(&m->value));
}
static int mutex_lock_killable(struct mutex *m) { mutex_lock(m); return 0; }
static void mutex_unlock(struct mutex *m) { assert(!pthread_mutex_unlock(&m->value)); }
/* PRODUCTION_FUNCTIONS */
static void count(void) { calls++; }
static void other(void) { calls += 10; }
static void blocked(void)
{
  pthread_mutex_lock(&gate);
  entered = true;
  pthread_cond_broadcast(&changed);
  while (!release_callback) pthread_cond_wait(&changed, &gate);
  pthread_mutex_unlock(&gate);
  calls++;
}
static void *dispatch(void *p) { vchiq_call_connected_callbacks(p); return NULL; }
static void *immediate(void *p)
{
  assert(!vchiq_add_connected_callback_sync(p, blocked));
  return NULL;
}
static void *cancel(void *p)
{
  cancelling = true;
  vchiq_remove_connected_callback(p, blocked);
  atomic_store(&cancelled, true);
  return NULL;
}
static void race(struct vchiq_device *d, bool connected)
{
  struct vchiq_drv_mgmt *m=d->drv_mgmt;
  pthread_t invoke, remove;
  m->connected=connected;
  entered=release_callback=cancel_waiting=false;
  atomic_store(&cancelled,false);
  if (!connected) assert(!vchiq_add_connected_callback_sync(d,blocked));
  assert(!pthread_create(&invoke,NULL,connected?immediate:dispatch,connected?(void *)d:(void *)m));
  pthread_mutex_lock(&gate);
  while (!entered) pthread_cond_wait(&changed,&gate);
  pthread_mutex_unlock(&gate);
  assert(!pthread_create(&remove,NULL,cancel,d));
  pthread_mutex_lock(&gate);
  while (!cancel_waiting) pthread_cond_wait(&changed,&gate);
  assert(!atomic_load(&cancelled));
  /* The production dispatcher must still own the exclusion mutex. */
  assert(pthread_mutex_trylock(&m->connected_mutex.value)==EBUSY);
  release_callback=true;
  pthread_cond_broadcast(&changed);
  pthread_mutex_unlock(&gate);
  assert(!pthread_join(invoke,NULL));
  assert(!pthread_join(remove,NULL));
  assert(atomic_load(&cancelled));
  assert(m->num_deferred_callbacks==0);
}
int main(void)
{
  struct vchiq_drv_mgmt m={.connected_mutex={PTHREAD_MUTEX_INITIALIZER}};
  struct vchiq_device d={&m};
  assert(!vchiq_add_connected_callback_sync(&d,count));
  assert(vchiq_add_connected_callback_sync(&d,count)==-EEXIST);
  vchiq_remove_connected_callback(&d,count);
  vchiq_call_connected_callbacks(&m);
  assert(calls==0);
  puts("PASS remove-before-connect and duplicate rejection");
  m.connected=false;
  assert(!vchiq_add_connected_callback_sync(&d,count));
  assert(!vchiq_add_connected_callback_sync(&d,other));
  vchiq_remove_connected_callback(&d,count);
  vchiq_call_connected_callbacks(&m);
  assert(calls==10);
  puts("PASS cancellation preserves other consumer");
  m.connected=false;
  assert(!vchiq_add_connected_callback_sync(&d,count));
  vchiq_remove_connected_callback(&d,count);
  assert(!vchiq_add_connected_callback_sync(&d,count));
  vchiq_call_connected_callbacks(&m);
  assert(calls==11);
  puts("PASS remove/re-register (transport reprobe prerequisite)");
  m.connected=false;
  m.num_deferred_callbacks=VCHIQ_DRV_MAX_CALLBACKS;
  for(int i=0;i<VCHIQ_DRV_MAX_CALLBACKS;i++) m.deferred_callback[i]=other;
  assert(vchiq_add_connected_callback_sync(&d,count)==-ENOSPC);
  assert(m.num_deferred_callbacks==VCHIQ_DRV_MAX_CALLBACKS);
  m.num_deferred_callbacks=0;
  puts("PASS registration capacity failure");
  race(&d,false);
  puts("PASS cancellation drains active deferred invocation");
  race(&d,true);
  puts("PASS cancellation drains active immediate invocation");
  assert(!pthread_mutex_destroy(&m.connected_mutex.value));
}
