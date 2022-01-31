#include <windows.h>

#ifndef POSIX_H
#define POSIX_H

typedef SRWLOCK pthread_mutex_t;
typedef CONDITION_VARIABLE pthread_cond_t;
typedef HANDLE pthread_t;
typedef struct {
    int stub;
} pthread_attr_t;

typedef struct {
    int stub;
} pthread_mutexattr_t;

int pthread_mutex_lock(pthread_mutex_t *mutex);
int pthread_mutex_unlock(pthread_mutex_t *mutex);
int pthread_mutex_trylock(pthread_mutex_t *mutex);
int pthread_mutex_init(pthread_mutex_t *mutex, const pthread_mutexattr_t *attr);
int pthread_mutex_destroy(pthread_mutex_t *mutex);
int pthread_cond_wait(pthread_cond_t *cond, pthread_mutex_t *mutex);
int pthread_cond_signal(pthread_cond_t *cond);
int pthread_attr_init(pthread_attr_t *attr);
int pthread_create(
    pthread_t *thread, const pthread_attr_t *attr,
    void *(*start_routine)(void *), void *arg);
int pthread_join(pthread_t thread, void **value_ptr);

#endif
