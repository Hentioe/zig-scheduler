const std = @import("std");
const Io = std.Io;
const scheduler = @import("zig_scheduler");
const Job = scheduler.Job;

pub fn main(init: std.process.Init) !void {
    var sched = try scheduler.create(init.io, init.gpa);
    defer sched.destroy();
    try sched.start(); // 启动调度器

    const now = Io.Timestamp.now(init.io, .real);
    // 1 秒后的 job
    const job1: Job = .{ .run_at = now.addDuration(.fromSeconds(1)) };
    try sched.push(job1);
    // 3 秒后的 job
    const job2: Job = .{ .run_at = now.addDuration(.fromSeconds(3)) };
    try sched.push(job2);

    // 暂停 5 秒
    init.io.sleep(.fromSeconds(5), .awake) catch {};
}
