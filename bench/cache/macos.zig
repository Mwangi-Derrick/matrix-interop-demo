const std = @import("std");
const common = @import("common.zig");

// Use @cImport for macOS sysctl — this is portable across Zig versions
// and avoids dependency on std.os.sysctlbyname which may be renamed/moved.
const c = @cImport({
    @cInclude("sys/sysctl.h");
});

fn getSysctlValue(name: [*:0]const u8) i64 {
    var val: i64 = 0;
    var size: usize = @sizeOf(i64);
    const result = c.sysctlbyname(name, &val, &size, null, 0);
    if (result != 0) return 0;
    return val;
}

pub fn detect(_: std.mem.Allocator) !common.CacheLayout {
    var layout = common.CacheLayout{ .source = "macOS sysctl" };

    const l1 = getSysctlValue("hw.l1dcachesize");
    const l2 = getSysctlValue("hw.l2cachesize");
    const l3 = getSysctlValue("hw.l3cachesize");
    const line = getSysctlValue("hw.cachelinesize");

    if (l1 > 0) layout.l1_size = @intCast(l1);
    if (l2 > 0) layout.l2_size = @intCast(l2);
    if (l3 > 0) layout.l3_size = @intCast(l3);
    if (line > 0) layout.line_size = @intCast(line);

    return layout;
}
