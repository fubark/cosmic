#if defined(JPH_SINGLE_THREAD)
#ifndef _LIBCPP_MUTEX
#define _LIBCPP_MUTEX

#include <system_error>

#define __SIZEOF_PTHREAD_MUTEX_T 40

namespace std {

typedef union mutex_t {
    char __size[__SIZEOF_PTHREAD_MUTEX_T];
    bool locked;
} mutex_t;

template<typename Mutex>
class unique_lock {
private:
    Mutex*	_M_device;
    bool		_M_owns;
public:
    unique_lock() : _M_device(0), _M_owns(false) {}

    explicit unique_lock(Mutex& __m) : _M_device(std::addressof(__m)), _M_owns(false) {
	    lock();
    }

    ~unique_lock() {
        if (_M_owns)
            unlock();
    }

    void lock() {
	    _M_device->lock();
	    _M_owns = true;
	}

    void unlock() {
	    if (!_M_owns) {
            throw std::system_error(int(std::errc::operation_not_permitted), std::system_category());
	    } else if (_M_device) {
	        _M_device->unlock();
            _M_owns = false;
        }
    }
};

class mutex {
public:
    mutex() {
        inner.locked = false;
    }

    bool try_lock() {
        if (inner.locked) {
            return false;
        } else {
            inner.locked = true;
            return true;
        }
    }

    void lock() {
        while (inner.locked) {}
        inner.locked = true;
    }

    void unlock() {
        inner.locked = false;
    }
private:
    mutex_t inner;
};

template<typename Mutex>
class lock_guard {
public:
    explicit lock_guard(Mutex& __m) : _M_device(__m) {
        _M_device.lock();
    }
 
    //lock_guard(Mutex& __m, adopt_lock_t) : _M_device(__m)
    //{ } // calling thread owns mutex
 
    ~lock_guard() {
        _M_device.unlock();
    }
 
    lock_guard(const lock_guard&) = delete;
    lock_guard& operator=(const lock_guard&) = delete;
private:
    Mutex&  _M_device;
};

struct once_flag {
    constexpr once_flag() noexcept;

    once_flag(const once_flag&) = delete;
    once_flag& operator=(const once_flag&) = delete;
};

}

#endif

#else
#include <mutex>
#endif
