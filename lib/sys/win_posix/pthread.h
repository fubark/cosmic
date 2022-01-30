#ifndef POSIX_H
#define POSIX_H

typedef SRWLOCK pthread_mutex_t;
typedef CONDITION_VARIABLE pthread_cond_t;
typedef HANDLE pthread_t;
typedef struct {
    int stub;
} pthread_attr_t;

#endif
