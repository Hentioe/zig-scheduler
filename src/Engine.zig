const std = @import("std");
const Io = std.Io;
const Allocator = std.mem.Allocator;
const Job = @import("Job.zig");
const JobPriorityQueue = std.PriorityQueue(Job, void, Job.lessThan);
const Self = @This();

pub const log = std.log.scoped(.scheduler);
pub const Message = union(enum) {
    tick,
    add: Job,
};

io: Io,
allocator: Allocator,
receiver: Io.Queue(Message),
scheduler: ?Io.Future(void) = null,
buffer: []Message,
is_started: Io.Event = .unset,
active_pushes: std.atomic.Value(usize) = .init(0),

pub fn create(io: Io, allocator: Allocator) !*Self {
    const ptr = try allocator.create(Self);
    errdefer allocator.destroy(ptr);
    const buffer = try allocator.alloc(Message, 1024);
    errdefer allocator.free(buffer);
    ptr.* = .{
        .io = io,
        .allocator = allocator,
        .buffer = buffer,
        .receiver = .init(buffer),
    };

    return ptr;
}

pub fn destroy(self: *Self) void {
    std.debug.assert(self.is_started.isSet());
    self.receiver.close(self.io);
    if (self.scheduler) |*s| _ = s.cancel(self.io);
    while (self.active_pushes.load(.acquire) != 0) { // 等待所有正在推送的任务完成
        std.atomic.spinLoopHint();
    }
    self.allocator.free(self.buffer); // 释放 buffer 放在调度循环结束后，避免循环仍在取消息
    self.allocator.destroy(self);
}

pub fn start(self: *Self) !void {
    std.debug.assert(!self.is_started.isSet());
    self.scheduler = try self.io.concurrent(schedule, .{self});
    try self.is_started.wait(self.io);
}

/// 推送一个任务到引擎中。注意：调度器会借用任务，调用者保留任务实例的所有权。
pub fn push(self: *Self, job: Job) !void {
    _ = self.active_pushes.fetchAdd(1, .monotonic);
    defer _ = self.active_pushes.fetchSub(1, .release);

    if (!self.is_started.isSet()) return error.NotStarted;
    try self.receiver.putOne(self.io, .{ .add = job });
}

fn schedule(self: *Self) void {
    var store: JobPriorityQueue = .initContext({}); // 任务容器（最小堆）
    defer store.deinit(self.allocator);
    var timer: ?Io.Future(void) = null; // 定时器，定期唤醒（一次）调度
    defer if (timer) |*t| t.cancel(self.io);
    self.is_started.set(self.io); // 标记调度器已启动

    while (true) {
        const message = self.receiver.getOne(self.io) catch return; // 关闭或取消，直接跳出
        log.debug("Received message: {}", .{message});
        switch (message) {
            .tick => {}, // 醒来，执行检查
            .add => |job| { // 任务添加后
                store.push(self.allocator, job) catch |err| {
                    log.err("Failed to add job: {}", .{err});
                    continue; // 添加失败，忽略检查
                };
            },
        }

        // 启动所有到期任务
        const now = Io.Timestamp.now(self.io, .real);
        while (store.peek()) |top| {
            if (top.runAt().compare(.gt, now)) break; // 跳过未到期的
            _ = store.pop(); // 从顶部移除
            top.run(); // 执行任务
        }

        // 检查下一个任务
        if (timer) |*t| t.cancel(self.io); // 取消旧定时器
        if (store.peek()) |top| { // 如果堆顶还有任务，启动新的定时器
            timer = self.io.concurrent(alarm, .{ self, now.durationTo(top.runAt()) }) catch |err| {
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
