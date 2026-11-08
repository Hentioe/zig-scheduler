const std = @import("std");
const scheduler = @import("zig_scheduler");
const Job = scheduler.Job;
const DelayJob = scheduler.DelayJob;

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

    var job1 = DelayJob.init(init.io, .fromSeconds(1), printId, &first_id);
    try sched.push(Job.from(&job1));
    var job2 = DelayJob.init(init.io, .fromSeconds(3), printId, &second_id);
    try sched.push(Job.from(&job2));

    init.io.sleep(.fromSeconds(5), .awake) catch {};
}
