const std = @import("std");

pub fn build(b: *std.Build) void {
    const target = b.standardTargetOptions(.{});
    const optimize = b.standardOptimizeOption(.{});

    // CURSED Compiler executable (full implementation)
    const cursed_exe = b.addExecutable(.{
        .name = "cursed-compiler",
        .root_module = b.createModule(.{
            .root_source_file = b.path("src-zig/cursed_compiler_main.zig"),
            .target = target,
            .optimize = optimize,
        }),
    });
    
    cursed_exe.linkLibC();
    
    // No longer need external LLVM libraries - using Zig's built-in LLVM IR builder
    // This enables cross-platform compilation including Windows

    // Install the executable
    b.installArtifact(cursed_exe);

    // CURSED Formatter executable
    const fmt_exe = b.addExecutable(.{
        .name = "cursed-fmt",
        .root_module = b.createModule(.{
            .root_source_file = b.path("src-zig/formatter.zig"),
            .target = target,
            .optimize = optimize,
        }),
    });
    fmt_exe.linkLibC();
    b.installArtifact(fmt_exe);

    // CURSED Linter executable
    const lint_exe = b.addExecutable(.{
        .name = "cursed-lint",
        .root_module = b.createModule(.{
            .root_source_file = b.path("src-zig/linter.zig"),
            .target = target,
            .optimize = optimize,
        }),
    });
    lint_exe.linkLibC();
    b.installArtifact(lint_exe);

    // Create a run step for the compiler
    const run_cmd = b.addRunArtifact(cursed_exe);
    run_cmd.step.dependOn(b.getInstallStep());

    if (b.args) |args| {
        run_cmd.addArgs(args);
    }

    const run_step = b.step("run", "Run the CURSED compiler");
    run_step.dependOn(&run_cmd.step);
}
