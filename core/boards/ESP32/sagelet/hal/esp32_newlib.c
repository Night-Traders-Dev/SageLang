/* esp32_newlib.c — the few libc/libgcc symbols a bare-metal ESP32 image needs.
 *
 * The Sage backend emits a self-contained C file that uses libc (fputs/stdio,
 * strcmp, math) and GCC emits calls to libgcc helpers. With a single newlib
 * instance and no hosted environment we supply the syscalls the linker asks
 * for, and route stdout at the UART so `print` reaches the console.
 */

#include <stddef.h>
#include <stdint.h>
#include <sys/stat.h>
#include <sys/types.h>
#include <fcntl.h>
#include <reent.h>

int hal_uart_init(uint32_t baud);
int hal_uart_putc(int byte);
int hal_uart_getc(void);

/* ------------------------------------------------------------- syscalls */

void *_sbrk_r(struct _reent *r, ptrdiff_t incr) {
    (void)r;
    extern char _heap_start;
    extern char _heap_end;
    static char *brk = NULL;
    if (brk == NULL) brk = &_heap_start;
    char *prev = brk;
    if (brk + incr > &_heap_end) return (void *)-1;
    brk += incr;
    return prev;
}

int _close(int fd) { (void)fd; return -1; }
int _fstat(int fd, struct stat *st) {
    (void)fd;
    st->st_mode = S_IFCHR;
    return 0;
}
int _isatty(int fd) { (void)fd; return 1; }
int _lseek(int fd, int pos, int whence) { (void)fd; (void)pos; (void)whence; return 0; }
int _read(int fd, char *buf, int len) { (void)fd; (void)buf; (void)len; return -1; }

int _write(int fd, const char *buf, int len) {
    if (fd != 1 && fd != 2) return -1;
    int n = 0;
    while (n < len) {
        if (hal_uart_putc((unsigned char)buf[n]) < 0) break;
        n++;
    }
    return n;
}

int _getpid(void) { return 1; }
int _kill(int pid, int sig) { (void)pid; (void)sig; return -1; }

/* Sage's print path writes to stdout, which newlib buffers. In an interactive
 * console a line-buffered stream is what you want: prompts appear immediately
 * but multi-call prints do not thrash the FIFO. */
int _open(const char *path, int flags, int mode) {
    (void)path; (void)mode;
    /* Only claim the character devices we actually drive. */
    if (flags & 0x100 /* O_WRONLY */) return 1;
    if (flags & 0x200 /* O_RDWR   */) return 2;
    return 3;
}

void __attribute__((weak)) _exit(int code) {
    (void)code;
    for (;;) { }
}

void abort(void) {
    for (;;) { }
}

int atexit(void (*f)(void)) { (void)f; return 0; }

int main(int argc, char **argv);
