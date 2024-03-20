const std = @import("std");
const ofw = @import("openfirmware");

comptime {
    ofw.entryPoint(main, &stack_bytes);
}

export var stack_bytes: [64 * 1024:0]u8 align(16) linksection(".bss") = undefined;

pub fn main() anyerror!void {
    try ofw.writer.print("All your {s} are belong to us.", .{"codebase"});
    try ofw.exit();
}
