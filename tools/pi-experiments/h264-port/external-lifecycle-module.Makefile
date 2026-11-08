# Prefer the patched transport header over the pre-port headers package.
LINUXINCLUDE := -I$(src)/include $(LINUXINCLUDE)
# Inactive external-module compiler harness; not a package recipe.
ccflags-y += -I$(src)/include
obj-m += vchiq.o vc-sm-cma.o bcm2835-mmal-vchiq.o bcm2835-codec.o
vchiq-y := drivers/platform/raspberrypi/vchiq-interface/vchiq_core.o drivers/platform/raspberrypi/vchiq-interface/vchiq_arm.o drivers/platform/raspberrypi/vchiq-interface/vchiq_bus.o drivers/platform/raspberrypi/vchiq-interface/vchiq_debugfs.o
vc-sm-cma-y := drivers/platform/raspberrypi/vc-sm-cma/vc_sm.o drivers/platform/raspberrypi/vc-sm-cma/vc_sm_cma_vchi.o
bcm2835-mmal-vchiq-y := drivers/platform/raspberrypi/vchiq-mmal/mmal-vchiq.o
bcm2835-codec-y := drivers/platform/raspberrypi/bcm2835-codec/bcm2835-v4l2-codec.o
