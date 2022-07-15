#if defined(JPH_SINGLE_THREAD)

#ifndef _LIBCPP_ATOMIC
#define _LIBCPP_ATOMIC

// Dummy implementation of atomics for single thread.

namespace std {

typedef enum memory_order {
    memory_order_relaxed,
    memory_order_consume,
    memory_order_acquire,
    memory_order_release,
    memory_order_acq_rel,
    memory_order_seq_cst
} memory_order;

template <typename T>
struct atomic_base {
    using value_type = T;
protected:
    T inner;

public:
    atomic_base(T val) : inner(val) {}
    atomic_base() = default;

    T load(memory_order order = memory_order_seq_cst) const {
        return inner;
    }

    void store(T desired, memory_order order = memory_order_seq_cst) {
        inner = desired;
    }

    T fetch_add(T arg, memory_order order = memory_order_seq_cst) {
        T last = inner;
        inner += arg;
        return last;
    }

    T fetch_sub(T arg, memory_order order = memory_order_seq_cst) {
        T last = inner;
        inner -= arg;
        return last;
    }

    T fetch_or(T arg, memory_order order = memory_order_seq_cst) {
        T last = inner;
        inner = inner | arg;
        return last;
    }

    T fetch_and(T arg, memory_order order = memory_order_seq_cst) {
        T last = inner;
        inner = inner & arg;
        return last;
    }

    T exchange(T desired, memory_order order = memory_order_seq_cst) {
        T last = inner;
        inner = desired;
        return last;
    }

    bool compare_exchange_weak(T& expected, T desired, memory_order order = memory_order_seq_cst) {
        if (inner == expected) {
            inner = desired;
            return true;
        } else {
            expected = inner;
            return false;
        }
    }

    bool compare_exchange_strong(T& expected, T desired, memory_order order = memory_order_seq_cst) {
        if (inner == expected) {
            inner = desired;
            return true;
        } else {
            expected = inner;
            return false;
        }
    }

    T operator=(T other) {
        inner = other;
        return inner;
    }

    operator T() const { return inner; }
};

template <typename T>
struct atomic : atomic_base<T> {
    using atomic_base<T>::atomic_base;
};

template <>
struct atomic<int> : atomic_base<int> {
public:
    using atomic_base<int>::atomic_base;

    int operator++() {
        this->inner++;
        return this->inner;
    }

    unsigned int operator++(int) {
        unsigned int last = this->inner;
        this->inner++;
        return last;
    }

    unsigned int operator-=(int rhs) {
        this->inner -= rhs;
        return this->inner;
    }
};

template <>
struct atomic<unsigned int> : atomic_base<unsigned int> {
public:
    using atomic_base<unsigned int>::atomic_base;
    atomic(int val) {
        inner = static_cast<unsigned int>(val);
    }

    unsigned int operator+=(unsigned int rhs) {
        this->inner += rhs;
        return this->inner;
    }

    unsigned int operator-=(int rhs) {
        this->inner -= rhs;
        return this->inner;
    }

    unsigned int operator--() {
        this->inner--;
        return this->inner;
    }

    unsigned int operator++() {
        this->inner++;
        return this->inner;
    }

    unsigned int operator++(int) {
        unsigned int last = this->inner;
        this->inner++;
        return last;
    }
};

template <>
struct atomic<unsigned short> : atomic_base<unsigned short> {
public:
    using atomic_base<unsigned short>::atomic_base;
    atomic(int val) {
        inner = static_cast<unsigned short>(val);
    }

    unsigned short operator+=(unsigned int rhs) {
        this->inner += rhs;
        return this->inner;
    }

    unsigned short operator|=(unsigned short rhs) {
        this->inner |= rhs;
        return this->inner;
    }

    unsigned short operator++() {
        this->inner++;
        return this->inner;
    }

    unsigned short operator++(int) {
        unsigned short last = this->inner;
        this->inner++;
        return last;
    }
};

template <>
struct atomic<unsigned char> : atomic_base<unsigned char> {
public:
    using atomic_base<unsigned char>::atomic_base;
    atomic(int val) {
        inner = static_cast<unsigned char>(val);
    }
};

template <>
struct atomic<long> : atomic_base<long> {
public:
    using atomic_base<long>::atomic_base;
    atomic(int val) {
        inner = static_cast<long>(val);
    }
};

template <>
struct atomic<unsigned long> : atomic_base<unsigned long> {
public:
    using atomic_base<unsigned long>::atomic_base;
    atomic(int val) {
        inner = static_cast<unsigned long>(val);
    }

    unsigned long operator++() {
        this->inner++;
        return this->inner;
    }

    unsigned long operator++(int) {
        unsigned long last = this->inner;
        this->inner++;
        return last;
    }
};

extern "C" void atomic_thread_fence(memory_order order);

}

#endif

#else
#include <atomic>
#endif
