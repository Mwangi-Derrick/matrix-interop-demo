const std = @import("std");
const common = @import("common.zig");

const win32 = std.os.windows;

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
    ProcessorMask: usize,
    Relationship: u32,
    Payload: extern union {
        ProcessorCore: extern struct {
            Flags: u8,
        },
        NumaNode: extern struct {
            NodeNumber: u32,
        },
        Cache: CACHE_DESCRIPTOR,
        Reserved: [2]u64,
    },
};

///The string like "kernel32" names the specific dynamic library (.dll on Windows, .so on Linux) the linker should search in to find the function to call.
/// 
/// Windows ships with hundreds of dynamic linked libraries (DLLs) as part of the OS.
/// The Core Windows DLLs You'll Encounter
    // kernel32.dll - Core system functions (memory, processes, threads, the function you're using)

    // user32.dll - Window management, UI elements, message passing

    // gdi32.dll - Graphics drawing (lines, shapes, text)

    // ntdll.dll - Low-level NT kernel interface (most functions end up here)

    // advapi32.dll - Security, registry, event logging

    // Every Windows machine from Windows 95 to Windows 11 ships with these DLLs in C:\Windows\System32\. They're the actual implementation of the Win32 API.

    // What This Means for Your Zig Code
    // When you write:

    // zig
    // extern "kernel32" fn GetLogicalProcessorInformation(...);
    // You're telling the Zig linker: "Insert a stub that jumps into kernel32.dll at runtime." That's it. No static linking, no copying the function's code into your .exe. Just a reference that Windows will resolve when your program loads.
/// 
/// 


extern "kernel32" fn GetLogicalProcessorInformation(
    Buffer: ?[*]SYSTEM_LOGICAL_PROCESSOR_INFORMATION,
    ReturnedLength: *win32.DWORD,
) callconv(std.builtin.CallingConvention.winapi) win32.BOOL;

pub fn detect(allocator: std.mem.Allocator) !common.CacheLayout {
    var layout = common.CacheLayout{ .source = "Windows API" };
    
    var buffer_size: win32.DWORD = 0;
    _ = GetLogicalProcessorInformation(null, &buffer_size);
    
    if (buffer_size > 0) {
        const num_elements = buffer_size / @sizeOf(SYSTEM_LOGICAL_PROCESSOR_INFORMATION);
        const buffer = try allocator.alloc(SYSTEM_LOGICAL_PROCESSOR_INFORMATION, num_elements);
        defer allocator.free(buffer);
        
        if (GetLogicalProcessorInformation(buffer.ptr, &buffer_size) != 0) {
            for (buffer) |info| {
                if (info.Relationship == RelationCache) {
                    const cache = info.Payload.Cache;
                    switch (cache.Level) {
                        1 => {
                            // Only take data cache or unified cache for L1
                            if (cache.Type == .Data or cache.Type == .Unified) {
                                layout.l1_size = cache.Size;
                            }
                        },
                        2 => layout.l2_size = cache.Size,
                        3 => layout.l3_size = cache.Size,
                        else => {},
                    }
                    if (cache.LineSize > 0) {
                        layout.line_size = cache.LineSize;
                    }
                }
            }
        }
    }
    return layout;
}
