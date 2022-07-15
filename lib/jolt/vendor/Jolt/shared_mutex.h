#if defined(JPH_SINGLE_THREAD)
#ifndef _WASM_SHARED_MUTEX
#define _WASM_SHARED_MUTEX

#define __SIZEOF_PTHREAD_RWLOCK_T 56

typedef union shared_mutex_t {
    char __size[__SIZEOF_PTHREAD_RWLOCK_T];
    struct {
        bool locked;
        bool shared;
    } lock;
} shared_mutex_t;

template<typename Mutex>
class shared_lock {
private:
    Mutex*	_M_pm;
    bool		_M_owns;

public:
    shared_lock() : _M_pm(nullptr), _M_owns(false) { }

    explicit shared_lock(Mutex& __m) : _M_pm(std::addressof(__m)), _M_owns(true) {
        __m.lock_shared();
    }
    
    ~shared_lock() {
        if (_M_owns)
            _M_pm->unlock_shared();
    }
};

class shared_mutex {
private:
    shared_mutex_t inner;

public:
    shared_mutex() {
        inner.lock = { false, false };
    }

    void lock() {
        while (inner.lock.locked) {}
        inner.lock.locked = true;
        inner.lock.shared = false;
    }

    void unlock() {
        if (inner.lock.locked) {
            inner.lock.locked = false;
        }
    }

    bool try_lock() {
        if (inner.lock.locked) {
            return false;
        } else {
            inner.lock.locked = true;
            inner.lock.shared = false;
            return true;
        }
    }

    void lock_shared() {
        while (inner.lock.locked) {}
        inner.lock.locked = true;
        inner.lock.shared = true;
    }

    bool try_lock_shared() {
        if (inner.lock.locked) {
            return false;
        } else {
            inner.lock.locked = true;
            inner.lock.shared = true;
            return true;
        }
    }

    void unlock_shared() {
        if (inner.lock.shared && inner.lock.locked) {
            inner.lock.locked = false;
        }
    }
};

#endif
#else
#include <shared_mutex>
#endif
