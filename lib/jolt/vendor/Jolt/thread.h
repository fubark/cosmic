#if defined(JPH_SINGLE_THREAD)
#ifndef _LIBCPP_THREAD
#define _LIBCPP_THREAD

#include <chrono>

typedef unsigned long int pthread_t;

class thread {
public:
    class id {
        pthread_t _M_thread;
    public:
        id(pthread_t __id) : _M_thread(__id) {}
        id() : _M_thread() {}

        inline bool operator==(id __y) {
            return _M_thread == __y._M_thread;
        }

        inline bool operator!=(id __y) {
            return _M_thread != __y._M_thread;
        }
    };
    thread() noexcept = default;
    static unsigned int hardware_concurrency() {
        return 1;
    }
    bool joinable() const {
        return false;
    }
    void join() {
    }
private:
    id _M_id;
};

namespace this_thread {
    inline thread::id get_id() {
        return thread::id(1);
    }

    template<class Rep, class Period>
    void sleep_for(const std::chrono::duration<Rep, Period>& sleep_duration) {
    }
}

#endif
#else
#include <thread>
#endif
