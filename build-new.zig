const std = @import("std");

// This is the build script for our MP4 Parser WebAssembly project
pub fn build(b: *std.Build) void {
    // Standard target options for WebAssembly
    const target = b.standardTargetOptions(.{
        .default_target = .{
            .cpu_arch = .wasm32,
            .os_tag = .freestanding,
        },
    });

    // Standard optimization options
    const optimize = b.standardOptimizeOption(.{});

    // Create an executable that compiles to WebAssembly
    // For WebAssembly, we use addExecutable instead of addSharedLibrary
    const exe = b.addExecutable(.{
        .name = "mp4_parser",
        .root_source_file = b.path("src/mp4_parser.zig"),
        .target = target,
        .optimize = optimize,
    });

    // Important WASM-specific settings
    exe.rdynamic = true;

    // Disable entry point for WebAssembly
    exe.entry = .disabled;

    // Make sure all exported functions are available
    // Note: In Zig 0.13.0, functions marked with 'export' are automatically exported
    // We don't need to explicitly list them, but we're documenting them here:
    // - addData
    // - parseMP4
    // - logBytes
    // - logBytesAtPosition
    // - resetBuffer
    // - getBufferUsed

    // Install in the output directory
    b.installArtifact(exe);

    // Clear and recreate the www directory
    const clear_www = b.addRemoveDirTree("www");
    const make_www = b.addSystemCommand(&[_][]const u8{ "mkdir", "www" });
    make_www.step.dependOn(&clear_www.step);

    // Create a step to copy the WASM file to the www directory
    const copy_wasm = b.addInstallBinFile(exe.getEmittedBin(), "www/mp4_parser.wasm");
    copy_wasm.step.dependOn(b.getInstallStep());
    copy_wasm.step.dependOn(&make_www.step);

    // Create a step to copy all files from the assets directory to the www directory
    const copy_assets = b.addInstallDirectory(.{
        .source_dir = b.path("assets"),
        .install_dir = .{ .custom = "www" },
        .install_subdir = "",
    });
    copy_assets.step.dependOn(&make_www.step);

    // Build and run the setup_zerver executable
    const setup_zerver = b.addExecutable(.{
        .name = "setup_zerver",
        .root_source_file = b.path("setup_zerver.zig"),
        .target = b.host,
        .optimize = optimize,
    });

    const run_setup = b.addRunArtifact(setup_zerver);
    run_setup.step.dependOn(&setup_zerver.step);

    // Add a run step to start http-zerver
    const server_path = if (@import("builtin").target.os.tag == .windows)
        "www\\http-zerver.exe"
    else
        "www/http-zerver";

    const run_cmd = b.addSystemCommand(&[_][]const u8{
        server_path,
        "8000",
        ".",
        "-v",
    });
    run_cmd.cwd = b.path("www");
    run_cmd.step.dependOn(&copy_wasm.step);
    run_cmd.step.dependOn(&copy_assets.step);
    run_cmd.step.dependOn(&run_setup.step);

    const run_step = b.step("run", "Build, deploy, and start HTTP server");
    run_step.dependOn(&run_cmd.step);

    // Add a deploy step that only copies the files without starting the server
    const deploy_step = b.step("deploy", "Build and copy files to www directory");
    deploy_step.dependOn(&copy_wasm.step);
    deploy_step.dependOn(&copy_assets.step);
}
