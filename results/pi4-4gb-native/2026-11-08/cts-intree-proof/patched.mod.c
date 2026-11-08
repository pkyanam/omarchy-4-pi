#include <linux/module.h>
#include <linux/export-internal.h>
#include <linux/compiler.h>

MODULE_INFO(name, KBUILD_MODNAME);

__visible struct module __this_module
__section(".gnu.linkonce.this_module") = {
	.name = KBUILD_MODNAME,
	.init = init_module,
#ifdef CONFIG_MODULE_UNLOAD
	.exit = cleanup_module,
#endif
	.arch = MODULE_ARCH_INIT,
};

MODULE_INFO(intree, "Y");



static const struct modversion_info ____versions[]
__used __section("__versions") = {
	{ 0xc09e7a6a, "__platform_driver_register" },
	{ 0xb5be2d6f, "serial8250_unregister_port" },
	{ 0x33d0c686, "clk_disable" },
	{ 0x33d0c686, "clk_unprepare" },
	{ 0x2106df1a, "device_remove_software_node" },
	{ 0xcffd9e08, "serial8250_do_set_mctrl" },
	{ 0xa0cac76d, "platform_driver_unregister" },
	{ 0x0e9cab28, "memset" },
	{ 0xe3246ffc, "devm_kmalloc" },
	{ 0xe83830c3, "serial8250_em485_supported" },
	{ 0xe87b4808, "devm_clk_get_optional" },
	{ 0xe9bf8a6a, "platform_get_resource" },
	{ 0x3a0124ef, "device_get_match_data" },
	{ 0xa2e94357, "device_add_software_node" },
	{ 0xe5dbadaf, "uart_read_port_properties" },
	{ 0xcedd357b, "device_property_read_bool" },
	{ 0xd8b288f3, "clk_prepare" },
	{ 0x2efcfb71, "dev_err_probe" },
	{ 0xd8b288f3, "clk_enable" },
	{ 0xa0928e7c, "clk_get_rate" },
	{ 0x3e762215, "serial8250_register_8250_port" },
	{ 0xd272d446, "__stack_chk_fail" },
	{ 0x889d9f7a, "_dev_err" },
	{ 0x8059ac6d, "serial8250_get_port" },
	{ 0x3239fbdb, "console_suspend_enabled" },
	{ 0xe4de56b4, "__ubsan_handle_load_invalid_value" },
	{ 0xb5be2d6f, "serial8250_suspend_port" },
	{ 0x18de975f, "tty_port_tty_get" },
	{ 0xe7a073ce, "tty_kref_put" },
	{ 0x81e61484, "serial8250_em485_config" },
	{ 0xb5be2d6f, "serial8250_resume_port" },
	{ 0x3f0dca4b, "serial8250_do_set_termios" },
	{ 0x11f4259a, "_raw_spin_lock_irqsave" },
	{ 0x444885a7, "_raw_spin_unlock_irqrestore" },
	{ 0xeec869d9, "mctrl_gpio_to_gpiod" },
	{ 0x17e80d2b, "nbcon_device_try_acquire" },
	{ 0xf4d63727, "nbcon_device_release" },
	{ 0x4483a0b8, "mctrl_gpio_set" },
	{ 0x57971f80, "module_layout" },
};

static const u32 ____version_ext_crcs[]
__used __section("__version_ext_crcs") = {
	0xc09e7a6a,
	0xb5be2d6f,
	0x33d0c686,
	0x33d0c686,
	0x2106df1a,
	0xcffd9e08,
	0xa0cac76d,
	0x0e9cab28,
	0xe3246ffc,
	0xe83830c3,
	0xe87b4808,
	0xe9bf8a6a,
	0x3a0124ef,
	0xa2e94357,
	0xe5dbadaf,
	0xcedd357b,
	0xd8b288f3,
	0x2efcfb71,
	0xd8b288f3,
	0xa0928e7c,
	0x3e762215,
	0xd272d446,
	0x889d9f7a,
	0x8059ac6d,
	0x3239fbdb,
	0xe4de56b4,
	0xb5be2d6f,
	0x18de975f,
	0xe7a073ce,
	0x81e61484,
	0xb5be2d6f,
	0x3f0dca4b,
	0x11f4259a,
	0x444885a7,
	0xeec869d9,
	0x17e80d2b,
	0xf4d63727,
	0x4483a0b8,
	0x57971f80,
};
static const char ____version_ext_names[]
__used __section("__version_ext_names") =
	"__platform_driver_register\0"
	"serial8250_unregister_port\0"
	"clk_disable\0"
	"clk_unprepare\0"
	"device_remove_software_node\0"
	"serial8250_do_set_mctrl\0"
	"platform_driver_unregister\0"
	"memset\0"
	"devm_kmalloc\0"
	"serial8250_em485_supported\0"
	"devm_clk_get_optional\0"
	"platform_get_resource\0"
	"device_get_match_data\0"
	"device_add_software_node\0"
	"uart_read_port_properties\0"
	"device_property_read_bool\0"
	"clk_prepare\0"
	"dev_err_probe\0"
	"clk_enable\0"
	"clk_get_rate\0"
	"serial8250_register_8250_port\0"
	"__stack_chk_fail\0"
	"_dev_err\0"
	"serial8250_get_port\0"
	"console_suspend_enabled\0"
	"__ubsan_handle_load_invalid_value\0"
	"serial8250_suspend_port\0"
	"tty_port_tty_get\0"
	"tty_kref_put\0"
	"serial8250_em485_config\0"
	"serial8250_resume_port\0"
	"serial8250_do_set_termios\0"
	"_raw_spin_lock_irqsave\0"
	"_raw_spin_unlock_irqrestore\0"
	"mctrl_gpio_to_gpiod\0"
	"nbcon_device_try_acquire\0"
	"nbcon_device_release\0"
	"mctrl_gpio_set\0"
	"module_layout\0"
;

MODULE_INFO(depends, "");

MODULE_ALIAS("acpi*:BCM2836:*");
MODULE_ALIAS("of:N*T*Cbrcm,bcm2835-aux-uart");
MODULE_ALIAS("of:N*T*Cbrcm,bcm2835-aux-uartC*");

MODULE_INFO(srcversion, "B6C2E9747A85E858B731389");
