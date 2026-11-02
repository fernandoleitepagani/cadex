//! Cadex on Linux: one Wayland window, one terminal, GTK4 through the shim.

const std = @import("std");
const core = @import("cadex");
const system = @import("system");
const terminal = @import("terminal");

const c = system.c;

const FONT = "Monospace 12";
const PAD: i32 = 8;

// GdkModifierType bits.
const SHIFT: c_uint = 1 << 0;
const CONTROL: c_uint = 1 << 2;
const ALT: c_uint = 1 << 3;
const SUPER: c_uint = 1 << 26;

// Cell flags, matching core/include/cadex.h.
const F_BOLD: u16 = 1 << 0;
const F_ITALIC: u16 = 1 << 1;
const F_SPACER: u16 = 1 << 5;
const F_HAS_BACKGROUND: u16 = 1 << 6;
const F_SELECTED: u16 = 1 << 7;
const F_MATCH: u16 = 1 << 11;
const F_MATCH_CURRENT: u16 = 1 << 12;

const CURSOR_BLOCK: u8 = 0;
const CURSOR_BAR: u8 = 1;
const CURSOR_UNDERLINE: u8 = 2;
const CURSOR_BLOCK_HOLLOW: u8 = 3;

const Launch = struct {
    cwd: ?[]u8,
    background: bool,
};

const App = struct {
    gpa: std.mem.Allocator,
    window: *anyopaque,
    area: *anyopaque,
    entry: *anyopaque,
    term: ?*terminal.Terminal = null,
    frame: ?*const core.cadex_terminal_frame = null,
    cell_w: i32 = 8,
    cell_h: i32 = 16,
    ascent: i32 = 12,
    cols: u16 = 80,
    rows: u16 = 24,
    width: i32 = 800,
    height: i32 = 600,
    redraw_pending: std.atomic.Value(bool) = .init(false),
    search_open: bool = false,
    closing: bool = false,
};

pub fn main() !void {
    if (std.c.getenv("WAYLAND_DISPLAY") == null) {
        std.debug.print("Cadex requires Wayland; WAYLAND_DISPLAY is not set.\n", .{});
        std.process.exit(1);
    }
    _ = c.cadex_set_wayland();

    const gpa = std.heap.c_allocator;
    // Zig 0.16 moved argsAlloc to std.Io; Run 2 opens the directory the app
    // was started in (the shell inherits it). A CLI directory arrives with
    // the multi-tab shell in Run 3.
    const launch = try gpa.create(Launch);
    launch.* = .{
        .cwd = null,
        .background = std.c.getenv("CADEX_BACKGROUND") != null,
    };

    const gtk_app = c.cadex_app_new() orelse {
        std.debug.print("cadex: cannot create the GTK application\n", .{});
        std.process.exit(1);
    };
    c.cadex_app_activate(gtk_app, onActivate, launch);
    const status = c.cadex_app_run(gtk_app);
    std.process.exit(@intCast(status));
}

fn onActivate(app: ?*anyopaque, user: ?*anyopaque) callconv(.c) void {
    const gtk_app = app orelse return;
    const launch: *Launch = @ptrCast(@alignCast(user.?));
    create(launch, gtk_app) catch |err| {
        std.debug.print("cadex: cannot open the window: {}\n", .{err});
        c.cadex_app_quit(gtk_app);
    };
}

fn create(launch: *Launch, gtk_app: *anyopaque) !void {
    const gpa = std.heap.c_allocator;
    const app = try gpa.create(App);
    app.* = .{
        .gpa = gpa,
        .window = undefined,
        .area = undefined,
        .entry = undefined,
    };

    app.window = c.cadex_window_new(gtk_app, "Cadex", 1000, 700) orelse return error.GtkFailed;
    const header = c.cadex_header_new(app.window) orelse return error.GtkFailed;
    _ = c.cadex_header_button(header, "Quit", quitClicked, app);
    const box = c.cadex_window_box(app.window) orelse return error.GtkFailed;
    app.entry = c.cadex_entry_new() orelse return error.GtkFailed;
    app.area = c.cadex_drawing_new() orelse return error.GtkFailed;

    c.cadex_entry_changed(app.entry, entryChanged, app);
    c.cadex_entry_activate(app.entry, entryActivate, app);
    c.cadex_entry_escape(app.entry, entryEscape, app);
    c.cadex_box_append(box, app.entry);
    c.cadex_box_append(box, app.area);
    c.cadex_widget_expand(app.area);
    c.cadex_drawing_draw(app.area, draw, app);
    c.cadex_drawing_input(app.area, key, commit, app);
    c.cadex_drawing_mouse(app.area, pointer, scroll, app);
    c.cadex_window_on_close(app.window, closeCb, app);

    var cw: c_int = 8;
    var ch: c_int = 16;
    var asc: c_int = 12;
    _ = c.cadex_text_metrics(app.area, FONT, &cw, &ch, &asc);
    app.cell_w = if (cw > 0) cw else 8;
    app.cell_h = if (ch > 0) ch else 16;
    app.ascent = if (asc > 0) asc else 12;

    app.term = terminal.Terminal.open(gpa, 80, 24, launch.cwd, .{
        .user = app,
        .output = onOutput,
        .exit = onExit,
        .title = onTitle,
        .bell = onBell,
    }) catch |err| {
        std.debug.print("cadex: cannot start the shell: {}\n", .{err});
        c.cadex_window_close(app.window);
        return;
    };

    var colors = std.mem.zeroes(core.cadex_terminal_colors);
    colors.background = 0x1e1e1e;
    colors.foreground = 0xd4d4d4;
    colors.cursor = 0xffffff;
    colors.ansi = .{
        0x1e1e1e, 0xcd3131, 0x0dbc79, 0xe5e510,
        0x2472c8, 0xbc3fbc, 0x11a8cd, 0xe5e5e5,
        0x666666, 0xf14c4c, 0x23d18b, 0xf5f543,
        0x3b8eea, 0xd670d6, 0x29b8db, 0xffffff,
    };
    app.term.?.setColors(&colors);
    app.term.?.setCursor(CURSOR_BLOCK, true);

    c.cadex_window_present(app.window, @intFromBool(launch.background));
    c.cadex_widget_focus(app.area);
    c.cadex_im_focus(app.area, 1);
}

fn scheduleRedraw(app: *App) void {
    if (!app.redraw_pending.swap(true, .acq_rel)) c.cadex_idle(redrawIdle, app);
}

fn redrawIdle(user: ?*anyopaque) callconv(.c) void {
    const app: *App = @ptrCast(@alignCast(user.?));
    app.redraw_pending.store(false, .release);
    if (!app.closing) c.cadex_queue_draw(app.area);
}

fn quitClicked(user: ?*anyopaque) callconv(.c) void {
    const app: *App = @ptrCast(@alignCast(user.?));
    c.cadex_window_close(app.window);
}

fn closeCb(user: ?*anyopaque) callconv(.c) c_int {
    const app: *App = @ptrCast(@alignCast(user.?));
    app.closing = true;
    if (app.term) |term| {
        term.close(app.gpa);
        app.term = null;
    }
    return 0;
}

fn onOutput(user: ?*anyopaque) callconv(.c) void {
    const app: *App = @ptrCast(@alignCast(user.?));
    scheduleRedraw(app);
}

fn onTitle(user: ?*anyopaque) callconv(.c) void {
    const app: *App = @ptrCast(@alignCast(user.?));
    c.cadex_idle(titleIdle, app);
}

fn titleIdle(user: ?*anyopaque) callconv(.c) void {
    const app: *App = @ptrCast(@alignCast(user.?));
    const term = app.term orelse return;
    const title = term.copyTitle(app.gpa) orelse return;
    defer app.gpa.free(title);
    const z = app.gpa.dupeZ(u8, title) catch return;
    defer app.gpa.free(z);
    c.cadex_window_title(app.window, z.ptr);
}

fn onBell(user: ?*anyopaque) callconv(.c) void {
    const app: *App = @ptrCast(@alignCast(user.?));
    c.cadex_idle(bellIdle, app);
}

fn bellIdle(user: ?*anyopaque) callconv(.c) void {
    const app: *App = @ptrCast(@alignCast(user.?));
    c.cadex_beep(app.area);
}

fn onExit(user: ?*anyopaque, code: i32) callconv(.c) void {
    _ = code;
    const app: *App = @ptrCast(@alignCast(user.?));
    c.cadex_idle(exitIdle, app);
}

fn exitIdle(user: ?*anyopaque) callconv(.c) void {
    const app: *App = @ptrCast(@alignCast(user.?));
    c.cadex_window_close(app.window);
}

fn draw(ctx: ?*anyopaque, width: c_int, height: c_int, user: ?*anyopaque) callconv(.c) void {
    const app: *App = @ptrCast(@alignCast(user.?));
    const term = app.term orelse {
        c.cadex_draw_rect(ctx, 0, 0, @floatFromInt(width), @floatFromInt(height), 0x1e1e1e);
        return;
    };
    if (width < 2 * PAD or height < 2 * PAD) return;
    app.width = width;
    app.height = height;

    const cw = app.cell_w;
    const ch = app.cell_h;
    const cols: u16 = @intCast(@max(1, @min(1000, @divTrunc(width - 2 * PAD, cw))));
    const rows: u16 = @intCast(@max(1, @min(1000, @divTrunc(height - 2 * PAD, ch))));
    if (cols != app.cols or rows != app.rows) {
        term.resize(cols, rows, @intCast(cw), @intCast(ch));
        app.cols = cols;
        app.rows = rows;
    }

    const frame = term.updateFrame() orelse return;
    app.frame = frame;
    c.cadex_draw_rect(ctx, 0, 0, @floatFromInt(width), @floatFromInt(height), frame.background);

    const cursor_is_block = frame.cursor_visible and frame.cursor_style == CURSOR_BLOCK;
    const pad_f: f64 = @floatFromInt(PAD);
    const cw_f: f64 = @floatFromInt(cw);
    const ch_f: f64 = @floatFromInt(ch);
    var row: usize = 0;
    while (row < frame.rows) : (row += 1) {
        var col: usize = 0;
        while (col < frame.cols) : (col += 1) {
            const cell = frame.cells[row * @as(usize, frame.cols) + col];
            const x = pad_f + @as(f64, @floatFromInt(col)) * cw_f;
            const y = pad_f + @as(f64, @floatFromInt(row)) * ch_f;

            var bg = frame.background;
            if (cell.flags & F_HAS_BACKGROUND != 0) bg = cell.bg;
            if (cell.flags & F_SELECTED != 0) bg = 0x264f78;
            if (cell.flags & F_MATCH != 0) bg = 0x5f4b00;
            if (cell.flags & F_MATCH_CURRENT != 0) bg = 0xffa500;

            const is_cursor = frame.cursor_visible and row == @as(usize, frame.cursor_y) and col == @as(usize, frame.cursor_x);
            const block_cursor = is_cursor and frame.cursor_style == CURSOR_BLOCK;
            if (block_cursor) bg = if (frame.has_cursor_color) frame.cursor_color else 0xffffff;
            if (bg != frame.background or block_cursor) {
                c.cadex_draw_rect(ctx, x, y, cw_f, ch_f, bg);
            }

            if (cell.text_len > 0 and cell.flags & F_SPACER == 0) {
                var fg = cell.fg;
                if (block_cursor) fg = frame.background;
                const bold = cell.flags & F_BOLD != 0;
                const italic = cell.flags & F_ITALIC != 0;
                const text = frame.text + @as(usize, cell.text_offset);
                c.cadex_draw_text(ctx, text, @intCast(cell.text_len), x, y, fg, @intFromBool(bold), @intFromBool(italic));
            }

            const underline = (cell.flags >> 8) & 7;
            if (underline != 0) {
                c.cadex_draw_line(ctx, x, y + ch_f - 1, x + cw_f, y + ch_f - 1, cell.fg);
            }
        }
    }

    if (frame.cursor_visible and !cursor_is_block) {
        const cx = pad_f + @as(f64, @floatFromInt(frame.cursor_x)) * cw_f;
        const cy = pad_f + @as(f64, @floatFromInt(frame.cursor_y)) * ch_f;
        const color = if (frame.has_cursor_color) frame.cursor_color else 0xffffff;
        switch (frame.cursor_style) {
            CURSOR_BAR => c.cadex_draw_rect(ctx, cx, cy, 2, ch_f, color),
            CURSOR_UNDERLINE => c.cadex_draw_rect(ctx, cx, cy + ch_f - 2, cw_f, 2, color),
            CURSOR_BLOCK_HOLLOW => {
                c.cadex_draw_line(ctx, cx, cy, cx + cw_f, cy, color);
                c.cadex_draw_line(ctx, cx, cy + ch_f - 1, cx + cw_f, cy + ch_f - 1, color);
                c.cadex_draw_line(ctx, cx, cy, cx, cy + ch_f, color);
                c.cadex_draw_line(ctx, cx + cw_f - 1, cy, cx + cw_f - 1, cy + ch_f, color);
            },
            else => {},
        }
    }

    const im_x = PAD + @as(i32, frame.cursor_x) * cw;
    const im_y = PAD + @as(i32, frame.cursor_y) * ch;
    c.cadex_im_cursor(app.area, im_x, im_y, cw, ch);
}

fn key(keyval: c_uint, keycode: c_uint, state: c_uint, user: ?*anyopaque) callconv(.c) c_int {
    _ = keycode;
    const app: *App = @ptrCast(@alignCast(user.?));
    const term = app.term orelse return 0;
    const shift = state & SHIFT != 0;
    const ctrl = state & CONTROL != 0;
    const alt = state & ALT != 0;
    const super = state & SUPER != 0;

    if (ctrl and shift) {
        switch (keyval) {
            'q', 'Q', 'w', 'W' => {
                c.cadex_window_close(app.window);
                return 1;
            },
            'c', 'C' => {
                copySelection(app, term);
                return 1;
            },
            'v', 'V' => {
                paste(app, term);
                return 1;
            },
            'f', 'F' => {
                toggleSearch(app);
                return 1;
            },
            'a', 'A' => {
                term.selectAll();
                scheduleRedraw(app);
                return 1;
            },
            else => {},
        }
    }

    // The C API's CADEX_KEY_* values (include/cadex.h).
    const special: u16 = switch (keyval) {
        0xff0d, 0xff8d => 1, // Enter
        0xff09 => 2, // Tab
        0xff08 => 3, // Backspace
        0xff1b => 4, // Escape
        0xffff => 5, // Delete
        0xff63 => 6, // Insert
        0xff50 => 7, // Home
        0xff57 => 8, // End
        0xff55 => 9, // Page Up
        0xff56 => 10, // Page Down
        0xff52 => 11, // Up
        0xff54 => 12, // Down
        0xff51 => 13, // Left
        0xff53 => 14, // Right
        0xffbe...0xffc9 => 15 + @as(u16, @intCast(keyval - 0xffbe)), // F1..F12
        else => 0,
    };
    if (special != 0) {
        term.key(special, modsFrom(shift, ctrl, alt, super), "", 0);
        return 1;
    }

    if (super) return 0;
    const cp = c.cadex_keyval_unicode(keyval);
    if (cp == 0) return 0;
    var buf: [4]u8 = undefined;
    const n = c.cadex_utf8_encode(cp, &buf);
    if (n <= 0) return 1;
    const text = buf[0..@intCast(n)];

    if (ctrl or alt) {
        const text_for_key: []const u8 = if (shift) text else "";
        const unshifted = c.cadex_keyval_lower(keyval);
        term.key(0, modsFrom(shift, ctrl, alt, super), text_for_key, unshifted);
        return 1;
    }

    term.write(text);
    return 1;
}

fn modsFrom(shift: bool, ctrl: bool, alt: bool, super: bool) u8 {
    var mods: u8 = 0;
    if (shift) mods |= 1;
    if (ctrl) mods |= 2;
    if (alt) mods |= 4;
    if (super) mods |= 8;
    return mods;
}

fn commit(text: ?[*:0]const u8, user: ?*anyopaque) callconv(.c) void {
    const raw = text orelse return;
    const app: *App = @ptrCast(@alignCast(user.?));
    if (app.term) |term| term.write(std.mem.span(raw));
}

fn pointer(x: c_int, y: c_int, button: c_int, state: c_uint, phase: c_int, clicks: c_int, user: ?*anyopaque) callconv(.c) void {
    if (button != 1) return;
    const app: *App = @ptrCast(@alignCast(user.?));
    const term = app.term orelse return;
    const cw = app.cell_w;
    const ch = app.cell_h;
    const col_i = @divTrunc(x - PAD, cw);
    const row_i = @divTrunc(y - PAD, ch);
    const col: u16 = @intCast(std.math.clamp(col_i, 0, @as(i32, app.cols) - 1));
    const row: u16 = @intCast(std.math.clamp(row_i, 0, @as(i32, app.rows) - 1));

    if (state & CONTROL != 0 and phase == 0 and clicks == 1) {
        const link = term.linkAt(app.gpa, col, row) orelse return;
        defer app.gpa.free(link.target);
        const z = app.gpa.dupeZ(u8, link.target) catch return;
        defer app.gpa.free(z);
        if (link.kind == 1) {
            _ = c.cadex_open_uri(z.ptr);
        } else {
            _ = c.cadex_open_path(z.ptr);
        }
        return;
    }

    if (term.mouseTracking() != 0) {
        var event = std.mem.zeroes(core.cadex_terminal_mouse_event);
        event.x = @floatFromInt(x);
        event.y = @floatFromInt(y);
        event.view_width = @intCast(@max(app.width, 0));
        event.view_height = @intCast(@max(app.height, 0));
        event.cell_width = @intCast(cw);
        event.cell_height = @intCast(ch);
        event.padding = @intCast(PAD);
        event.action = if (phase == 0) 0 else if (phase == 1) 2 else 1;
        event.button = 1;
        event.mods = modsFrom(state & SHIFT != 0, state & CONTROL != 0, state & ALT != 0, state & SUPER != 0);
        term.mouse(&event);
        return;
    }

    var p = core.cadex_terminal_pointer{
        .x = @floatFromInt(x),
        .y = @floatFromInt(y),
        .col = col,
        .row = row,
        .cell_width = @intCast(cw),
        .padding_left = PAD,
        .view_height = @intCast(@max(app.height, 0)),
    };
    const extend = state & SHIFT != 0;
    if (phase == 0) {
        term.selectPress(&p, @intCast(std.math.clamp(clicks, 1, 3)), extend);
    } else if (phase == 1) {
        term.selectDrag(&p);
    } else if (phase == 2) {
        term.selectRelease(&p);
    }
    scheduleRedraw(app);
}

fn scroll(dx: f64, dy: f64, user: ?*anyopaque) callconv(.c) void {
    _ = dx;
    const app: *App = @ptrCast(@alignCast(user.?));
    const term = app.term orelse return;
    var event = std.mem.zeroes(core.cadex_terminal_mouse_event);
    event.view_width = @intCast(@max(app.width, 0));
    event.view_height = @intCast(@max(app.height, 0));
    event.cell_width = @intCast(app.cell_w);
    event.cell_height = @intCast(app.cell_h);
    event.padding = @intCast(PAD);
    event.action = 0;
    event.button = 0;
    const rows: i32 = if (dy > 0) -3 else 3;
    term.wheel(&event, rows);
    scheduleRedraw(app);
}

fn entryChanged(user: ?*anyopaque) callconv(.c) void {
    const app: *App = @ptrCast(@alignCast(user.?));
    const raw = c.cadex_entry_text(app.entry);
    if (raw == null) return;
    const text = std.mem.span(@as([*:0]const u8, @ptrCast(raw)));
    const term = app.term orelse return;
    if (text.len == 0) {
        term.searchStop();
    } else {
        term.searchStart(text);
        _ = term.searchSelect(0);
    }
    scheduleRedraw(app);
}

fn entryActivate(user: ?*anyopaque) callconv(.c) void {
    const app: *App = @ptrCast(@alignCast(user.?));
    const term = app.term orelse return;
    _ = term.searchSelect(0);
    scheduleRedraw(app);
}

fn entryEscape(user: ?*anyopaque) callconv(.c) void {
    const app: *App = @ptrCast(@alignCast(user.?));
    app.search_open = false;
    c.cadex_widget_visible(app.entry, 0);
    if (app.term) |term| term.searchStop();
    c.cadex_widget_focus(app.area);
    scheduleRedraw(app);
}

fn toggleSearch(app: *App) void {
    if (app.search_open) {
        entryEscape(app);
        return;
    }
    app.search_open = true;
    c.cadex_widget_visible(app.entry, 1);
    c.cadex_entry_select_all(app.entry);
    c.cadex_widget_focus(app.entry);
}

fn copySelection(app: *App, term: *terminal.Terminal) void {
    const text = term.copySelection(app.gpa) orelse return;
    defer app.gpa.free(text);
    const z = app.gpa.dupeZ(u8, text) catch return;
    defer app.gpa.free(z);
    c.cadex_clipboard_set(app.area, z.ptr);
}

fn paste(app: *App, term: *terminal.Terminal) void {
    _ = term;
    c.cadex_clipboard_get(app.area, clipboardText, app);
}

fn clipboardText(text: [*c]const u8, user: ?*anyopaque) callconv(.c) void {
    if (text == null) return;
    const app: *App = @ptrCast(@alignCast(user.?));
    const s = std.mem.span(@as([*:0]const u8, @ptrCast(text)));
    if (app.term) |term| term.paste(s);
}
