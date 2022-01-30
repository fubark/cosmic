#include <winsock.h>

#ifndef SYS_SOCKET_H
#define SYS_SOCKET_H

struct iovec {
    void* iov_base;
    size_t iov_len;
};

struct msghdr {
    WSAMSG inner;
};

#endif
