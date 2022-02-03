#ifndef USER_CONFIG_H
#define USER_CONFIG_H

#include <inttypes.h>
#include <sys/types.h>

#ifdef _WINDOWS
#define strerror_r(errno,buf,len) strerror_s(buf,len,errno)
#define O_CLOEXEC 0
typedef char setsockopt_name_t;
int getpagesize(void);
#else
typedef int setsockopt_name_t;
#endif

#endif