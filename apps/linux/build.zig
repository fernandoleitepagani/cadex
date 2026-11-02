//! The Linux app (plan 18): Zig, GTK4 on Wayland, the core through its C API.
//! GTK/Pango live behind shared/system/gtk_shim.c; that shim owns the system
//! headers because GLib 2.88 does not survive translate-c.

const std = @import("std");

pub fn build(b: *std.Build) void {
    // The core and the app must use the same libc: both default to the host
    // with the baseline CPU. Cross builds pass -Dtarget to both.
    if (b.graph.host.result.os.tag != .linux) @panic("apps/linux builds on Linux");
    const target = b.standardTargetOptions(.{ .default_target = .{ .cpu_model = .baseline } });
    const optimize = b.standardOptimizeOption(.{});
    const core_lib = b.option([]const u8, "core-lib", "libcadex.a for this target") orelse
        "../../core/zig-out/lib/libcadex.a";

    const include_paths = pkgFlags(b, &.{ "pkg-config", "--cflags-only-I", "gtk4" }, "-I");
    const lib_paths = pkgFlags(b, &.{ "pkg-config", "--libs-only-L", "gtk4" }, "-L");
    const lib_names = pkgFlags(b, &.{ "pkg-config", "--libs-only-l", "gtk4" }, "-l");

    // The C shim: GTK4, GDK, Pango and GLib, compiled by the C compiler.
    // WebKitGTK is optional: without its development package the preview page
    // explains how to enable it instead of failing the build.
    var webkit_code: u8 = 0;
    _ = b.runAllowFail(&.{ "pkg-config", "--exists", "webkitgtk-6.0" }, &webkit_code, .ignore) catch "";
    const has_webkit = webkit_code == 0;
    var adw_code: u8 = 0;
    _ = b.runAllowFail(&.{ "pkg-config", "--exists", "libadwaita-1" }, &adw_code, .ignore) catch "";
    if (adw_code != 0) @panic("libadwaita-1 is required (install libadwaita-devel)");
    const shim_module = b.createModule(.{ .target = target, .optimize = optimize, .link_libc = true });
    shim_module.addCSourceFile(.{ .file = b.path("shared/system/gtk_shim.c"), .flags = &.{"-std=c11"} });
    for (include_paths) |path| shim_module.addIncludePath(.{ .cwd_relative = path });
    shim_module.addCMacro("CADEX_HAS_ADW", "1");
    const adw_includes = pkgFlags(b, &.{ "pkg-config", "--cflags-only-I", "libadwaita-1" }, "-I");
    for (adw_includes) |path| shim_module.addIncludePath(.{ .cwd_relative = path });
    if (has_webkit) {
        shim_module.addCMacro("CADEX_HAS_WEBKIT", "1");
        const webkit_includes = pkgFlags(b, &.{ "pkg-config", "--cflags-only-I", "webkitgtk-6.0" }, "-I");
        for (webkit_includes) |path| shim_module.addIncludePath(.{ .cwd_relative = path });
    }
    const shim = b.addLibrary(.{ .name = "cadex-gtk-shim", .linkage = .static, .root_module = shim_module });

    const system = b.createModule(.{
        .root_source_file = b.path("shared/system/system.zig"),
        .target = target,
        .optimize = optimize,
        .link_libc = true,
    });
    system.addIncludePath(b.path("shared/system"));

    const cadex = b.addTranslateC(.{
        .root_source_file = b.path("../../core/include/cadex.h"),
        .target = target,
        .optimize = optimize,
    }).createModule();

    const terminal = b.createModule(.{
        .root_source_file = b.path("features/terminal/terminal.zig"),
        .target = target,
        .optimize = optimize,
        .link_libc = true,
        .imports = &.{.{ .name = "cadex", .module = cadex }},
    });

    const documents = b.createModule(.{
        .root_source_file = b.path("features/documents/documents.zig"),
        .target = target,
        .optimize = optimize,
        .link_libc = true,
        .imports = &.{.{ .name = "cadex", .module = cadex }},
    });

    const root = b.createModule(.{
        .root_source_file = b.path("app/main.zig"),
        .target = target,
        .optimize = optimize,
        .link_libc = true,
        .imports = &.{
            .{ .name = "cadex", .module = cadex },
            .{ .name = "system", .module = system },
            .{ .name = "terminal", .module = terminal },
            .{ .name = "documents", .module = documents },
        },
    });
    linkCore(root, b.pathFromRoot(core_lib));
    // The pkg-config flags put GTK in the local prefix; glib/cairo and the
    // rest stay in the system multiarch libdir, which Zig does not search
    // once an explicit -L exists.
    const system_libdir = b.run(&.{ "pkg-config", "--variable=libdir", "glib-2.0" });
    root.addLibraryPath(.{ .cwd_relative = std.mem.trimEnd(u8, system_libdir, "\n") });
    for (lib_paths) |path| root.addLibraryPath(.{ .cwd_relative = path });
    for (lib_names) |name| root.linkSystemLibrary(name, .{});
    const adw_lib_paths = pkgFlags(b, &.{ "pkg-config", "--libs-only-L", "libadwaita-1" }, "-L");
    const adw_lib_names = pkgFlags(b, &.{ "pkg-config", "--libs-only-l", "libadwaita-1" }, "-l");
    for (adw_lib_paths) |path| root.addLibraryPath(.{ .cwd_relative = path });
    for (adw_lib_names) |name| root.linkSystemLibrary(name, .{});
    if (has_webkit) {
        const webkit_lib_paths = pkgFlags(b, &.{ "pkg-config", "--libs-only-L", "webkitgtk-6.0" }, "-L");
        const webkit_lib_names = pkgFlags(b, &.{ "pkg-config", "--libs-only-l", "webkitgtk-6.0" }, "-l");
        for (webkit_lib_paths) |path| root.addLibraryPath(.{ .cwd_relative = path });
        for (webkit_lib_names) |name| root.linkSystemLibrary(name, .{});
    }
    root.linkLibrary(shim);

    const exe = b.addExecutable(.{ .name = "cadex", .root_module = root });
    b.installArtifact(exe);

    const documents_test = b.addTest(.{ .root_module = documents });
    const run_documents_test = b.addRunArtifact(documents_test);
    const test_step = b.step("test", "Run the Linux app's unit tests");
    test_step.dependOn(&run_documents_test.step);

    const run = b.addRunArtifact(exe);
    b.step("run", "Build and run Cadex").dependOn(&run.step);
}

fn linkCore(module: *std.Build.Module, core_lib: []const u8) void {
    module.addObjectFile(.{ .cwd_relative = core_lib });
    // simdutf/highway inside libcadex.a are C++.
    module.link_libcpp = true;
}

fn pkgFlags(b: *std.Build, args: []const []const u8, prefix: []const u8) []const []const u8 {
    const output = b.run(args);
    var list: std.ArrayList([]const u8) = .empty;
    var it = std.mem.tokenizeAny(u8, output, " \t\n");
    while (it.next()) |token| {
        if (!std.mem.startsWith(u8, token, prefix)) continue;
        list.append(b.allocator, token[prefix.len..]) catch @panic("OOM");
    }
    return list.items;
}
