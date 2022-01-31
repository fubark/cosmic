const std = @import("std");

pub extern const pthread_mutex_t = std.Thread.Mutex;
pub extern const pthread_cond_t = std.Thread.Condition;

pub extern fn pthread_mutex_lock(mutex: *pthread_mutex_t) c_int {
    mutex.lock();
    return 0;
}

pub extern fn pthread_mutex_unlock(mutex: *pthread_mutex_t) c_int {
    mutex.unlock();
    return 0;
}
