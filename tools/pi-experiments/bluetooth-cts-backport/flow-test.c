/* SPDX-License-Identifier: GPL-2.0 */
#include "production.inc"
#include "callbacks.inc"
static struct uart_8250_port u;
static struct bcm2835aux_data data;
static struct tty_struct tty;
static struct uart_state state;
static struct uart_ops ops = { .stop_rx = stop_rx };
static struct ktermios termios;
static unsigned int checks, failures;
#define CHECK(x) do { checks++; if (!(x)) { failures++; fprintf(stderr, "%d: %s\n", __LINE__, #x); } } while (0)
static void reset(void) {
  memset(&u, 0, sizeof(u)); memset(&data, 0, sizeof(data));
  tty.throttled = false; state.port.tty = &tty;
  u.port.dev = &data; u.port.ops = &ops; u.port.state = &state;
  u.port.flags = UPF_HARD_FLOW; u.port.mctrl = TIOCM_RTS;
  data.cntl = 3; u.ier = 0x8f; termios.c_cflag = CRTSCTS | 15;
  refs = termios_calls = em485_error = 0;
}
/* Register-contract oracle, not physical proof. Active-low pin readiness is
 * evaluated from the actual mapped CNTL written by the production functions. */
static bool ready(bool cts_high) {
  unsigned int cntl = mapped_read(&u, 8);
  return (cntl & 2) && (!(cntl & 8) || (cts_high == !(cntl & 128)));
}
int main(void) {
  reset(); apply_termios(&u.port, &termios, NULL);
  CHECK(termios_calls == 1); CHECK(mapped_read(&u, 8) == 0xff);
  CHECK(u.port.status == (UPSTAT_AUTOCTS | UPSTAT_AUTORTS));
  CHECK(!ready(true)); CHECK(ready(false)); CHECK(!ready(true));
  CHECK(refs == 0);
  apply_mctrl(&u.port, 0);
  CHECK(mapped_read(&u, 8) == 0x8b); CHECK(u.mcr == 0);
  apply_mctrl(&u.port, TIOCM_RTS);
  CHECK(mapped_read(&u, 8) == 0xff); CHECK(u.mcr == UART_MCR_RTS);
  tty.throttled = true; apply_throttle(&u.port);
  CHECK(mapped_read(&u, UART_IER) == 0x8a);
  apply_termios(&u.port, &termios, NULL);
  CHECK(mapped_read(&u, UART_IER) == 0x8a); CHECK(refs == 0);
  tty.throttled = false; apply_unthrottle(&u.port);
  CHECK(mapped_read(&u, UART_IER) == 0x8f);
  tty.throttled = true; termios.c_cflag = CRTSCTS; u.port.mctrl = 0;
  apply_termios(&u.port, &termios, NULL); /* B0 must not reclaim RTS */
  CHECK(mapped_read(&u, 8) == 0x8b); CHECK(u.port.mctrl == 0);
  termios.c_cflag |= 15; apply_termios(&u.port, &termios, NULL);
  CHECK(mapped_read(&u, 8) == 0xff); CHECK(u.port.mctrl & TIOCM_RTS);
  termios.c_cflag = 15; apply_termios(&u.port, &termios, NULL);
  CHECK(mapped_read(&u, 8) == 3); CHECK(u.port.status == 0);
  CHECK(mapped_read(&u, UART_IER) == 0x8f);
  /* Startup/resume termios reprogramming after register loss, including throttle. */
  reset(); tty.throttled = true; memset(u.mapped, 0, sizeof(u.mapped));
  apply_termios(&u.port, &termios, NULL);
  CHECK(mapped_read(&u, 8) == 0xff); CHECK(mapped_read(&u, UART_IER) == 0x8a);
  /* RS485 exclusion and teardown without stop_tx: recover RXEN and auto flow. */
  struct serial_rs485 r = { .flags = SER_RS485_ENABLED | SER_RS485_RTS_ON_SEND };
  CHECK(apply_rs485(&u.port, &termios, &r) == 0); u.port.rs485 = r;
  CHECK(mapped_read(&u, 8) == 3); CHECK(mapped_read(&u, UART_IER) == 0x8f);
  bcm2835aux_rs485_start_tx(&u, false);
  CHECK(mapped_read(&u, 8) == 2); CHECK(u.mcr == 0);
  bcm2835aux_rs485_stop_tx(&u, false);
  CHECK(mapped_read(&u, 8) == 3); CHECK(u.mcr == UART_MCR_RTS);
  bcm2835aux_rs485_start_tx(&u, false);
  r.flags = 0; CHECK(apply_rs485(&u.port, &termios, &r) == 0); u.port.rs485 = r;
  CHECK(mapped_read(&u, 8) == 0xff); CHECK(mapped_read(&u, UART_IER) == 0x8a);
  unsigned int cntl = mapped_read(&u, 8); em485_error = -12; r.flags = 1;
  CHECK(apply_rs485(&u.port, &termios, &r) == -12); CHECK(mapped_read(&u, 8) == cntl);
  em485_error = 0; CHECK(apply_rs485(&u.port, NULL, &r) == 0);
  CHECK(mapped_read(&u, 8) == 3);
  reset(); u.port.rs485.flags = SER_RS485_ENABLED | SER_RS485_RX_DURING_TX | SER_RS485_RTS_AFTER_SEND;
  bcm2835aux_rs485_start_tx(&u, false); CHECK(data.cntl == 3);
  bcm2835aux_rs485_stop_tx(&u, false); CHECK(data.cntl == 3); CHECK(u.mcr == 0);
  apply_termios(&u.port, &termios, NULL); CHECK(!(termios.c_cflag & CRTSCTS));
  CHECK(!(u.port.status & (UPSTAT_AUTORTS | UPSTAT_AUTOCTS)));
  reset(); u.port.flags = 0; apply_termios(&u.port, &termios, NULL);
  CHECK(!(termios.c_cflag & CRTSCTS)); CHECK(mapped_read(&u, 8) == 3);
  reset(); u.port.flags = 0; u.gpios = &tty;
  apply_termios(&u.port, &termios, NULL);
  CHECK(termios.c_cflag & CRTSCTS); CHECK(u.port.status == 0); CHECK(mapped_read(&u, 8) == 3);
  reset(); state.port.tty = NULL; apply_termios(&u.port, &termios, NULL);
  CHECK(refs == 0); CHECK(mapped_read(&u, 8) == 0xff);
  u.port.state = NULL; apply_termios(&u.port, &termios, NULL);
  CHECK(refs == 0); CHECK(mapped_read(&u, 8) == 0xff);
  /* Other serial-core status flags must survive entering/leaving hardware flow. */
  reset(); u.port.status = 0x10; apply_termios(&u.port, &termios, NULL);
  CHECK(u.port.status == 0x1c);
  termios.c_cflag = 15; apply_termios(&u.port, &termios, NULL);
  CHECK(u.port.status == 0x10);
  /* Preserve an intentionally disabled RX or TX across mode transitions. */
  for (unsigned int enables = 0; enables < 4; enables++) {
    reset(); data.cntl = enables;
    apply_termios(&u.port, &termios, NULL);
    CHECK((mapped_read(&u, 8) & 3) == enables);
    termios.c_cflag = 15; apply_termios(&u.port, &termios, NULL);
    CHECK(mapped_read(&u, 8) == enables);
  }
  printf("%u checks, %u failures\n", checks, failures);
  return failures ? 1 : 0;
}
