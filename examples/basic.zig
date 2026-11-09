const std = @import("std");
const Io = std.Io;
const scheduler = @import("zig_scheduler");
const Job = scheduler.Job;

const PrintJob = struct {
    run_at: Io.Timestamp,

    pub fn init(run_at: Io.Timestamp) @This() {
        return .{ .run_at = run_at };
    }

    pub fn run(self: *@This()) void {
        std.log.info("Running job scheduled at: {any}", .{self.run_at});
    }
};

pub fn main(init: std.process.Init) !void {
    var sched = try scheduler.create(init.io, init.gpa);
    defer sched.destroy();
    try sched.start(); // 启动调度器

    const now = Io.Timestamp.now(init.io, .real);
    // 1 秒后的 job
    var job1 = PrintJob.init(now.addDuration(.fromSeconds(1)));
    try sched.pushAt(Job.from(&job1), job1.run_at);
    // 3 秒后的 job
    var job2 = PrintJob.init(now.addDuration(.fromSeconds(3)));
    try sched.pushAt(Job.from(&job2), job2.run_at);

    // 暂停 5 秒
    init.io.sleep(.fromSeconds(5), .awake) catch {};
}
