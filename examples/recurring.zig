const std = @import("std");
const Io = std.Io;
const scheduler = @import("zig_scheduler");
const Job = scheduler.Job;
const Schedule = scheduler.Schedule;

const Tick = struct {
    id: usize,

    pub fn run(self: *@This()) void {
        std.log.info("Recurring job {d} ran", .{self.id});
    }
};

/// 以固定周期重复执行，直到超过截止时间。
const Every = struct {
    interval: Io.Duration,
    deadline: Io.Timestamp,

    pub fn next(self: *const @This(), prev: Io.Timestamp, _: Io.Timestamp) ?Io.Timestamp {
        const next_at = prev.addDuration(self.interval);
        if (next_at.compare(.gt, self.deadline)) return null;
        return next_at;
    }
};

pub fn main(init: std.process.Init) !void {
    var sched = try scheduler.create(init.io, init.gpa);
    defer sched.destroy();
    try sched.start();

    const now = Io.Timestamp.now(init.io, .real);
    const interval: Io.Duration = .fromSeconds(1);
    const first = now.addDuration(interval);
    const every: Every = .{
        .interval = interval,
        .deadline = first.addDuration(.fromSeconds(4)),
    };

    // 每秒执行一次，共 5 次
    var tick: Tick = .{ .id = 1 };
    try sched.pushRecurring(Job.from(&tick), Schedule.from(&every), first);

    init.io.sleep(.fromSeconds(7), .awake) catch {};
}
