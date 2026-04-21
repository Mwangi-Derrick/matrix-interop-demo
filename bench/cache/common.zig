const std = @import("std");

pub const CacheLayout = struct {
    l1_size: usize = 0,
    l2_size: usize = 0,
    l3_size: usize = 0,
    line_size: usize = 64,
    source: []const u8 = "",

    pub fn format(self: CacheLayout, comptime fmt: []const u8, options: std.fmt.FormatOptions, writer: anytype) !void {
        _ = fmt;
        _ = options;
        try writer.print(
            \\--- CPU Cache Layout ---
            \\Detection Method: {s}
            \\L1 Data Cache:   {d: >6} KB
            \\L2 Cache:        {d: >6} KB
            \\L3 Cache:        {d: >6} MB
            \\Cache Line Size: {d: >6} bytes
            \\
        , .{
            self.source,
            self.l1_size / 1024,
            self.l2_size / 1024,
            self.l3_size / (1024 * 1024),
            self.line_size,
        });
    }
};

pub fn suggestBlockSize(layout: CacheLayout, comptime T: type) usize {
    const target_size = if (layout.l1_size > 0) layout.l1_size / 2 else 32768;
    
    // We want a square block (B x B) that fits in L1.
    // However, matrix multiply needs multiple tiles in L1 (A, B, and C).
    // So B * B * @sizeOf(T) * 3 should be <= L1 size.
    // Or roughly B = sqrt(L1_size / (3 * sizeOf(T)))
    
    const b = std.math.sqrt(target_size / (3 * @sizeOf(T)));
    
    // Round to nearest multiple of 8 for SIMD friendliness
    var aligned_b = (b / 8) * 8;
    if (aligned_b == 0) aligned_b = 8;
    
    return aligned_b;
}
