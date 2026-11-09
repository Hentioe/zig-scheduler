const std = @import("std");
const scheduler = @import("zig_scheduler");
const Delay = scheduler.Delay;

fn printId(context: ?*anyopaque) void {
    const id: *const usize = @ptrCast(@alignCast(context.?));
    std.log.info("Running delayed job {d}", .{id.*});
}

pub fn main(init: std.process.Init) !void {
    var first_id: usize = 1;
    var second_id: usize = 2;
    var sched = try scheduler.create(init.io, init.gpa);
    defer sched.destroy();
    try sched.start();

    var print1 = Delay.init(init.io, .fromSeconds(1), printId, &first_id);
    try sched.pushDelay(&print1);
    var print2 = Delay.init(init.io, .fromSeconds(3), printId, &second_id);
    try sched.pushDelay(&print2);

    init.io.sleep(.fromSeconds(5), .awake) catch {};
}
