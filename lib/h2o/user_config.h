#ifndef USER_CONFIG_H
#define USER_CONFIG_H

#include <inttypes.h>
#include <sys/types.h>

#ifdef _WINDOWS
#define PROT_READ 1
#define PROT_WRITE 1
#define MAP_SHARED 1
#define MAP_FAILED ((void *) -1)
#define strerror_r(errno,buf,len) strerror_s(buf,len,errno)
int getpagesize(void);
int munmap(void *addr, size_t length);
void *mmap(void *addr, size_t length, int prot, int flags, int fd, off_t offset);
#endif

#endif