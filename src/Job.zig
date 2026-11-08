const std = @import("std");
const Io = std.Io;
const Self = @This();

run_at: Io.Timestamp,

pub fn init(run_at: Io.Timestamp) Self {
    return .{
        .run_at = run_at,
    };
}

pub fn run(self: *const Self) void {
    std.log.info("Running job scheduled at: {any}", .{self.run_at});
}

pub fn lessThan(_: void, a: Self, b: Self) std.math.Order {
    return std.math.order(a.run_at.nanoseconds, b.run_at.nanoseconds);
}
