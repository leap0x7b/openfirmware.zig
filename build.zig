const std = @import("std");

pub fn build(b: *std.Build) !void {
    const target = b.standardTargetOptions(.{
        .default_target = .{
            .cpu_arch = .powerpc,
            .os_tag = .freestanding,
            .abi = .none,
        },
        .whitelist = &.{
            .{ .cpu_arch = .powerpc, .os_tag = .freestanding, .abi = .none },
            .{ .cpu_arch = .powerpc64, .os_tag = .freestanding, .abi = .none },
            .{ .cpu_arch = .powerpcle, .os_tag = .freestanding, .abi = .none },
            .{ .cpu_arch = .powerpc64le, .os_tag = .freestanding, .abi = .none },
        },
    });
    const optimize = b.standardOptimizeOption(.{});

    const module = b.addModule("openfirmware", .{
        .root_source_file = .{ .path = "src/root.zig" },
        .target = target,
        .optimize = optimize,
    });

    const exe = b.addExecutable(.{
        .name = "example.elf",
        .root_source_file = .{ .path = "src/main.zig" },
        .target = target,
        .optimize = optimize,
    });
    exe.setLinkerScript(.{ .path = "src/linker.ld" });
    exe.root_module.addImport("openfirmware", module);
    b.installArtifact(exe);

    const cmd = &[_][]const u8{
        // zig fmt: off
        "/bin/sh", "-c",
        try std.mem.concat(b.allocator, u8, &[_][]const u8{
            "rm -rf zig-out/iso/root && ",
            "mkdir -p zig-out/iso/root/boot && ",
            "cp zig-out/bin/example.elf zig-out/iso/root/boot && ",
            "cp src/boot/ofboot.b zig-out/iso/root/boot && ",
            "mkisofs -quiet -chrp-boot -hfs -part -U -T -r -l -J -sysid PPC ",
                "-A \"Barebones\" -V \"Barebones\" ",
                "-volset 1 -volset-size 1 -volset-seqno 1 ",
                "-hfs-volid \"Barebones\" -hfs-bless zig-out/iso/root/boot ",
                "-map src/boot/hfs.map -no-desktop -allow-multidot ",
                "-o zig-out/iso/barebones.iso zig-out/iso/root",
        }),
        // zig fmt: on
    };

    const iso_cmd = b.addSystemCommand(cmd);
    iso_cmd.step.dependOn(b.getInstallStep());

    const iso_step = b.step("iso", "Generate a bootable Limine ISO file");
    iso_step.dependOn(&iso_cmd.step);

    const run_cmd = b.addSystemCommand(&[_][]const u8{
        // zig fmt: off
        switch (target.result.cpu.arch) {
            .powerpc, .powerpcle => "qemu-system-ppc",
            .powerpc64, .powerpc64le => "qemu-system-ppc64",
            else => return error.UnsupportedArch,
        },
        "-M", "mac99",
        "-m", "512M",
        "-cdrom", "zig-out/iso/barebones.iso",
        "-boot", "d",
        "-serial", "stdio",
        // zig fmt: on
    });
    run_cmd.step.dependOn(iso_step);

    const run_step = b.step("run", "Boot ISO in QEMU");
    run_step.dependOn(&run_cmd.step);

    const unit_tests = b.addTest(.{
        .root_source_file = .{ .path = "src/root.zig" },
        .target = target,
        .optimize = optimize,
    });
    const run_unit_tests = b.addRunArtifact(unit_tests);

    const test_step = b.step("test", "Run unit tests");
    test_step.dependOn(&run_unit_tests.step);
}
