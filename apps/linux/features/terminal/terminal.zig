//! The core terminal behind the GTK view: one session, its callbacks and the
//! small wrappers the app needs (frame, keys, mouse, search, clipboard).

const std = @import("std");
const c = @import("cadex");

pub const Events = struct {
    user: *anyopaque,
    output: *const fn (user: ?*anyopaque) callconv(.c) void,
    exit: *const fn (user: ?*anyopaque, code: i32) callconv(.c) void,
    title: *const fn (user: ?*anyopaque) callconv(.c) void,
    bell: *const fn (user: ?*anyopaque) callconv(.c) void,
};

pub const Link = struct {
    kind: u8,
    target: []u8,
};

pub const Terminal = struct {
    handle: *c.cadex_terminal,
    events: Events,

    pub fn open(allocator: std.mem.Allocator, cols: u16, rows: u16, cwd: ?[]const u8, events: Events) !*Terminal {
        const self = try allocator.create(Terminal);
        errdefer allocator.destroy(self);
        self.* = .{ .handle = undefined, .events = events };

        var options = std.mem.zeroes(c.cadex_terminal_options);
        options.cols = cols;
        options.rows = rows;
        options.context = self;
        options.on_output = onOutput;
        options.on_exit = onExit;
        options.on_title = onTitle;
        options.on_bell = onBell;
        options.history_lines = 10_000;
        options.on_local_url = null;

        var cwd_z: ?[:0]u8 = null;
        if (cwd) |dir| {
            cwd_z = try allocator.dupeZ(u8, dir);
            options.cwd = cwd_z.?.ptr;
        }
        defer if (cwd_z) |z| allocator.free(z);

        var handle: ?*c.cadex_terminal = null;
        const status = c.cadex_terminal_open(&options, &handle);
        if (status != c.CADEX_OK or handle == null) return error.OpenFailed;
        self.handle = handle.?;
        return self;
    }

    pub fn close(self: *Terminal, allocator: std.mem.Allocator) void {
        c.cadex_terminal_close(self.handle);
        allocator.destroy(self);
    }

    pub fn updateFrame(self: *Terminal) ?*const c.cadex_terminal_frame {
        var frame: ?*const c.cadex_terminal_frame = null;
        if (c.cadex_terminal_update_frame(self.handle, &frame) != c.CADEX_OK) return null;
        return frame;
    }

    pub fn resize(self: *Terminal, cols: u16, rows: u16, cell_width: u16, cell_height: u16) void {
        _ = c.cadex_terminal_resize(self.handle, cols, rows, cell_width, cell_height);
    }

    pub fn write(self: *Terminal, bytes: []const u8) void {
        if (bytes.len == 0) return;
        _ = c.cadex_terminal_write(self.handle, bytes.ptr, bytes.len);
    }

    pub fn key(self: *Terminal, key_code: u16, mods: u8, text: []const u8, unshifted: u32) void {
        const text_ptr: ?[*]const u8 = if (text.len == 0) null else text.ptr;
        _ = c.cadex_terminal_key(self.handle, key_code, mods, text_ptr, text.len, unshifted);
    }

    pub fn paste(self: *Terminal, bytes: []const u8) void {
        if (bytes.len == 0) return;
        _ = c.cadex_terminal_paste(self.handle, bytes.ptr, bytes.len);
    }

    pub fn scrollTop(self: *Terminal) void {
        _ = c.cadex_terminal_scroll_to(self.handle, c.CADEX_SCROLL_TOP);
    }

    pub fn scrollBottom(self: *Terminal) void {
        _ = c.cadex_terminal_scroll_to(self.handle, c.CADEX_SCROLL_BOTTOM);
    }

    pub fn scroll(self: *Terminal, rows: i32) void {
        _ = c.cadex_terminal_scroll(self.handle, rows);
    }

    pub fn mouseTracking(self: *Terminal) u8 {
        return c.cadex_terminal_mouse_tracking(self.handle);
    }

    pub fn mouse(self: *Terminal, event: *const c.cadex_terminal_mouse_event) void {
        _ = c.cadex_terminal_mouse(self.handle, event);
    }

    pub fn wheel(self: *Terminal, event: *const c.cadex_terminal_mouse_event, rows: i32) void {
        _ = c.cadex_terminal_wheel(self.handle, event, rows);
    }

    pub fn focus(self: *Terminal, focused: bool) void {
        _ = c.cadex_terminal_focus(self.handle, focused);
    }

    pub fn selectPress(self: *Terminal, pointer: *const c.cadex_terminal_pointer, clicks: u8, extend: bool) void {
        _ = c.cadex_terminal_select_press(self.handle, pointer, clicks, extend);
    }

    pub fn selectDrag(self: *Terminal, pointer: *const c.cadex_terminal_pointer) void {
        var autoscroll: i8 = 0;
        _ = c.cadex_terminal_select_drag(self.handle, pointer, &autoscroll);
    }

    pub fn selectRelease(self: *Terminal, pointer: *const c.cadex_terminal_pointer) void {
        _ = c.cadex_terminal_select_release(self.handle, pointer);
    }

    pub fn selectAll(self: *Terminal) void {
        _ = c.cadex_terminal_select_all(self.handle);
    }

    pub fn hasSelection(self: *Terminal) bool {
        return c.cadex_terminal_has_selection(self.handle);
    }

    pub fn copySelection(self: *Terminal, allocator: std.mem.Allocator) ?[]u8 {
        var ptr: ?[*]u8 = null;
        var len: usize = 0;
        if (c.cadex_terminal_copy_selection(self.handle, &ptr, &len) != c.CADEX_OK) return null;
        const p = ptr orelse return null;
        defer c.cadex_free(@ptrCast(p));
        if (len == 0) return null;
        return allocator.dupe(u8, p[0..len]) catch null;
    }

    pub fn copyWorkingDirectory(self: *Terminal, allocator: std.mem.Allocator) ?[]u8 {
        var ptr: ?[*]u8 = null;
        var len: usize = 0;
        if (c.cadex_terminal_copy_working_directory(self.handle, &ptr, &len) != c.CADEX_OK) return null;
        const p = ptr orelse return null;
        defer c.cadex_free(@ptrCast(p));
        if (len == 0) return null;
        return allocator.dupe(u8, p[0..len]) catch null;
    }

    pub fn copyTitle(self: *Terminal, allocator: std.mem.Allocator) ?[]u8 {
        var ptr: ?[*]u8 = null;
        var len: usize = 0;
        if (c.cadex_terminal_copy_title(self.handle, &ptr, &len) != c.CADEX_OK) return null;
        const p = ptr orelse return null;
        defer c.cadex_free(@ptrCast(p));
        if (len == 0) return null;
        return allocator.dupe(u8, p[0..len]) catch null;
    }

    pub fn searchStart(self: *Terminal, needle: []const u8) void {
        _ = c.cadex_terminal_search_start(self.handle, needle.ptr, needle.len);
    }

    pub fn searchStop(self: *Terminal) void {
        c.cadex_terminal_search_stop(self.handle);
    }

    pub fn searchSelect(self: *Terminal, direction: u8) bool {
        var found = false;
        _ = c.cadex_terminal_search_select(self.handle, direction, &found);
        return found;
    }

    pub fn linkAt(self: *Terminal, allocator: std.mem.Allocator, col: u16, row: u16) ?Link {
        var link: c.cadex_terminal_link = undefined;
        var ptr: ?[*]u8 = null;
        var len: usize = 0;
        if (c.cadex_terminal_link_at(self.handle, col, row, &link, &ptr, &len) != c.CADEX_OK) return null;
        if (link.kind == c.CADEX_LINK_NONE) return null;
        const p = ptr orelse return null;
        defer c.cadex_free(@ptrCast(p));
        const target = allocator.dupe(u8, p[0..len]) catch return null;
        return .{ .kind = link.kind, .target = target };
    }

    pub fn setColors(self: *Terminal, colors: *const c.cadex_terminal_colors) void {
        _ = c.cadex_terminal_set_colors(self.handle, colors);
    }

    pub fn setCursor(self: *Terminal, shape: u8, blink: bool) void {
        _ = c.cadex_terminal_set_cursor(self.handle, shape, blink);
    }
};

fn onOutput(context: ?*anyopaque) callconv(.c) void {
    const self: *Terminal = @ptrCast(@alignCast(context.?));
    self.events.output(self.events.user);
}

fn onExit(context: ?*anyopaque, code: i32) callconv(.c) void {
    const self: *Terminal = @ptrCast(@alignCast(context.?));
    self.events.exit(self.events.user, code);
}

fn onTitle(context: ?*anyopaque) callconv(.c) void {
    const self: *Terminal = @ptrCast(@alignCast(context.?));
    self.events.title(self.events.user);
}

fn onBell(context: ?*anyopaque) callconv(.c) void {
    const self: *Terminal = @ptrCast(@alignCast(context.?));
    self.events.bell(self.events.user);
}
