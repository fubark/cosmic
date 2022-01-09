const std = @import("std");
const stdx = @import("stdx");
const ds = stdx.ds;
const log = stdx.log.scoped(.work_queue);
const builtin = @import("builtin");
const uv = @import("uv");

pub const WorkQueue = struct {
    const Self = @This();

    alloc: std.mem.Allocator,
    tasks_mutex: std.Thread.Mutex,
    tasks: ds.CompactUnorderedList(TaskId, TaskInfo),

    // Allocate the worker on the heap for now so the worker thread doesn't have to query for it.
    workers: std.ArrayList(*Worker),

    // Tasks in the ready queue can be picked up for work; their parent tasks have already completed.
    ready: std.atomic.Queue(TaskId),

    // Done queue holds tasks that have completed but haven't taken post steps (invoking callbacks and resolving deps)
    // This let's the main thread process them all without needing thread locks.
    done: std.atomic.Queue(TaskResult),

    // When workers have processed a task and added to done, wakeup event is set.
    // Must refer to the same memory address.
    done_notify: *std.Thread.ResetEvent,

    num_processing: u32,
    num_processing_mutex: std.Thread.Mutex,

    pub fn init(alloc: std.mem.Allocator, done_notify: *std.Thread.ResetEvent) Self {
        var new = Self{
            .alloc = alloc,
            .tasks_mutex = std.Thread.Mutex{},
            .tasks = ds.CompactUnorderedList(TaskId, TaskInfo).init(alloc),
            .ready = std.atomic.Queue(TaskId).init(),
            .done = std.atomic.Queue(TaskResult).init(),
            .workers = std.ArrayList(*Worker).init(alloc),
            .done_notify = done_notify,
            .num_processing = 0,
            .num_processing_mutex = std.Thread.Mutex{},
        };
        return new;
    }

    pub fn deinit(self: *Self) void {
        // Consume the tasks.
        while (self.done.get()) |n| {
            self.alloc.destroy(n);
        }
        while (self.ready.get()) |n| {
            self.alloc.destroy(n);
        }

        {
            self.tasks_mutex.lock();
            defer self.tasks_mutex.unlock();
            var iter = self.tasks.iterator();
            while (iter.next()) |task| {
                task.deinit(self.alloc);
            }
            self.tasks.deinit();
        }

        for (self.workers.items) |worker| {
            worker.deinit();
            self.alloc.destroy(worker);
        }
        self.workers.deinit();
    }

    /// An unfinished task can be in the following states:
    /// - currently in ready (not picked up by a worker)
    /// - currently being processed by a worker
    /// - currently in done queue but still hasn't done post processing (we check this for the last in-progress task that is marked done)
    /// This is useful to determine whether waiting for unfinished tasks will actually have a wakeup call.
    pub fn hasUnfinishedTasks(self: *Self) bool {
        self.num_processing_mutex.lock();
        defer self.num_processing_mutex.unlock();

        return !self.ready.isEmpty() or self.num_processing > 0 or !self.done.isEmpty();
    }

    fn getTaskInfo(self: *Self, id: TaskId) TaskInfo {
        self.tasks_mutex.lock();
        defer self.tasks_mutex.unlock();
        return self.tasks.get(id);
    }

    pub fn createAndRunWorker(self: *Self) void {
        const worker = self.alloc.create(Worker) catch unreachable;
        worker.init(self);
        self.workers.append(worker) catch unreachable;
        const thread = std.Thread.spawn(.{}, Worker.loop, .{worker}) catch unreachable;
        worker.thread = thread;
    }

    pub fn addTaskWithCb(self: *Self,
        task: anytype,
        ctx: anytype,
        comptime success_cb: fn (@TypeOf(ctx), TaskOutput(@TypeOf(task))) void,
        comptime failure_cb: fn (@TypeOf(ctx), anyerror) void,
    ) void {
        const Task = @TypeOf(task);
        const task_dupe = self.alloc.create(Task) catch unreachable;
        task_dupe.* = task;

        const ctx_dupe = self.alloc.create(@TypeOf(ctx)) catch unreachable;
        ctx_dupe.* = ctx;

        const task_info = TaskInfo.initWithCb(Task, task_dupe, ctx_dupe, success_cb, failure_cb);
        const task_id = self.tasks.add(task_info) catch unreachable;

        const task_node = self.alloc.create(std.atomic.Queue(TaskId).Node) catch unreachable;
        task_node.data = task_id;

        self.ready.put(task_node);

        for (self.workers.items) |worker| {
            worker.wakeup.set();
        }
    }

    /// Workers submit their results through this method.
    fn addTaskResult(self: *Self, res: TaskResult) void {
        // log.debug("task done processing", .{});

        // TODO: Ensure allocator is thread safe or use our own array list with lock.
        const res_node = self.alloc.create(std.atomic.Queue(TaskResult).Node) catch unreachable;
        res_node.data = res;
        self.done.put(res_node);

        {
            self.num_processing_mutex.lock();
            defer self.num_processing_mutex.unlock();
            self.num_processing -= 1;
        }

        // Notify that we have done tasks.
        self.done_notify.set();
    }

    pub fn processDone(self: *Self) void {
        while (self.done.get()) |n| {
            // log.debug("processed done task", .{});
            const task_id = n.data.task_id;
            const task_info = self.tasks.get(task_id);
            if (task_info.has_cb) {
                if (n.data.success) {
                    task_info.invokeSuccessCallback();
                } else {
                    task_info.invokeFailureCallback(n.data.err);
                }
            }
            self.alloc.destroy(n);

            task_info.deinit(self.alloc);

            self.tasks_mutex.lock();
            defer self.tasks_mutex.unlock();
            self.tasks.remove(task_id);
        }
    }
};

pub fn TaskOutput(comptime Task: type) type {
    return stdx.meta.FieldType(Task, .res);
}

// A thread is tied to a worker which simply requests the next task to work on.
const Worker = struct {
    const Self = @This();

    thread: std.Thread,

    queue: *WorkQueue,

    wakeup: std.Thread.ResetEvent,

    fn init(self: *Self, queue: *WorkQueue) void {
        self.* = .{
            .thread = undefined,
            .queue = queue,
            .wakeup = undefined,
        };
        self.wakeup.init() catch unreachable;
    }

    fn deinit(self: *Self) void {
        self.thread.detach();
        self.wakeup.deinit();
    }

    fn loop(self: *Self) void {
        while (true) {
            while (self.queue.ready.get()) |n| {
                {
                    self.queue.num_processing_mutex.lock();
                    defer self.queue.num_processing_mutex.unlock();
                    self.queue.num_processing += 1;
                }
                // log.debug("Worker on thread: {} received work", .{std.Thread.getCurrentId()});
                const task_id = n.data;
                self.queue.alloc.destroy(n);

                const task_info = self.queue.getTaskInfo(task_id);

                if (task_info.task.process()) {
                    self.queue.addTaskResult(.{
                        .task_id = task_id,
                        .success = true,
                        .err = undefined,
                    });
                } else |err| {
                    self.queue.addTaskResult(.{
                        .task_id = task_id,
                        .success = false,
                        .err = err,
                    });
                }
            }
            // Wait until the next task is added.
            self.wakeup.wait();
            self.wakeup.reset();
        }
    }
};

const TaskId = u32;

const TaskInfo = struct {
    const Self = @This();

    task: TaskIface,

    cb_ctx_ptr: *anyopaque,
    success_cb: fn(ctx_ptr: *anyopaque, ptr: *anyopaque) void,
    failure_cb: fn(ctx_ptr: *anyopaque, err: anyerror) void,

    deinit_fn: fn(self: Self, alloc: std.mem.Allocator) void,

    has_cb: bool,

    fn initWithCb(comptime TaskImpl: type, task_ptr: *TaskImpl, ctx_ptr: anytype,
        comptime success_cb: fn (std.meta.Child(@TypeOf(ctx_ptr)), TaskOutput(TaskImpl)) void,
        comptime failure_cb: fn (std.meta.Child(@TypeOf(ctx_ptr)), anyerror) void,
    ) Self {
        const Context = std.meta.Child(@TypeOf(ctx_ptr));
        const gen = struct {
            fn success_cb(_ctx_ptr: *anyopaque, ptr: *anyopaque) void {
                const ctx = stdx.mem.ptrCastAlign(*Context, _ctx_ptr);
                const orig_ptr = stdx.mem.ptrCastAlign(*TaskImpl, ptr);
                return @call(.{ .modifier = .always_inline }, success_cb, .{ ctx.*, orig_ptr.res });
            }

            fn failure_cb(_ctx_ptr: *anyopaque, err: anyerror) void {
                const ctx = stdx.mem.ptrCastAlign(*Context, _ctx_ptr);
                return @call(.{ .modifier = .always_inline }, failure_cb, .{ ctx.*, err });
            }

            fn deinit(self: Self, alloc: std.mem.Allocator) void {
                self.task.deinit();
                const orig_ptr = stdx.mem.ptrCastAlign(*TaskImpl, self.task.ptr);
                alloc.destroy(orig_ptr);
                const orig_ctx_ptr = stdx.mem.ptrCastAlign(*Context, self.cb_ctx_ptr);
                alloc.destroy(orig_ctx_ptr);
            }
        };
        return .{
            .task = TaskIface.init(task_ptr),
            .cb_ctx_ptr = ctx_ptr,
            .success_cb = gen.success_cb,
            .failure_cb = gen.failure_cb,
            .deinit_fn = gen.deinit,
            .has_cb = true,
        };
    }

    fn deinit(self: Self, alloc: std.mem.Allocator) void {
        self.deinit_fn(self, alloc);
    }

    fn invokeSuccessCallback(self: Self) void {
        self.success_cb(self.cb_ctx_ptr, self.task.ptr);
    }

    fn invokeFailureCallback(self: Self, err: anyerror) void {
        self.failure_cb(self.cb_ctx_ptr, err);
    }
};

const TaskIface = struct {
    const Self = @This();
    const VTable = struct {
        process: fn (ptr: *anyopaque) anyerror!void,
        deinit: fn (ptr: *anyopaque) void,
    };

    ptr: *anyopaque,
    vtable: *const VTable,

    pub fn init(impl_ptr: anytype) Self {
        const ImplPtr = @TypeOf(impl_ptr);
        const Impl = std.meta.Child(ImplPtr);

        const gen = struct {
            const vtable = VTable{
                .process = _process,
                .deinit = _deinit,
            };
            fn _process(ptr: *anyopaque) !void {
                const self = stdx.mem.ptrCastAlign(ImplPtr, ptr);
                return @call(.{ .modifier = .always_inline }, Impl.process, .{ self });
            }
            fn _deinit(ptr: *anyopaque) void {
                const self = stdx.mem.ptrCastAlign(ImplPtr, ptr);
                return @call(.{ .modifier = .always_inline }, Impl.deinit, .{ self });
            }
        };
        return .{
            .ptr = impl_ptr,
            .vtable = &gen.vtable,
        };
    }

    fn process(self: Self) !void {
        return self.vtable.process(self.ptr);
    }

    fn deinit(self: Self) void {
        self.vtable.deinit(self.ptr);
    }
};

const TaskResult = struct {
    task_id: TaskId,
    success: bool,
    err: anyerror,
};