#ifndef SYS_SOCKET_H
#define SYS_SOCKET_H

#include <winsock.h>
#include <winsock2.h>
#include <ws2ipdef.h>
#include <sys/uio.h>

struct msghdr {
    WSAMSG inner;
};

typedef int socklen_t;

#define UNIX_PATH_MAX 108
struct sockaddr_un { 
     ADDRESS_FAMILY sun_family; 
     char sun_path[UNIX_PATH_MAX]; 
};

#endif
