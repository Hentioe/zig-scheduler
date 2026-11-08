const std = @import("std");
const Io = std.Io;
const Job = @import("Job.zig");
const Self = @This();

// todo: 支持自动移除任务

io: Io,
futures: Io.Group = .init,

pub fn init(io: Io) Self {
    return .{ .io = io };
}

pub fn deinit(self: *Self) void {
    self.futures.await(self.io) catch {};
}

pub fn submit(self: *Self, job: Job) !void {
    try self.futures.concurrent(self.io, Job.run, .{job});
}
