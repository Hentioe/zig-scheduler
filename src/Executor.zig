const std = @import("std");
const Io = std.Io;
const Allocator = std.mem.Allocator;
const Job = @import("Job.zig");
const Self = @This();

pub const StartError = Io.ConcurrentError || Io.Cancelable;
pub const SubmitError = Io.ConcurrentError || error{NotStarted};

pub const log = std.log.scoped(.executor);
const Field = union(enum) { job, wait };

io: Io,
allocator: Allocator,
buffer: []Field,
futures: Io.Select(Field),
is_started: Io.Event = .unset,

pub fn create(io: Io, allocator: Allocator) Allocator.Error!*Self {
    const ptr = try allocator.create(Self);
    errdefer allocator.destroy(ptr);
    const buffer = try allocator.alloc(Field, 1024);
    errdefer allocator.free(buffer);
    ptr.* = .{
        .io = io,
        .allocator = allocator,
        .buffer = buffer,
        .futures = .init(io, buffer),
    };

    return ptr;
}

pub fn destroy(self: *Self) void {
    _ = self.futures.cancel();
    self.allocator.free(self.buffer);
    self.allocator.destroy(self);
}

pub fn start(self: *Self) StartError!void {
    try self.futures.concurrent(.job, wait, .{self});
    try self.is_started.wait(self.io);
}

pub fn submit(self: *Self, job: Job) SubmitError!void {
    if (!self.is_started.isSet()) return SubmitError.NotStarted;
    try self.futures.concurrent(.job, Job.run, .{job});
}

fn wait(self: *Self) void {
    self.is_started.set(self.io);
    while (true) {
        const field = self.futures.await() catch break;
        switch (field) {
            .job => log.debug("Job completed", .{}),
            else => {},
        }
    }
}
