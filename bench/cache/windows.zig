const std = @import("std");
const common = @import("common.zig");

const RelationCache = 2;
const PROCESSOR_CACHE_TYPE = enum(c_int) {
    Unified = 0,
    Instruction = 1,
    Data = 2,
    Trace = 3,
};

const CACHE_DESCRIPTOR = extern struct {
    Level: u8,
    Associativity: u8,
    LineSize: u16,
    Size: u32,
    Type: PROCESSOR_CACHE_TYPE,
};

const SYSTEM_LOGICAL_PROCESSOR_INFORMATION = extern struct {
    ProcessorMask: u32,
    Relationship: u32,
    Cache: CACHE_DESCRIPTOR,
};

pub fn detect(allocator: std.mem.Allocator) !common.CacheLayout {
    var layout = common.CacheLayout{ .source = "Windows API" };
    
    const win32 = std.os.windows;
    var buffer_size: win32.DWORD = 0;
    _ = win32.kernel32.GetLogicalProcessorInformation(null, &buffer_size);
    
    if (buffer_size > 0) {
        const buffer = try allocator.alloc(u8, buffer_size);
        defer allocator.free(buffer);
        
        if (win32.kernel32.GetLogicalProcessorInformation(@ptrCast(buffer.ptr), &buffer_size) != 0) {
            const info_ptr = @as([*]SYSTEM_LOGICAL_PROCESSOR_INFORMATION, @ptrCast(buffer.ptr));
            for (0..buffer_size / @sizeOf(SYSTEM_LOGICAL_PROCESSOR_INFORMATION)) |i| {
                const info = info_ptr[i];
                if (info.Relationship == RelationCache) {
                    switch (info.Cache.Level) {
                        1 => layout.l1_size = info.Cache.Size,
                        2 => layout.l2_size = info.Cache.Size,
                        3 => layout.l3_size = info.Cache.Size,
                        else => {},
                    }
                    layout.line_size = info.Cache.LineSize;
                }
            }
        }
    }
    return layout;
}
