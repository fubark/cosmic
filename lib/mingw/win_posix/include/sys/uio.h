#ifndef SYS_UIO_H
#define SYS_UIO_H

#include <inttypes.h>

#define UIO_MAXIOV 1024

struct iovec {
    void* iov_base;
    size_t iov_len;
};

ssize_t writev(int fildes, const struct iovec *iov, int iovcnt);

#endif