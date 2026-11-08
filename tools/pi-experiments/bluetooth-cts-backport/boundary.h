/* SPDX-License-Identifier: GPL-2.0 */
/* Host boundary only: kernel types, tty reference/lock and generic 8250 calls.
 * Driver functions are extracted unchanged from the replayed production file.
 * No stub implements AUX automatic flow control. */
#include <assert.h>
#include <stdbool.h>
#include <stddef.h>
#include <stdint.h>
#include <stdio.h>
#include <string.h>
typedef uint32_t u32;
typedef unsigned int tcflag_t;
#define UPSTAT_AUTORTS 4
#define UPSTAT_AUTOCTS 8
#define UPF_HARD_FLOW ((1u << 20) | (1u << 21))
#define CRTSCTS 020000000000u
#define CBAUD 0010017u
#define B0 0
#define TIOCM_RTS 004
#define UART_MCR_RTS 2
#define UART_IER 1
#define UART_IER_RDI 1
#define UART_IER_RLSI 4
#define UART_GPIO_CTS 2
#define SER_RS485_ENABLED 1
#define SER_RS485_RTS_ON_SEND 2
#define SER_RS485_RTS_AFTER_SEND 4
#define SER_RS485_RX_DURING_TX 16
struct clk;
struct tty_struct { bool throttled; };
struct tty_port { struct tty_struct *tty; };
struct uart_state { struct tty_port port; };
struct serial_rs485 { unsigned int flags; };
struct ktermios { tcflag_t c_cflag; };
struct uart_port;
struct uart_ops { void (*stop_rx)(struct uart_port *); };
struct uart_port {
  void *dev;
  struct uart_state *state;
  struct uart_ops *ops;
  unsigned int status, flags, mctrl;
  struct serial_rs485 rs485;
};
struct uart_8250_port {
  struct uart_port port;
  unsigned int ier;
  void *gpios;
  unsigned char mapped[64];
  unsigned int writes[16], mcr;
};
static int refs, termios_calls, em485_error;
static struct tty_struct *scope __attribute__((unused));
/* Model conditional tty acquisition and release on return, as the kernel guard does. */
static void put_scope(struct tty_struct **t) { if (*t) refs--; }
#define scoped_guard(kind, p) \
  for (struct tty_struct *held __attribute__((cleanup(put_scope))) = \
       ((scope = (p)->tty) ? (refs++, scope) : NULL); held; held = (refs--, NULL))
#define scoped_tty() scope
#define guard(kind) (void)
static bool tty_throttled(struct tty_struct *t) { return t->throttled; }
static void *dev_get_drvdata(void *dev) { return dev; }
static struct uart_8250_port *up_to_u8250p(struct uart_port *p) {
  return (struct uart_8250_port *)p;
}
static void serial_out(struct uart_8250_port *u, unsigned int reg, unsigned int val) {
  assert(reg < 16);
  memcpy(u->mapped + (reg << 2), &val, sizeof(val));
  u->writes[reg]++;
}
static unsigned int mapped_read(struct uart_8250_port *u, unsigned int reg) {
  unsigned int v;
  memcpy(&v, u->mapped + (reg << 2), sizeof(v));
  return v;
}
static void serial8250_out_MCR(struct uart_8250_port *u, unsigned int v) { u->mcr = v; }
static void serial8250_do_set_mctrl(struct uart_port *p, unsigned int v) {
  serial8250_out_MCR(up_to_u8250p(p), (v & TIOCM_RTS) ? UART_MCR_RTS : 0);
}
static void stop_rx(struct uart_port *p) {
  struct uart_8250_port *u = up_to_u8250p(p);
  u->ier &= ~(UART_IER_RDI | UART_IER_RLSI);
  serial_out(u, UART_IER, u->ier);
}
static void serial8250_do_set_termios(struct uart_port *p, struct ktermios *t,
                                     const struct ktermios *old) {
  (void)t; (void)old;
  struct uart_8250_port *u = up_to_u8250p(p);
  termios_calls++;
  /* Generic termios re-enables RX: AUX must reapply a tty throttle afterwards. */
  u->ier |= UART_IER_RDI | UART_IER_RLSI;
  serial_out(u, UART_IER, u->ier);
}
static void *mctrl_gpio_to_gpiod(void *gpios, int which) { (void)which; return gpios; }
static int serial8250_em485_config(struct uart_port *p, struct ktermios *t,
                                  struct serial_rs485 *r) {
  (void)p; (void)t; (void)r;
  return em485_error;
}
