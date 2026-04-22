const std = @import("std");
const common = @import("common.zig");

fn read_sysfs(path: []const u8) usize {
    const file = std.fs.openFileAbsolute(path, .{}) catch return 0;
    defer file.close();

    // Read up to 64 bytes — sysfs values are small
    var buf: [64]u8 = undefined;
    const len = file.read(&buf) catch return 0;
    if (len == 0) return 0;

    // Trim trailing whitespace/newlines
    var trimmed = buf[0..len];
    while (trimmed.len > 0 and (trimmed[trimmed.len - 1] == '\n' or trimmed[trimmed.len - 1] == '\r' or trimmed[trimmed.len - 1] == ' ')) {
        trimmed = trimmed[0 .. trimmed.len - 1];
    }
    if (trimmed.len == 0) return 0;

    // Try plain integer first
    if (std.fmt.parseInt(usize, trimmed, 10)) |num| {
        return num;
    } else |_| {}

    // Try with K suffix (e.g. "32K")
    if (trimmed[trimmed.len - 1] == 'K') {
        if (std.fmt.parseInt(usize, trimmed[0 .. trimmed.len - 1], 10)) |num| {
            return num * 1024;
        } else |_| {}
    }

    // Try with M suffix (e.g. "3M")
    if (trimmed[trimmed.len - 1] == 'M') {
        if (std.fmt.parseInt(usize, trimmed[0 .. trimmed.len - 1], 10)) |num| {
            return num * 1024 * 1024;
        } else |_| {}
    }

    return 0;
}

pub fn detect(_: std.mem.Allocator) !common.CacheLayout {
    var layout = common.CacheLayout{ .source = "Linux sysfs" };

    layout.l1_size = read_sysfs("/sys/devices/system/cpu/cpu0/cache/index0/size");
    layout.l2_size = read_sysfs("/sys/devices/system/cpu/cpu0/cache/index2/size");
    layout.l3_size = read_sysfs("/sys/devices/system/cpu/cpu0/cache/index3/size");
    layout.line_size = read_sysfs("/sys/devices/system/cpu/cpu0/cache/index0/coherency_line_size");

    return layout;
}
