const std = @import("std");
const process = std.process;
const builtin = @import("builtin");

pub fn main() !void {
    // Get allocator
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    const repo_url = "https://github.com/haleth-embershield/http-zerver";
    const repo_dir = "http-zerver";
    const assets_dir = "assets";

    // Create assets directory if it doesn't exist
    try std.fs.cwd().makePath(assets_dir);

    std.debug.print("Setting up http-zerver...\n", .{});

    // Clone repository using git
    std.debug.print("Cloning http-zerver repository...\n", .{});
    {
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

    // Change directory to repo
    try process.changeCurDir(repo_dir);

    // Build http-zerver
    std.debug.print("Building http-zerver...\n", .{});
    {
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

    // Change back to parent directory
    try process.changeCurDir("..");

    // Copy the executable to assets directory
    std.debug.print("Copying http-zerver executable to assets directory...\n", .{});
    const exe_name = if (builtin.target.os.tag == .windows) "http-zerver.exe" else "http-zerver";
    const src_path = try std.fs.path.join(allocator, &[_][]const u8{ repo_dir, "zig-out", "bin", exe_name });
    defer allocator.free(src_path);
    const dst_path = try std.fs.path.join(allocator, &[_][]const u8{ assets_dir, exe_name });
    defer allocator.free(dst_path);

    try std.fs.copyFileAbsolute(src_path, dst_path, .{});

    // Delete the repository directory
    std.debug.print("Cleaning up...\n", .{});
    try std.fs.deleteTreeAbsolute(repo_dir);

    std.debug.print("Setup complete! http-zerver has been copied to the assets directory.\n", .{});
}
