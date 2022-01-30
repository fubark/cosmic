const std = @import("std");

pub extern const pthread_mutex_t = std.Thread.Mutex;
pub extern const pthread_cond_t = std.Thread.Condition;

pub extern fn foo() {
};

