const std = @import("std");
const common = @import("common.zig");

fn read_sysfs(allocator: std.mem.Allocator, path: []const u8) !usize {
    const file = std.fs.openFileAbsolute(path, .{}) catch return 0;
    defer file.close();
    
    var buf_reader = std.io.bufferedReader(file.reader());
    var reader = buf_reader.reader();
    
    var line = std.ArrayList(u8).init(allocator);
    defer line.deinit();
    
    reader.streamUntilDelimiter(line.writer(), '\n', 1024) catch return 0;
    if (line.items.len == 0) return 0;
    
    var val: usize = 0;
    if (std.fmt.parseInt(usize, line.items, 10)) |num| {
        val = num;
    } else |_| {
        if (line.items[line.items.len-1] == 'K') {
            val = std.fmt.parseInt(usize, line.items[0..line.items.len-1], 10) catch 0;
            if (val > 0) val *= 1024;
        } else if (line.items[line.items.len-1] == 'M') {
            val = std.fmt.parseInt(usize, line.items[0..line.items.len-1], 10) catch 0;
            if (val > 0) val *= 1024 * 1024;
        }
    }
    return val;
}

pub fn detect(allocator: std.mem.Allocator) !common.CacheLayout {
    var layout = common.CacheLayout{ .source = "Linux sysfs" };
    
    layout.l1_size = try read_sysfs(allocator, "/sys/devices/system/cpu/cpu0/cache/index0/size");
    layout.l2_size = try read_sysfs(allocator, "/sys/devices/system/cpu/cpu0/cache/index2/size");
    layout.l3_size = try read_sysfs(allocator, "/sys/devices/system/cpu/cpu0/cache/index3/size");
    layout.line_size = try read_sysfs(allocator, "/sys/devices/system/cpu/cpu0/cache/index0/coherency_line_size");
    
    return layout;
}
