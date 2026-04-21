const std = @import("std");
const common = @import("common.zig");

pub fn detect(_: std.mem.Allocator) !common.CacheLayout {
    var layout = common.CacheLayout{ .source = "macOS sysctl" };
    
    var size: usize = @sizeOf(i64);
    var val: i64 = 0;
    
    if (std.os.sysctlbyname("hw.l1dcachesize", &val, &size, null, 0) == 0)
        layout.l1_size = @intCast(val);
    if (std.os.sysctlbyname("hw.l2cachesize", &val, &size, null, 0) == 0)
        layout.l2_size = @intCast(val);
    if (std.os.sysctlbyname("hw.l3cachesize", &val, &size, null, 0) == 0)
        layout.l3_size = @intCast(val);
    if (std.os.sysctlbyname("hw.cachelinesize", &val, &size, null, 0) == 0)
        layout.line_size = @intCast(val);
        
    return layout;
}
