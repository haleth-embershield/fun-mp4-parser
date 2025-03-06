const std = @import("std");
const process = std.process;
const builtin = @import("builtin");

pub fn main() !void {
    // Get allocator
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    // Get absolute path of current directory
    const cwd = try std.fs.cwd().realpathAlloc(allocator, ".");
    defer allocator.free(cwd);

    const repo_url = "https://github.com/haleth-embershield/http-zerver";
    const repo_dir = try std.fs.path.join(allocator, &[_][]const u8{ cwd, "http-zerver" });
    defer allocator.free(repo_dir);
    const assets_dir = try std.fs.path.join(allocator, &[_][]const u8{ cwd, "assets" });
    defer allocator.free(assets_dir);
    const www_dir = try std.fs.path.join(allocator, &[_][]const u8{ cwd, "www" });
    defer allocator.free(www_dir);

    // Create directories if they don't exist
    std.fs.makeDirAbsolute(assets_dir) catch |err| switch (err) {
        error.PathAlreadyExists => {}, // Directory already exists, which is fine
        else => return err, // Other errors should be propagated
    };
    std.fs.makeDirAbsolute(www_dir) catch |err| switch (err) {
        error.PathAlreadyExists => {}, // Directory already exists, which is fine
        else => return err, // Other errors should be propagated
    };

    // Check if http-zerver already exists in assets directory
    const exe_name = if (builtin.os.tag == .windows) "http-zerver.exe" else "http-zerver";
    const server_path = try std.fs.path.join(allocator, &[_][]const u8{ assets_dir, exe_name });
    defer allocator.free(server_path);

    if (std.fs.accessAbsolute(server_path, .{})) |_| {
        std.debug.print("http-zerver detected in assets directory, skipping setup...\n", .{});
        return;
    } else |_| {}

    std.debug.print("Setting up http-zerver...\n", .{});

    // Clean up existing http-zerver directory if it exists
    std.debug.print("Cleaning up any existing http-zerver directory...\n", .{});
    if (std.fs.accessAbsolute(repo_dir, .{})) |_| {
        try std.fs.deleteTreeAbsolute(repo_dir);
    } else |_| {}

    // Clone repository using git
    std.debug.print("Cloning http-zerver repository...\n", .{});
    {
        // Change to the root directory before cloning
        try process.changeCurDir(cwd);

        const git_args = &[_][]const u8{ "git", "clone", repo_url };
        const result = try process.Child.run(.{
            .allocator = allocator,
            .argv = git_args,
        });
        defer allocator.free(result.stdout);
        defer allocator.free(result.stderr);

        if (result.term.Exited != 0) {
            std.debug.print("Failed to clone repository: {s}\n", .{result.stderr});
            return error.GitCloneFailed;
        }
    }

    // Build http-zerver
    std.debug.print("Building http-zerver...\n", .{});
    {
        // Change to the repo directory for building
        try process.changeCurDir(repo_dir);

        const build_args = &[_][]const u8{ "zig", "build" };
        const result = try process.Child.run(.{
            .allocator = allocator,
            .argv = build_args,
        });
        defer allocator.free(result.stdout);
        defer allocator.free(result.stderr);

        if (result.term.Exited != 0) {
            std.debug.print("Failed to build http-zerver: {s}\n", .{result.stderr});
            return error.BuildFailed;
        }
    }

    // Change back to root directory
    try process.changeCurDir(cwd);

    // Copy the executable to assets directory
    std.debug.print("Copying http-zerver executable to assets directory...\n", .{});

    const src_path = try std.fs.path.join(allocator, &[_][]const u8{ repo_dir, "zig-out", "bin", exe_name });
    defer allocator.free(src_path);

    try std.fs.copyFileAbsolute(src_path, server_path, .{});

    // Delete the repository directory
    std.debug.print("Cleaning up...\n", .{});
    try std.fs.deleteTreeAbsolute(repo_dir);

    std.debug.print("Setup complete! http-zerver has been copied to the assets directory.\n", .{});
}
