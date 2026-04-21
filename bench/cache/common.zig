const std = @import("std");

pub const CacheLayout = struct {
    l1_size: usize = 0,
    l2_size: usize = 0,
    l3_size: usize = 0,
    line_size: usize = 64,
    source: []const u8 = "",
    
    // Hierarchical block sizes
    l1_block: usize = 32,
    l2_block: usize = 64,
    l3_block: usize = 256,

    pub fn format(self: CacheLayout, _: []const u8, _: std.fmt.FormatOptions, writer: anytype) !void {
        try writer.print(
            \\--- CPU Cache Hierarchy ---
            \\Detection:     {s}
            \\L1 Data Cache: {d: >6} KB (Inner:  {d})
            \\L2 Cache:      {d: >6} KB (Middle: {d})
            \\L3 Cache:      {d: >6} MB (Outer:  {d})
            \\Line Size:     {d: >6} bytes
            \\
        , .{
            self.source,
            self.l1_size / 1024,
            self.l1_block,
            self.l2_size / 1024,
            self.l2_block,
            self.l3_size / (1024 * 1024),
            self.l3_block,
            self.line_size,
        });
    }
};

pub fn suggestBlockSizes(layout: *CacheLayout) void {
    // L3 block: 95% of L3 (register micro-kernel reduces cache pressure)
    const l3_usable = (layout.l3_size * 95) / 100;
    //why divide by 12?
    // 4x4 C tile = 16 floats = 64 bytes
    // 4x4 B tile = 16 floats = 64 bytes
    // 4x4 A tile = 16 floats = 64 bytes
    // Total = 192 bytes
    // 192 / 64 = 3 cache lines
    // 3 * 4 = 12
    const l3_raw = @sqrt(@as(f64, @floatFromInt(l3_usable)) / 12.0);
    layout.l3_block = @max(64, (@as(usize, @intFromFloat(l3_raw)) / 8) * 8);

    // L2 block: 95% of L2
    const l2_usable = (layout.l2_size * 95) / 100;
    const l2_raw = @sqrt(@as(f64, @floatFromInt(l2_usable)) / 12.0);
    layout.l2_block = @max(32, (@as(usize, @intFromFloat(l2_raw)) / 8) * 8);

    // L1 block: 100% of L1 (4x4 C tile lives in registers, not L1)
    const l1_usable = (layout.l1_size * 100) / 100;
    const l1_raw = @sqrt(@as(f64, @floatFromInt(l1_usable)) / 12.0);
    layout.l1_block = @max(8, (@as(usize, @intFromFloat(l1_raw)) / 8) * 8);
    
    // Safety clamps
    if (layout.l1_block > layout.l2_block) layout.l1_block = layout.l2_block;
    if (layout.l2_block > layout.l3_block) layout.l2_block = layout.l3_block;
}
