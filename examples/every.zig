const std = @import("std");
const scheduler = @import("zig_scheduler");
const Every = scheduler.Every;

fn printTick(context: ?*anyopaque) void {
    const id: *const usize = @ptrCast(@alignCast(context.?));
    std.log.info("Every job {d} ran", .{id.*});
}

pub fn main(init: std.process.Init) !void {
    var id: usize = 1;
    var sched = try scheduler.create(init.io, init.gpa);
    defer sched.destroy();
    try sched.start();

    var every = Every.init(init.io, .fromSeconds(1), printTick, &id);
    try sched.pushEvery(&every);

    // 每秒执行一次，共观察到 5 次
    init.io.sleep(.fromSeconds(6), .awake) catch {};
}
