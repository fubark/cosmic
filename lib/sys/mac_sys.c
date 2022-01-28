#include <sys/select.h>

// cImport doesn't like macros, so wrap them in functions.
void sys_FD_SET(int n, fd_set* p) {
    FD_SET(n, p);
}

void sys_FD_ZERO(fd_set* p) {
    FD_ZERO(p);
}