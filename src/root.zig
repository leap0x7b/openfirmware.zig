const std = @import("std");
const builtin = @import("builtin");

pub var ofw_call: *const fn (*Service) callconv(.C) c_int = undefined;
pub fn call(service: *Service) !void {
    const ret = ofw_call(service);
    if (ret == -1) {
        return error.SizeError;
    }
}

pub const Handle = anyopaque;
pub var root: *Handle = undefined;
pub var chosen: *Handle = undefined;
pub var stdout: *Handle = undefined;
pub var stdin: *Handle = undefined;

pub const Service = extern struct {
    service: [*:0]const u8,
    argument_count: usize,
    return_count: usize,
};

const WriteService = extern struct {
    service: Service = .{
        .service = "write",
        .argument_count = 3,
        .return_count = 1,
    },
    handle: *Handle,
    string: [*:0]const u8,
    length: usize,
    ret: usize = 0,
};

const FindDeviceService = extern struct {
    service: Service = .{
        .service = "finddevice",
        .argument_count = 1,
        .return_count = 1,
    },
    device: [*:0]const u8,
    handle: ?*Handle = null,
};

const ClaimService = extern struct {
    service: Service = .{
        .service = "claim",
        .argument_count = 3,
        .return_count = 1,
    },
    address: usize = 0,
    size: usize,
    alignment: usize,
    ret: usize = 0,
};

const ReleaseService = extern struct {
    service: Service = .{
        .service = "release",
        .argument_count = 2,
        .return_count = 0,
    },
    address: usize,
    size: usize,
};

const OpenService = extern struct {
    service: Service = .{
        .service = "open",
        .argument_count = 1,
        .return_count = 1,
    },
    device: [*:0]const u8,
    handle: ?*Handle = null,
};

pub fn exit() !void {
    var args = Service{
        .service = "exit",
        .argument_count = 0,
        .return_count = 0,
    };
    try call(&args);
}

pub fn write(handle: *Handle, string: [:0]const u8, length: usize) !usize {
    var args = WriteService{
        .handle = handle,
        .string = string.ptr,
        .length = length,
    };
    try call(@ptrCast(&args));
    return args.ret;
}

pub fn findDevice(name: [:0]const u8) !*Handle {
    var args = FindDeviceService{ .device = name.ptr };
    try call(@ptrCast(&args));
    if (args.handle) |handle|
        return handle
    else
        return error.DeviceNotFound;
}

pub fn getProperty(handle: *Handle, property: [:0]const u8, T: type, buffer: *T, length: usize) !usize {
    var args: extern struct {
        service: Service = .{
            .service = "getprop",
            .argument_count = 4,
            .return_count = 1,
        },
        handle: *Handle,
        property: [*:0]const u8,
        buffer: *T,
        length: usize,
        size: usize = 0,
    } = .{
        .handle = handle,
        .property = property.ptr,
        .buffer = buffer,
        .length = length,
    };
    try call(@ptrCast(&args));
    return args.size;
}

pub fn claim(size: usize, alignment: usize) !usize {
    var args = ClaimService{
        .size = size,
        .alignment = alignment,
    };
    try call(@ptrCast(&args));
    return args.ret;
}

pub fn release(address: usize, size: usize) !void {
    var args = ReleaseService{
        .address = address,
        .size = size,
    };
    try call(@ptrCast(&args));
}

pub fn open(name: [:0]const u8) !*Handle {
    var args = OpenService{ .device = name.ptr };
    try call(@ptrCast(&args));
    if (args.handle) |handle|
        return handle
    else
        return error.DeviceNotFound;
}

fn alloc(_: *anyopaque, size: usize, _: u8, _: usize) ?[*]u8 {
    return @ptrFromInt(claim(size, @alignOf([*]u8)) catch unreachable);
}

fn resize(_: *anyopaque, buffer: []u8, _: u8, new_size: usize, _: usize) bool {
    // TODO: resize
    _ = buffer;
    _ = new_size;
    return false;
}

fn free(_: *anyopaque, buf: []u8, _: u8, _: usize) void {
    release(@intFromPtr(buf.ptr), buf.len) catch unreachable;
}

pub const allocator = std.mem.Allocator{
    .ptr = undefined,
    .vtable = &.{
        .alloc = alloc,
        .resize = resize,
        .free = free,
    },
};

pub const writer = std.io.AnyWriter{
    .context = undefined,
    .writeFn = struct {
        pub fn w(_: *const anyopaque, string: []const u8) !usize {
            return write(stdout, try allocator.dupeZ(u8, string), string.len);
        }
    }.w,
};

pub fn entryPoint(comptime entrypoint: fn () anyerror!void, stack: []u8) void {
    switch (builtin.cpu.arch) {
        .powerpc => @export(struct {
            pub fn _start() callconv(.Naked) noreturn {
                asm volatile (
                    \\li %r2, 0
                    \\li %r13, 0
                    \\
                    \\lis %r10, __bss_start@ha
                    \\la %r10, __bss_start@l(%r10)
                    \\subi %r10, %r10, 4
                    \\lis %r11, _end@ha
                    \\la %r11, _end@l(%r11)
                    \\subi %r11, %r11, 4
                    \\li %r12, 0
                    \\
                    \\1:
                    \\cmpw 0, %r10, %r11
                    \\beq 2f
                    \\stwu %r12, 4(%r10)
                    \\b 1b
                    \\
                    \\2:
                    \\li %r10, 0
                    \\mtsrr1 %r10
                    \\bl __ofw_entry
                    \\
                    \\3: b 3b
                    :
                    : [_] "{r1}" (&stack[stack.len - 32]),
                );
            }
        }._start, .{ .name = "_start", .linkage = .Strong }),
        .powerpc64 => @export(struct {
            pub fn _start() callconv(.Naked) noreturn {
                asm volatile (
                    \\lis %r10, __bss_start@ha
                    \\la %r10, __bss_start@l(%r10)
                    \\subi %r10, %r10, 4
                    \\lis %r11, _end@ha
                    \\la %r11, _end@l(%r11)
                    \\subi %r11, %r11, 4
                    \\li %r12, 0
                    \\
                    \\1:
                    \\cmpw 0, %r10, %r11
                    \\beq 2f
                    \\stwu %r12, 4(%r10)
                    \\b 1b
                    \\
                    \\2:
                    \\mfmsr	%r10
                    \\mtsrr1 %r10
                    \\bl __ofw_entry
                    \\
                    \\3: b 3b
                    :
                    : [_] "{r1}" (&stack[stack.len - 512]),
                );
            }
        }._start, .{ .name = "_start", .linkage = .Strong }),
        else => @compileError("Unsupported architecture"),
    }

    @export(struct {
        pub fn entryPoint(r3: u32, r4: u32, call_ptr: *const fn (*Service) callconv(.C) c_int) callconv(.C) void {
            _ = r3;
            _ = r4;
            ofw_call = call_ptr;
            root = findDevice("/") catch unreachable;
            chosen = findDevice("/chosen") catch unreachable;
            _ = getProperty(chosen, "stdout", *Handle, &stdout, @sizeOf(*Handle)) catch unreachable;
            _ = getProperty(chosen, "stdin", *Handle, &stdin, @sizeOf(*Handle)) catch unreachable;
            entrypoint() catch unreachable;
        }
    }.entryPoint, .{ .name = "__ofw_entry", .linkage = .Strong });
}
