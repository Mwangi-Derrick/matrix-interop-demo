const std = @import("std");
const builtin = @import("builtin");

pub const common = @import("cache/common.zig");
pub const CacheLayout = common.CacheLayout;
pub const suggestBlockSize = common.suggestBlockSize;

const windows = @import("cache/windows.zig");
const linux = @import("cache/linux.zig");
const macos = @import("cache/macos.zig");

pub fn detect(allocator: std.mem.Allocator) !CacheLayout {
    var layout: CacheLayout = switch (builtin.os.tag) {
        .windows => try windows.detect(allocator),
        .linux => try linux.detect(allocator),
        .macos, .ios => try macos.detect(allocator),
        else => CacheLayout{ .source = "Unsupported OS" },
    };

    // Fallback if detection failed or OS unsupported
    if (layout.l1_size == 0) {
        layout.l1_size = 32768; // 32KB default
        if (layout.source.len == 0 or std.mem.eql(u8, layout.source, "Unsupported OS")) {
            layout.source = "Fallback (Default Values)";
        } else {
            const new_source = try std.mem.concat(allocator, u8, &[_][]const u8{ layout.source, " (with Fallback)" });
            layout.source = new_source;
        }
    }
    if (layout.l2_size == 0) layout.l2_size = 262144; // 256KB default
    if (layout.l3_size == 0) layout.l3_size = 8388608; // 8MB default

    return layout;
}
