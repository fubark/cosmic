#if defined(JPH_SINGLE_THREAD)
#ifndef _WASM_CONDITION_VARIABLE
#define _WASM_CONDITION_VARIABLE

#include <Jolt/mutex.h>

#define __SIZEOF_PTHREAD_COND_T 48

namespace std {

typedef union {
    char __size[__SIZEOF_PTHREAD_COND_T];
} condition_variable_t;

class condition_variable {
private:
    condition_variable_t inner;
public:
    void notify_one() {
    }

    void notify_all() {
    }

    void wait(unique_lock<mutex>& __lock) {
        wait(__lock);
    }

    template<typename _Predicate>
    void wait(unique_lock<mutex>& __lock, _Predicate __p) {
	    while (!__p()) {
            wait(__lock);
        }
    }
};

}

#endif
#else
#include <condition_variable>
#endif
