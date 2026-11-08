.PHONY: stage-final
stage-final:
	@test -z "$(KBUILD_EXTMOD)"
	$(MAKE) -f $(srctree)/scripts/Makefile.modfinal KBUILD_MODULES=1 KBUILD_BUILTIN=1
.PHONY: stage-mod
stage-mod:
	@test -z "$(KBUILD_EXTMOD)"
	$(MAKE) -f $(srctree)/scripts/Makefile.build obj=drivers/tty/serial/8250 drivers/tty/serial/8250/8250_bcm2835aux.mod
