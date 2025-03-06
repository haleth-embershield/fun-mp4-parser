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

    // Create a step to clear the www directory
    const clear_www = b.addSystemCommand(&[_][]const u8{ "powershell", "-Command", "if (Test-Path www) { Remove-Item -Path www\\* -Recurse -Force }; if (-not (Test-Path www)) { New-Item -ItemType Directory -Path www }" });

    // Create a step to copy the WASM file to the www directory
    const copy_wasm = b.addSystemCommand(&[_][]const u8{
        "powershell",                                        "-Command",            "Copy-Item",
        b.fmt("{s}/bin/mp4_parser.wasm", .{b.install_path}), "www/mp4_parser.wasm",
    });
    copy_wasm.step.dependOn(b.getInstallStep());
    copy_wasm.step.dependOn(&clear_www.step);

    // Create a step to copy all files from the assets directory to the www directory
    const copy_assets = b.addSystemCommand(&[_][]const u8{ "powershell", "-Command", "if (Test-Path assets) { Copy-Item -Path assets\\* -Destination www\\ -Recurse -Force }" });
    copy_assets.step.dependOn(&clear_www.step);

    // Add a run step to start a Python HTTP server
    // Try both 'py' and 'python' commands to be compatible with different systems
    // const run_cmd = b.addSystemCommand(&[_][]const u8{ "powershell", "-Command", "cd www; try { py -m http.server 8000 } catch { python -m http.server 8000 }" });
    // Check if http-zerver exists and run setup if needed
    const check_and_setup_server = b.addSystemCommand(&[_][]const u8{
        "powershell",
        "-Command",
        "if (-not (Test-Path assets/http-zerver.exe)) { Write-Host 'http-zerver not found. Running setup...'; .\\setup_http_server.ps1 }",
    });

    // Add a run step to start http-zerver
    const run_cmd = b.addSystemCommand(&[_][]const u8{ "powershell", "-Command", "cd www; ./http-zerver.exe 8000 . -v" });
    run_cmd.step.dependOn(&copy_wasm.step);
    run_cmd.step.dependOn(&copy_assets.step);
    run_cmd.step.dependOn(&check_and_setup_server.step);

    const run_step = b.step("run", "Build, deploy, and start HTTP server");
    run_step.dependOn(&run_cmd.step);

    // Add a deploy step that only copies the files without starting the server
    const deploy_step = b.step("deploy", "Build and copy files to www directory");
    deploy_step.dependOn(&copy_wasm.step);
    deploy_step.dependOn(&copy_assets.step);
}
