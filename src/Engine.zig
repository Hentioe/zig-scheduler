const std = @import("std");
const Io = std.Io;
const Allocator = std.mem.Allocator;
const Job = @import("Job.zig");
const Schedule = @import("Schedule.zig");
const Delay = @import("Delay.zig");
const Every = @import("Every.zig");
const Executor = @import("Executor.zig");
const Self = @This();

const Entry = struct {
    job: Job,
    at: Io.Timestamp,
    schedule: ?Schedule = null,

    fn lessThan(_: void, a: Entry, b: Entry) std.math.Order {
        return std.math.order(a.at.nanoseconds, b.at.nanoseconds);
    }
};
const EntryQueue = std.PriorityQueue(Entry, void, Entry.lessThan);

pub const StartError = Io.ConcurrentError || Io.Cancelable;
pub const PushError = Io.QueueClosedError || Io.Cancelable || error{NotStarted};

pub const log = std.log.scoped(.scheduler);
pub const Message = union(enum) {
    tick,
    add: Entry,
};

io: Io,
allocator: Allocator,
receiver: Io.Queue(Message),
loop_future: ?Io.Future(void) = null,
executor: *Executor,
buffer: []Message,
is_started: Io.Event = .unset,
active_pushes: std.atomic.Value(usize) = .init(0),

pub fn create(io: Io, allocator: Allocator) Allocator.Error!*Self {
    const ptr = try allocator.create(Self);
    errdefer allocator.destroy(ptr);
    const buffer = try allocator.alloc(Message, 1024);
    errdefer allocator.free(buffer);
    ptr.* = .{
        .io = io,
        .allocator = allocator,
        .buffer = buffer,
        .receiver = .init(buffer),
        .executor = try .create(io, allocator),
    };

    return ptr;
}

pub fn destroy(self: *Self) void {
    std.debug.assert(self.is_started.isSet());
    self.receiver.close(self.io);
    if (self.loop_future) |*s| _ = s.cancel(self.io);
    self.executor.destroy();
    while (self.active_pushes.load(.acquire) != 0) { // 等待所有正在推送的任务完成
        std.atomic.spinLoopHint();
    }
    self.allocator.free(self.buffer); // 释放 buffer 放在调度循环结束后，避免循环仍在取消息
    self.allocator.destroy(self);
}

pub fn start(self: *Self) StartError!void {
    std.debug.assert(!self.is_started.isSet());
    self.loop_future = try self.io.concurrent(loop, .{self});
    try self.executor.start();
    try self.is_started.wait(self.io);
}

/// 推送一个只执行一次的任务，在 `at` 时刻执行。
/// 注意：调度器会借用任务，调用者保留任务实例的所有权。
pub fn pushAt(self: *Self, job: Job, at: Io.Timestamp) PushError!void {
    return self.pushEntry(.{ .job = job, .at = at });
}

/// 推送一个 `Delay` 任务。
/// 注意：调度器会借用该任务，调用者必须保证它比本次调度存活更久。
pub fn pushDelay(self: *Self, delay: *Delay) PushError!void {
    return self.pushAt(delay.job(), delay.run_at);
}

/// 推送一个重复任务（recurring），首次在 `first` 时刻执行，之后由 `schedule` 计算下一次执行时间。
/// 注意：调度器会借用任务和调度器，调用者保留它们的所有权。
pub fn pushRecurring(self: *Self, job: Job, schedule: Schedule, first: Io.Timestamp) PushError!void {
    return self.pushEntry(.{ .job = job, .at = first, .schedule = schedule });
}

/// 推送一个 `Every` 固定间隔任务。
/// 注意：调度器会借用该任务，调用者必须保证它比本次调度存活更久。
pub fn pushEvery(self: *Self, every: *Every) PushError!void {
    return self.pushRecurring(every.job(), every.schedule(), every.first_at);
}

fn pushEntry(self: *Self, entry: Entry) PushError!void {
    _ = self.active_pushes.fetchAdd(1, .monotonic);
    defer _ = self.active_pushes.fetchSub(1, .release);

    if (!self.is_started.isSet()) return PushError.NotStarted;
    try self.receiver.putOne(self.io, .{ .add = entry });
}

fn loop(self: *Self) void {
    var store: EntryQueue = .initContext({}); // 任务容器（最小堆）
    defer store.deinit(self.allocator);
    var timer: ?Io.Future(void) = null; // 定时器，定期唤醒（一次）调度
    defer if (timer) |*t| t.cancel(self.io);
    self.is_started.set(self.io); // 标记调度器已启动

    while (true) {
        const message = self.receiver.getOne(self.io) catch return; // 关闭或取消，直接跳出
        log.debug("Received message: {}", .{message});
        switch (message) {
            .tick => {}, // 醒来，执行检查
            .add => |entry| { // 添加新的
                store.push(self.allocator, entry) catch |err| {
                    log.err("Failed to add job: {}", .{err});
                    continue; // 添加失败，忽略检查
                };
            },
        }

        // 启动所有到期任务
        const now = Io.Timestamp.now(self.io, .real);
        while (store.peek()) |entry| {
            if (entry.at.compare(.gt, now)) break; // 跳过未到期的
            _ = store.pop(); // 从顶部移除
            self.executor.submit(entry.job) catch |err| {
                log.err("Failed to submit job: {}", .{err});
                continue;
            };

            // 重复任务提交执行后，计算下一次调度时间重新入堆
            if (entry.schedule) |sched| {
                const next_at = sched.next(entry.at, now) orelse continue;
                if (!next_at.compare(.gt, entry.at)) { // 下一次调度时间没有推进，说明调度器有问题
                    log.err("Schedule did not advance: {}", .{entry.at});
                    continue;
                }
                store.push(self.allocator, .{
                    .job = entry.job,
                    .at = next_at,
                    .schedule = sched,
                }) catch |err| {
                    log.err("Failed to re-push job: {}", .{err});
                };
            }
        }

        // 检查下一个任务
        if (timer) |*t| t.cancel(self.io); // 取消旧定时器
        if (store.peek()) |top| { // 如果堆顶还有任务，启动新的定时器
            timer = self.io.concurrent(alarm, .{ self, now.durationTo(top.at) }) catch |err| {
                log.err("Failed to start alarm: {}", .{err});
                self.receiver.close(self.io); // 关闭队列，避免无意义阻塞
                break;
            };
        }
    }
}

fn alarm(self: *Self, delay: Io.Duration) void {
    self.io.sleep(delay, .awake) catch return; // 被取消就静默退出
    // 休眠结束，发送 tick 唤醒调度
    self.receiver.putOne(self.io, .tick) catch {};
}
