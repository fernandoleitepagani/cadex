//! Cadex on Linux: a GTK4/Wayland shell over the core terminal.

const std = @import("std");
const core = @import("cadex");
const system = @import("system");
const terminal = @import("terminal");

const c = system.c;

const PAD: i32 = 8;

const SHIFT: c_uint = 1 << 0;
const CONTROL: c_uint = 1 << 2;
const ALT: c_uint = 1 << 3;
const SUPER: c_uint = 1 << 26;

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

const HORIZONTAL: c_int = 0;
const VERTICAL: c_int = 1;

const Theme = struct {
    name: []const u8,
    dark: bool,
    background: u32,
    foreground: u32,
    cursor: u32,
    panel: u32,
    ansi: [16]u32,
};

const themes = [_]Theme{
    .{
        .name = "Cadex Dark",
        .dark = true,
        .background = 0x1e1e1e,
        .foreground = 0xd4d4d4,
        .cursor = 0xffffff,
        .panel = 0x252526,
        .ansi = .{ 0x1e1e1e, 0xcd3131, 0x0dbc79, 0xe5e510, 0x2472c8, 0xbc3fbc, 0x11a8cd, 0xe5e5e5, 0x666666, 0xf14c4c, 0x23d18b, 0xf5f543, 0x3b8eea, 0xd670d6, 0x29b8db, 0xffffff },
    },
    .{
        .name = "Cadex Light",
        .dark = false,
        .background = 0xfafafa,
        .foreground = 0x383a42,
        .cursor = 0x000000,
        .panel = 0xeeeeee,
        .ansi = .{ 0x383a42, 0xe45649, 0x50a14f, 0xc18401, 0x4078f2, 0xa626a4, 0x0184bc, 0xa0a1a7, 0x696c77, 0xe45649, 0x50a14f, 0xc18401, 0x4078f2, 0xa626a4, 0x0184bc, 0xffffff },
    },
    .{
        .name = "Solarized Dark",
        .dark = true,
        .background = 0x002b36,
        .foreground = 0x839496,
        .cursor = 0x93a1a1,
        .panel = 0x073642,
        .ansi = .{ 0x073642, 0xdc322f, 0x859900, 0xb58900, 0x268bd2, 0xd33682, 0x2aa198, 0xeee8d5, 0x002b36, 0xcb4b16, 0x586e75, 0x657b83, 0x839496, 0x6c71c4, 0x93a1a1, 0xfdf6e3 },
    },
    .{
        .name = "Solarized Light",
        .dark = false,
        .background = 0xfdf6e3,
        .foreground = 0x657b83,
        .cursor = 0x586e75,
        .panel = 0xeee8d5,
        .ansi = .{ 0x073642, 0xdc322f, 0x859900, 0xb58900, 0x268bd2, 0xd33682, 0x2aa198, 0xeee8d5, 0x002b36, 0xcb4b16, 0x586e75, 0x657b83, 0x839496, 0x6c71c4, 0x93a1a1, 0xfdf6e3 },
    },
};

const theme_names = [_][*:0]const u8{
    "Cadex Dark",
    "Cadex Light",
    "Solarized Dark",
    "Solarized Light",
};

const Settings = struct {
    font_size: i32 = 12,
    cursor_blink: bool = true,
    sidebar: bool = true,
};

const Space = struct {
    app: *App,
    notebook: *anyopaque,
    name: [:0]u8,
    tabs: std.ArrayList(*Tab) = .empty,
};

const Tab = struct {
    app: *App,
    space: *Space,
    container: *anyopaque,
    content: *anyopaque,
    label_box: *anyopaque,
    title_label: *anyopaque,
    panes: [2]?*Pane = .{ null, null },
    orientation: c_int = HORIZONTAL,
    closed: bool = false,
};

const Pane = struct {
    app: *App,
    tab: *Tab,
    term: ?*terminal.Terminal = null,
    container: *anyopaque,
    area: *anyopaque,
    header_label: *anyopaque,
    title: [:0]u8,
    closed: bool = false,
    redraw_pending: std.atomic.Value(bool) = .init(false),
};

const App = struct {
    gpa: std.mem.Allocator,
    window: *anyopaque,
    header_title: *anyopaque,
    space_label: *anyopaque,
    sidebar: *anyopaque,
    sidebar_stack: *anyopaque,
    content: *anyopaque,
    spaces_stack: *anyopaque,
    find_entry: *anyopaque,
    find_open: bool = false,
    cwd_label: *anyopaque,
    tabs_label: *anyopaque,
    spaces: std.ArrayList(*Space) = .empty,
    space_index: usize = 0,
    focused: ?*Pane = null,
    theme_index: usize = 0,
    settings: Settings = .{},
    font: [32]u8 = undefined,
    cell_w: i32 = 8,
    cell_h: i32 = 16,
    ascent: i32 = 12,
    width: i32 = 800,
    height: i32 = 600,
    palette_window: ?*anyopaque = null,
    palette_entry: ?*anyopaque = null,
    palette_list: ?*anyopaque = null,
    palette_filtered: std.ArrayList(*const Command) = .empty,
    settings_window: ?*anyopaque = null,
    settings_theme: ?*anyopaque = null,
    settings_font: ?*anyopaque = null,
    settings_blink: ?*anyopaque = null,
    settings_sidebar: ?*anyopaque = null,
    closing: bool = false,
};

const Command = struct {
    id: []const u8,
    title: []const u8,
    keywords: []const u8,
    shortcut: []const u8,
    run: *const fn (*App) void,
};

const commands = [_]Command{
    .{ .id = "palette.open", .title = "Command Palette", .keywords = "palette commands k", .shortcut = "Ctrl+Shift+K", .run = cmdPalette },
    .{ .id = "tab.new", .title = "New Tab", .keywords = "tab new terminal", .shortcut = "Ctrl+Shift+T", .run = cmdNewTab },
    .{ .id = "tab.close", .title = "Close Tab", .keywords = "tab close", .shortcut = "Ctrl+Shift+W", .run = cmdCloseTab },
    .{ .id = "tab.next", .title = "Next Tab", .keywords = "tab next", .shortcut = "Ctrl+Shift+PgDn", .run = cmdNextTab },
    .{ .id = "tab.previous", .title = "Previous Tab", .keywords = "tab previous", .shortcut = "Ctrl+Shift+PgUp", .run = cmdPrevTab },
    .{ .id = "pane.split-right", .title = "Split Right", .keywords = "pane split right", .shortcut = "Ctrl+Shift+D", .run = cmdSplitRight },
    .{ .id = "pane.split-down", .title = "Split Down", .keywords = "pane split down", .shortcut = "Ctrl+Shift+Alt+D", .run = cmdSplitDown },
    .{ .id = "pane.close", .title = "Close Pane", .keywords = "pane close", .shortcut = "", .run = cmdClosePane },
    .{ .id = "terminal.find", .title = "Find in Terminal", .keywords = "find search terminal", .shortcut = "Ctrl+Shift+F", .run = cmdFind },
    .{ .id = "terminal.copy", .title = "Copy Selection", .keywords = "copy clipboard", .shortcut = "Ctrl+Shift+C", .run = cmdCopy },
    .{ .id = "terminal.paste", .title = "Paste", .keywords = "paste clipboard", .shortcut = "Ctrl+Shift+V", .run = cmdPaste },
    .{ .id = "terminal.select-all", .title = "Select All", .keywords = "select all", .shortcut = "Ctrl+Shift+A", .run = cmdSelectAll },
    .{ .id = "space.new", .title = "New Space", .keywords = "space new", .shortcut = "Ctrl+Shift+N", .run = cmdSpaceNew },
    .{ .id = "space.next", .title = "Next Space", .keywords = "space next", .shortcut = "Ctrl+Shift+Alt+PgDn", .run = cmdSpaceNext },
    .{ .id = "space.previous", .title = "Previous Space", .keywords = "space previous", .shortcut = "Ctrl+Shift+Alt+PgUp", .run = cmdSpacePrev },
    .{ .id = "view.toggle-sidebar", .title = "Toggle Sidebar", .keywords = "sidebar toggle", .shortcut = "Ctrl+Shift+B", .run = cmdToggleSidebar },
    .{ .id = "sidebar.files", .title = "Sidebar: Files", .keywords = "sidebar files explorer", .shortcut = "", .run = cmdSidebarFiles },
    .{ .id = "sidebar.git", .title = "Sidebar: Git", .keywords = "sidebar git source control", .shortcut = "", .run = cmdSidebarGit },
    .{ .id = "sidebar.history", .title = "Sidebar: History", .keywords = "sidebar history git", .shortcut = "", .run = cmdSidebarHistory },
    .{ .id = "settings.open", .title = "Settings", .keywords = "settings preferences theme font", .shortcut = "Ctrl+Shift+,", .run = cmdSettings },
    .{ .id = "app.quit", .title = "Quit Cadex", .keywords = "quit exit", .shortcut = "Ctrl+Shift+Q", .run = cmdQuit },
};

pub fn main() !void {
    if (std.c.getenv("WAYLAND_DISPLAY") == null) {
        std.debug.print("Cadex requires Wayland; WAYLAND_DISPLAY is not set.\n", .{});
        std.process.exit(1);
    }
    _ = c.cadex_set_wayland();

    const gpa = std.heap.c_allocator;
    const launch = try gpa.create(Launch);
    launch.* = .{ .background = std.c.getenv("CADEX_BACKGROUND") != null };
    const gtk_app = c.cadex_app_new() orelse {
        std.debug.print("cadex: cannot create the GTK application\n", .{});
        std.process.exit(1);
    };
    c.cadex_app_activate(gtk_app, onActivate, launch);
    const status = c.cadex_app_run(gtk_app);
    std.process.exit(@intCast(status));
}

const Launch = struct {
    background: bool,
};

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
        .header_title = undefined,
        .space_label = undefined,
        .sidebar = undefined,
        .sidebar_stack = undefined,
        .content = undefined,
        .spaces_stack = undefined,
        .find_entry = undefined,
        .cwd_label = undefined,
        .tabs_label = undefined,
    };
    loadSettings(app);

    app.window = c.cadex_window_new(gtk_app, "Cadex", 1100, 750) orelse return error.GtkFailed;
    const header = c.cadex_header_new(app.window) orelse return error.GtkFailed;
    const header_start = c.cadex_box_new_h(8) orelse return error.GtkFailed;
    app.space_label = c.cadex_label_new("Space 1") orelse return error.GtkFailed;
    c.cadex_box_append(header_start, app.space_label);
    c.cadex_box_append(header_start, c.cadex_button_new("Sidebar", sidebarClicked, app) orelse return error.GtkFailed);
    c.cadex_header_widget_start(header, header_start);
    app.header_title = c.cadex_header_title(header, "Cadex") orelse return error.GtkFailed;
    const header_end = c.cadex_box_new_h(8) orelse return error.GtkFailed;
    c.cadex_box_append(header_end, c.cadex_button_new("Palette", paletteClicked, app) orelse return error.GtkFailed);
    c.cadex_box_append(header_end, c.cadex_button_new("Settings", settingsClicked, app) orelse return error.GtkFailed);
    c.cadex_header_widget_end(header, header_end);

    const main_box = c.cadex_paned_new(HORIZONTAL) orelse return error.GtkFailed;
    app.sidebar = c.cadex_box_new() orelse return error.GtkFailed;
    c.cadex_widget_set_size(app.sidebar, 220, -1);
    c.cadex_widget_add_class(app.sidebar, "cadex-sidebar");
    const sidebar_title = c.cadex_label_new("Cadex") orelse return error.GtkFailed;
    c.cadex_widget_add_class(sidebar_title, "cadex-sidebar-title");
    c.cadex_box_append(app.sidebar, sidebar_title);
    const icons = c.cadex_box_new_h(4) orelse return error.GtkFailed;
    c.cadex_box_append(icons, c.cadex_button_new("Files", sidebarFilesClicked, app) orelse return error.GtkFailed);
    c.cadex_box_append(icons, c.cadex_button_new("Git", sidebarGitClicked, app) orelse return error.GtkFailed);
    c.cadex_box_append(icons, c.cadex_button_new("History", sidebarHistoryClicked, app) orelse return error.GtkFailed);
    c.cadex_box_append(app.sidebar, icons);
    app.sidebar_stack = c.cadex_stack_new() orelse return error.GtkFailed;
    c.cadex_stack_add(app.sidebar_stack, c.cadex_label_new("Files — Run 4") orelse return error.GtkFailed, "files");
    c.cadex_stack_add(app.sidebar_stack, c.cadex_label_new("Git — Run 4") orelse return error.GtkFailed, "git");
    c.cadex_stack_add(app.sidebar_stack, c.cadex_label_new("History — Run 4") orelse return error.GtkFailed, "history");
    c.cadex_widget_expand(app.sidebar_stack);
    c.cadex_box_append(app.sidebar, app.sidebar_stack);

    app.content = c.cadex_box_new() orelse return error.GtkFailed;
    c.cadex_widget_expand(app.content);
    app.find_entry = c.cadex_entry_new() orelse return error.GtkFailed;
    c.cadex_widget_visible(app.find_entry, 0);
    c.cadex_entry_changed(app.find_entry, findChanged, app);
    c.cadex_entry_activate(app.find_entry, findActivate, app);
    c.cadex_entry_escape(app.find_entry, findEscape, app);
    c.cadex_box_append(app.content, app.find_entry);
    app.spaces_stack = c.cadex_stack_new() orelse return error.GtkFailed;
    c.cadex_widget_expand(app.spaces_stack);
    c.cadex_box_append(app.content, app.spaces_stack);
    const status = c.cadex_box_new_h(12) orelse return error.GtkFailed;
    c.cadex_widget_add_class(status, "cadex-status");
    app.cwd_label = c.cadex_label_new("~") orelse return error.GtkFailed;
    app.tabs_label = c.cadex_label_new("1 tab") orelse return error.GtkFailed;
    c.cadex_box_append(status, app.cwd_label);
    c.cadex_box_append(status, app.tabs_label);
    c.cadex_box_append(app.content, status);

    c.cadex_paned_set_start(main_box, app.sidebar);
    c.cadex_paned_set_end(main_box, app.content);
    c.cadex_paned_set_position(main_box, 230);
    c.cadex_window_child(app.window, main_box);
    c.cadex_window_on_close(app.window, closeCb, app);

    try newSpace(app);
    applyFont(app);
    applyTheme(app);
    applySidebar(app);
    c.cadex_window_present(app.window, @intFromBool(launch.background));
    if (app.focused) |pane| c.cadex_widget_focus(pane.area);
    _ = c.cadex_timeout(1000, statusTimer, app);
}

fn closeCb(user: ?*anyopaque) callconv(.c) c_int {
    const app: *App = @ptrCast(@alignCast(user.?));
    app.closing = true;
    for (app.spaces.items) |space| {
        for (space.tabs.items) |tab| {
            for (tab.panes) |maybe| {
                if (maybe) |pane| {
                    pane.closed = true;
                    if (pane.term) |term| {
                        term.close(app.gpa);
                        pane.term = null;
                    }
                }
            }
        }
    }
    return 0;
}

fn currentSpace(app: *App) *Space {
    return app.spaces.items[app.space_index];
}

fn newSpace(app: *App) !void {
    const gpa = app.gpa;
    const space = try gpa.create(Space);
    const name = try std.fmt.allocPrintSentinel(gpa, "Space {d}", .{app.spaces.items.len + 1}, 0);
    space.* = .{
        .app = app,
        .notebook = c.cadex_notebook_new() orelse return error.GtkFailed,
        .name = name,
    };
    c.cadex_notebook_on_switch(space.notebook, onNotebookSwitch, space);
    c.cadex_stack_add(app.spaces_stack, space.notebook, space.name.ptr);
    try app.spaces.append(gpa, space);
    switchSpace(app, app.spaces.items.len - 1);
    try newTab(app, space);
}

fn switchSpace(app: *App, index: usize) void {
    if (index >= app.spaces.items.len) return;
    app.space_index = index;
    const space = app.spaces.items[index];
    c.cadex_stack_set(app.spaces_stack, space.name.ptr);
    c.cadex_label_set(app.space_label, space.name.ptr);
    if (space.tabs.items.len > 0) {
        const page: usize = @intCast(@max(0, c.cadex_notebook_current(space.notebook)));
        const tab = space.tabs.items[@min(page, space.tabs.items.len - 1)];
        app.focused = tab.panes[0];
        if (tab.panes[0]) |pane| c.cadex_widget_focus(pane.area);
    } else {
        app.focused = null;
    }
    updateTitle(app);
    updateStatus(app);
}

fn onNotebookSwitch(notebook: ?*anyopaque, index: c_int, user: ?*anyopaque) callconv(.c) void {
    _ = notebook;
    const space: *Space = @ptrCast(@alignCast(user.?));
    const app = space.app;
    if (index < 0) return;
    const at: usize = @intCast(index);
    if (at >= space.tabs.items.len) return;
    const tab = space.tabs.items[at];
    app.focused = tab.panes[0];
    if (tab.panes[0]) |pane| c.cadex_widget_focus(pane.area);
    updateTitle(app);
    updateStatus(app);
}

fn newTab(app: *App, space: *Space) !void {
    const gpa = app.gpa;
    const tab = try gpa.create(Tab);
    tab.* = .{
        .app = app,
        .space = space,
        .container = c.cadex_box_new() orelse return error.GtkFailed,
        .content = undefined,
        .label_box = c.cadex_box_new_h(4) orelse return error.GtkFailed,
        .title_label = c.cadex_label_new("Terminal") orelse return error.GtkFailed,
    };
    c.cadex_label_ellipsize(tab.title_label);
    c.cadex_widget_set_size(tab.title_label, 160, -1);
    c.cadex_widget_add_class(tab.label_box, "cadex-tab-label");
    c.cadex_box_append(tab.label_box, tab.title_label);
    c.cadex_box_append(tab.label_box, c.cadex_button_new("×", tabCloseClicked, tab) orelse return error.GtkFailed);

    const pane = try createPane(app, tab);
    tab.panes = .{ pane, null };
    tab.content = pane.container;
    c.cadex_box_append(tab.container, pane.container);
    c.cadex_notebook_append(space.notebook, tab.container, tab.label_box);
    try space.tabs.append(gpa, tab);
    const index = space.tabs.items.len - 1;
    c.cadex_notebook_set_current(space.notebook, @intCast(index));
    app.focused = pane;
    c.cadex_widget_focus(pane.area);
    updateTitle(app);
    updateStatus(app);
}

fn createPane(app: *App, tab: *Tab) !*Pane {
    const gpa = app.gpa;
    const pane = try gpa.create(Pane);
    pane.* = .{
        .app = app,
        .tab = tab,
        .container = undefined,
        .area = undefined,
        .header_label = undefined,
        .title = try gpa.dupeZ(u8, "Terminal"),
    };
    pane.term = try terminal.Terminal.open(gpa, 80, 24, null, .{
        .user = pane,
        .output = onOutput,
        .exit = onExit,
        .title = onTitle,
        .bell = onBell,
    });
    pane.container = c.cadex_box_new() orelse return error.GtkFailed;
    const header = c.cadex_box_new_h(4) orelse return error.GtkFailed;
    c.cadex_widget_add_class(header, "cadex-pane-header");
    pane.header_label = c.cadex_label_new("Terminal") orelse return error.GtkFailed;
    c.cadex_label_ellipsize(pane.header_label);
    c.cadex_box_append(header, pane.header_label);
    c.cadex_box_append(header, c.cadex_button_new("×", paneCloseClicked, pane) orelse return error.GtkFailed);
    c.cadex_box_append(pane.container, header);
    pane.area = c.cadex_drawing_new() orelse return error.GtkFailed;
    c.cadex_widget_expand(pane.area);
    c.cadex_widget_add_class(pane.area, "cadex-term");
    c.cadex_box_append(pane.container, pane.area);
    c.cadex_drawing_draw(pane.area, draw, pane);
    c.cadex_drawing_input(pane.area, key, commit, pane);
    c.cadex_drawing_mouse(pane.area, pointer, scroll, pane);
    if (pane.term) |term| {
        var colors = themeColors(themes[app.theme_index]);
        term.setColors(&colors);
        term.setCursor(CURSOR_BLOCK, app.settings.cursor_blink);
    }
    return pane;
}

fn themeColors(theme: Theme) core.cadex_terminal_colors {
    var colors = std.mem.zeroes(core.cadex_terminal_colors);
    colors.background = theme.background;
    colors.foreground = theme.foreground;
    colors.cursor = theme.cursor;
    colors.ansi = theme.ansi;
    return colors;
}

fn schedulePaneRedraw(pane: *Pane) void {
    if (pane.closed) return;
    if (!pane.redraw_pending.swap(true, .acq_rel)) c.cadex_idle(paneRedrawIdle, pane);
}

fn paneRedrawIdle(user: ?*anyopaque) callconv(.c) void {
    const pane: *Pane = @ptrCast(@alignCast(user.?));
    pane.redraw_pending.store(false, .release);
    if (!pane.closed) c.cadex_queue_draw(pane.area);
}

fn onOutput(user: ?*anyopaque) callconv(.c) void {
    const pane: *Pane = @ptrCast(@alignCast(user.?));
    schedulePaneRedraw(pane);
}

fn onTitle(user: ?*anyopaque) callconv(.c) void {
    const pane: *Pane = @ptrCast(@alignCast(user.?));
    c.cadex_idle(paneTitleIdle, pane);
}

fn paneTitleIdle(user: ?*anyopaque) callconv(.c) void {
    const pane: *Pane = @ptrCast(@alignCast(user.?));
    const app = pane.app;
    if (pane.closed) return;
    const term = pane.term orelse return;
    const title = term.copyTitle(app.gpa) orelse return;
    defer app.gpa.free(title);
    const z = app.gpa.dupeZ(u8, title) catch return;
    if (pane.title.len > 0) app.gpa.free(pane.title);
    pane.title = z;
    c.cadex_label_set(pane.header_label, z.ptr);
    c.cadex_label_set(pane.tab.title_label, z.ptr);
    if (app.focused == pane) updateTitle(app);
    updateStatus(app);
}

fn onBell(user: ?*anyopaque) callconv(.c) void {
    const pane: *Pane = @ptrCast(@alignCast(user.?));
    c.cadex_idle(paneBellIdle, pane);
}

fn paneBellIdle(user: ?*anyopaque) callconv(.c) void {
    const pane: *Pane = @ptrCast(@alignCast(user.?));
    if (!pane.closed) c.cadex_beep(pane.area);
}

fn onExit(user: ?*anyopaque, code: i32) callconv(.c) void {
    _ = code;
    const pane: *Pane = @ptrCast(@alignCast(user.?));
    c.cadex_idle(paneExitIdle, pane);
}

fn paneExitIdle(user: ?*anyopaque) callconv(.c) void {
    const pane: *Pane = @ptrCast(@alignCast(user.?));
    closePane(pane);
}

fn updateTitle(app: *App) void {
    const pane = app.focused orelse return;
    if (pane.closed) return;
    c.cadex_window_title(app.window, pane.title.ptr);
    c.cadex_label_set(app.header_title, pane.title.ptr);
}

fn updateStatus(app: *App) void {
    if (app.closing) return;
    var cwd_text: ?[]u8 = null;
    if (app.focused) |pane| {
        if (pane.term) |term| cwd_text = term.copyWorkingDirectory(app.gpa);
    }
    if (cwd_text) |text| {
        defer app.gpa.free(text);
        const z = app.gpa.dupeZ(u8, text) catch return;
        defer app.gpa.free(z);
        c.cadex_label_set(app.cwd_label, z.ptr);
    }
    const count = c.cadex_notebook_count(currentSpace(app).notebook);
    var buf: [64]u8 = undefined;
    const text = std.fmt.bufPrintZ(&buf, "{d} tab(s)", .{count}) catch return;
    c.cadex_label_set(app.tabs_label, @ptrCast(text.ptr));
}

fn statusTimer(user: ?*anyopaque) callconv(.c) void {
    const app: *App = @ptrCast(@alignCast(user.?));
    updateTitle(app);
    updateStatus(app);
    if (!app.closing) _ = c.cadex_timeout(1000, statusTimer, app);
}

fn applyFont(app: *App) void {
    const z = std.fmt.bufPrintZ(&app.font, "Monospace {d}", .{app.settings.font_size}) catch return;
    c.cadex_text_set_font(z.ptr);
    updateMetrics(app);
    for (app.spaces.items) |space| {
        for (space.tabs.items) |tab| {
            for (tab.panes) |maybe| {
                if (maybe) |pane| schedulePaneRedraw(pane);
            }
        }
    }
}

fn updateMetrics(app: *App) void {
    for (app.spaces.items) |space| {
        for (space.tabs.items) |tab| {
            for (tab.panes) |maybe| {
                if (maybe) |pane| {
                    var cw: c_int = 8;
                    var ch: c_int = 16;
                    var asc: c_int = 12;
                    _ = c.cadex_text_metrics(pane.area, @ptrCast(&app.font), &cw, &ch, &asc);
                    app.cell_w = if (cw > 0) cw else 8;
                    app.cell_h = if (ch > 0) ch else 16;
                    app.ascent = if (asc > 0) asc else 12;
                    return;
                }
            }
        }
    }
}

fn applyTheme(app: *App) void {
    const theme = themes[app.theme_index];
    c.cadex_set_dark(@intFromBool(theme.dark));
    const css = std.fmt.allocPrintSentinel(app.gpa,
        "window {{ background-color: #{x:0>6}; color: #{x:0>6}; }}\n" ++
            "headerbar {{ background-color: #{x:0>6}; color: #{x:0>6}; }}\n" ++
            ".cadex-sidebar {{ background-color: #{x:0>6}; color: #{x:0>6}; }}\n" ++
            ".cadex-status {{ background-color: #{x:0>6}; color: #{x:0>6}; }}\n" ++
            ".cadex-pane-header {{ background-color: #{x:0>6}; color: #{x:0>6}; }}\n" ++
            ".cadex-tab-label {{ background-color: #{x:0>6}; color: #{x:0>6}; }}\n" ++
            ".cadex-term {{ background-color: #{x:0>6}; }}\n",
        .{
            theme.background, theme.foreground,
            theme.panel,      theme.foreground,
            theme.panel,      theme.foreground,
            theme.panel,      theme.foreground,
            theme.panel,      theme.foreground,
            theme.panel,      theme.foreground,
            theme.background,
        }, 0) catch return;
    defer app.gpa.free(css);
    c.cadex_css_apply(css.ptr);
    for (app.spaces.items) |space| {
        for (space.tabs.items) |tab| {
            for (tab.panes) |maybe| {
                if (maybe) |pane| {
                    if (pane.term) |term| {
                        var colors = themeColors(theme);
                        term.setColors(&colors);
                        term.setCursor(CURSOR_BLOCK, app.settings.cursor_blink);
                    }
                    schedulePaneRedraw(pane);
                }
            }
        }
    }
}

fn applySidebar(app: *App) void {
    c.cadex_widget_visible(app.sidebar, @intFromBool(app.settings.sidebar));
}

fn draw(ctx: ?*anyopaque, width: c_int, height: c_int, user: ?*anyopaque) callconv(.c) void {
    const pane: *Pane = @ptrCast(@alignCast(user.?));
    const app = pane.app;
    if (pane.closed) return;
    const term = pane.term orelse {
        c.cadex_draw_rect(ctx, 0, 0, @floatFromInt(width), @floatFromInt(height), 0x1e1e1e);
        return;
    };
    if (width < 2 * PAD or height < 2 * PAD) return;
    const cw = app.cell_w;
    const ch = app.cell_h;
    const cols: u16 = @intCast(@max(1, @min(1000, @divTrunc(width - 2 * PAD, cw))));
    const rows: u16 = @intCast(@max(1, @min(1000, @divTrunc(height - 2 * PAD, ch))));
    term.resize(cols, rows, @intCast(cw), @intCast(ch));
    const frame = term.updateFrame() orelse return;

    c.cadex_draw_rect(ctx, 0, 0, @floatFromInt(width), @floatFromInt(height), frame.background);
    const pad_f: f64 = @floatFromInt(PAD);
    const cw_f: f64 = @floatFromInt(cw);
    const ch_f: f64 = @floatFromInt(ch);
    const cursor_is_block = frame.cursor_visible and frame.cursor_style == CURSOR_BLOCK;
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
            const block_cursor = is_cursor and cursor_is_block;
            if (block_cursor) bg = if (frame.has_cursor_color) frame.cursor_color else 0xffffff;
            if (bg != frame.background or block_cursor) c.cadex_draw_rect(ctx, x, y, cw_f, ch_f, bg);
            if (cell.text_len > 0 and cell.flags & F_SPACER == 0) {
                var fg = cell.fg;
                if (block_cursor) fg = frame.background;
                const bold = cell.flags & F_BOLD != 0;
                const italic = cell.flags & F_ITALIC != 0;
                const text = frame.text + @as(usize, cell.text_offset);
                c.cadex_draw_text(ctx, text, @intCast(cell.text_len), x, y, fg, @intFromBool(bold), @intFromBool(italic));
            }
            const underline = (cell.flags >> 8) & 7;
            if (underline != 0) c.cadex_draw_line(ctx, x, y + ch_f - 1, x + cw_f, y + ch_f - 1, cell.fg);
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
    c.cadex_im_cursor(pane.area, im_x, im_y, cw, ch);
}

fn key(keyval: c_uint, keycode: c_uint, state: c_uint, user: ?*anyopaque) callconv(.c) c_int {
    _ = keycode;
    const pane: *Pane = @ptrCast(@alignCast(user.?));
    const app = pane.app;
    if (pane.closed) return 0;
    app.focused = pane;
    if (handleShortcut(app, keyval, state)) return 1;
    const term = pane.term orelse return 0;

    const shift = state & SHIFT != 0;
    const ctrl = state & CONTROL != 0;
    const alt = state & ALT != 0;
    const super = state & SUPER != 0;

    const special: u16 = switch (keyval) {
        0xff0d, 0xff8d => 1,
        0xff09 => 2,
        0xff08 => 3,
        0xff1b => 4,
        0xffff => 5,
        0xff63 => 6,
        0xff50 => 7,
        0xff57 => 8,
        0xff55 => 9,
        0xff56 => 10,
        0xff52 => 11,
        0xff54 => 12,
        0xff51 => 13,
        0xff53 => 14,
        0xffbe...0xffc9 => 15 + @as(u16, @intCast(keyval - 0xffbe)),
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

fn handleShortcut(app: *App, keyval: c_uint, state: c_uint) bool {
    const shift = state & SHIFT != 0;
    const ctrl = state & CONTROL != 0;
    const alt = state & ALT != 0;
    if (!ctrl or !shift) return false;
    const id: ?[]const u8 = switch (keyval) {
        'k', 'K' => "palette.open",
        't', 'T' => "tab.new",
        'w', 'W' => "tab.close",
        'd', 'D' => if (alt) "pane.split-down" else "pane.split-right",
        'f', 'F' => "terminal.find",
        'c', 'C' => "terminal.copy",
        'v', 'V' => "terminal.paste",
        'a', 'A' => "terminal.select-all",
        'b', 'B' => "view.toggle-sidebar",
        ',' => "settings.open",
        'q', 'Q' => "app.quit",
        'n', 'N' => if (alt) "space.next" else "space.new",
        0xff56 => if (alt) "space.next" else "tab.next",
        0xff55 => if (alt) "space.previous" else "tab.previous",
        else => null,
    };
    if (id) |command| {
        runCommand(app, command);
        return true;
    }
    return false;
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
    const pane: *Pane = @ptrCast(@alignCast(user.?));
    if (pane.closed) return;
    if (pane.term) |term| term.write(std.mem.span(raw));
}

fn pointer(x: c_int, y: c_int, button: c_int, state: c_uint, phase: c_int, clicks: c_int, user: ?*anyopaque) callconv(.c) void {
    if (button != 1) return;
    const pane: *Pane = @ptrCast(@alignCast(user.?));
    const app = pane.app;
    if (pane.closed) return;
    app.focused = pane;
    updateTitle(app);
    updateStatus(app);
    const term = pane.term orelse return;
    var ww: c_int = 0;
    var wh: c_int = 0;
    c.cadex_widget_size(pane.area, &ww, &wh);
    if (ww <= 0 or wh <= 0) return;
    const col_i = @divTrunc(x - PAD, app.cell_w);
    const row_i = @divTrunc(y - PAD, app.cell_h);
    const cols: i32 = @max(1, @divTrunc(ww - 2 * PAD, app.cell_w));
    const rows: i32 = @max(1, @divTrunc(wh - 2 * PAD, app.cell_h));
    const col: u16 = @intCast(std.math.clamp(col_i, 0, cols - 1));
    const row: u16 = @intCast(std.math.clamp(row_i, 0, rows - 1));

    if (state & CONTROL != 0 and phase == 0 and clicks == 1) {
        const link = term.linkAt(app.gpa, col, row) orelse return;
        defer app.gpa.free(link.target);
        const z = app.gpa.dupeZ(u8, link.target) catch return;
        defer app.gpa.free(z);
        if (link.kind == 1) _ = c.cadex_open_uri(z.ptr) else _ = c.cadex_open_path(z.ptr);
        return;
    }
    if (term.mouseTracking() != 0) {
        var event = std.mem.zeroes(core.cadex_terminal_mouse_event);
        event.x = @floatFromInt(x);
        event.y = @floatFromInt(y);
        event.view_width = @intCast(ww);
        event.view_height = @intCast(wh);
        event.cell_width = @intCast(app.cell_w);
        event.cell_height = @intCast(app.cell_h);
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
        .cell_width = @intCast(app.cell_w),
        .padding_left = @intCast(PAD),
        .view_height = @intCast(wh),
    };
    if (phase == 0) {
        term.selectPress(&p, @intCast(std.math.clamp(clicks, 1, 3)), state & SHIFT != 0);
    } else if (phase == 1) {
        term.selectDrag(&p);
    } else if (phase == 2) {
        term.selectRelease(&p);
    }
    schedulePaneRedraw(pane);
}

fn scroll(dx: f64, dy: f64, user: ?*anyopaque) callconv(.c) void {
    _ = dx;
    const pane: *Pane = @ptrCast(@alignCast(user.?));
    if (pane.closed) return;
    const app = pane.app;
    const term = pane.term orelse return;
    var ww: c_int = 0;
    var wh: c_int = 0;
    c.cadex_widget_size(pane.area, &ww, &wh);
    var event = std.mem.zeroes(core.cadex_terminal_mouse_event);
    event.view_width = @intCast(@max(ww, 0));
    event.view_height = @intCast(@max(wh, 0));
    event.cell_width = @intCast(app.cell_w);
    event.cell_height = @intCast(app.cell_h);
    event.padding = @intCast(PAD);
    event.action = 0;
    event.button = 0;
    term.wheel(&event, if (dy > 0) -3 else 3);
    schedulePaneRedraw(pane);
}

fn closePane(pane: *Pane) void {
    if (pane.closed) return;
    pane.closed = true;
    if (pane.term) |term| {
        term.close(pane.app.gpa);
        pane.term = null;
    }
    const app = pane.app;
    const tab = pane.tab;
    if (tab.closed) return;
    if (tab.panes[1] == null) {
        closeTab(tab);
        return;
    }
    const keep = if (tab.panes[0] == pane) tab.panes[1].? else tab.panes[0].?;
    c.cadex_paned_set_start(tab.content, null);
    c.cadex_paned_set_end(tab.content, null);
    c.cadex_widget_unparent(tab.content);
    c.cadex_box_append(tab.container, keep.container);
    tab.content = keep.container;
    tab.panes = .{ keep, null };
    app.focused = keep;
    c.cadex_widget_focus(keep.area);
    updateTitle(app);
    updateStatus(app);
}

fn closeTab(tab: *Tab) void {
    if (tab.closed) return;
    tab.closed = true;
    const app = tab.app;
    for (tab.panes) |maybe| {
        if (maybe) |pane| {
            pane.closed = true;
            if (pane.term) |term| {
                term.close(app.gpa);
                pane.term = null;
            }
        }
    }
    const index = c.cadex_notebook_page_num(tab.space.notebook, tab.container);
    if (index >= 0) c.cadex_notebook_remove(tab.space.notebook, index);
    for (tab.space.tabs.items, 0..) |item, i| {
        if (item == tab) {
            _ = tab.space.tabs.orderedRemove(i);
            break;
        }
    }
    if (tab.space.tabs.items.len == 0) {
        newTab(app, tab.space) catch {};
    } else {
        const page: usize = @intCast(@max(0, c.cadex_notebook_current(tab.space.notebook)));
        const next = tab.space.tabs.items[@min(page, tab.space.tabs.items.len - 1)];
        app.focused = next.panes[0];
        if (next.panes[0]) |pane| c.cadex_widget_focus(pane.area);
    }
    updateTitle(app);
    updateStatus(app);
}

fn splitPane(pane: *Pane, orientation: c_int) void {
    const tab = pane.tab;
    if (tab.closed or pane.closed) return;
    if (tab.panes[1] != null) {
        c.cadex_beep(pane.area);
        return;
    }
    const app = pane.app;
    const new = createPane(app, tab) catch {
        c.cadex_beep(pane.area);
        return;
    };
    c.cadex_widget_unparent(tab.content);
    const paned = c.cadex_paned_new(orientation) orelse return;
    c.cadex_paned_set_start(paned, tab.content);
    c.cadex_paned_set_end(paned, new.container);
    c.cadex_box_append(tab.container, paned);
    tab.content = paned;
    tab.panes[1] = new;
    tab.orientation = orientation;
    app.focused = new;
    c.cadex_widget_focus(new.area);
    updateTitle(app);
    updateStatus(app);
}

fn tabCloseClicked(user: ?*anyopaque) callconv(.c) void {
    const tab: *Tab = @ptrCast(@alignCast(user.?));
    closeTab(tab);
}

fn paneCloseClicked(user: ?*anyopaque) callconv(.c) void {
    const pane: *Pane = @ptrCast(@alignCast(user.?));
    closePane(pane);
}

fn cmdNewTab(app: *App) void {
    newTab(app, currentSpace(app)) catch {};
}

fn cmdCloseTab(app: *App) void {
    const pane = app.focused orelse return;
    closeTab(pane.tab);
}

fn cmdNextTab(app: *App) void {
    const space = currentSpace(app);
    const count = c.cadex_notebook_count(space.notebook);
    if (count <= 1) return;
    const next = @mod(c.cadex_notebook_current(space.notebook) + 1, count);
    c.cadex_notebook_set_current(space.notebook, next);
}

fn cmdPrevTab(app: *App) void {
    const space = currentSpace(app);
    const count = c.cadex_notebook_count(space.notebook);
    if (count <= 1) return;
    var next = c.cadex_notebook_current(space.notebook) - 1;
    if (next < 0) next = count - 1;
    c.cadex_notebook_set_current(space.notebook, next);
}

fn cmdSplitRight(app: *App) void {
    if (app.focused) |pane| splitPane(pane, HORIZONTAL);
}

fn cmdSplitDown(app: *App) void {
    if (app.focused) |pane| splitPane(pane, VERTICAL);
}

fn cmdClosePane(app: *App) void {
    if (app.focused) |pane| closePane(pane);
}

fn cmdPalette(app: *App) void {
    paletteOpen(app);
}

fn cmdSettings(app: *App) void {
    settingsOpen(app);
}

fn cmdQuit(app: *App) void {
    c.cadex_window_close(app.window);
}

fn cmdToggleSidebar(app: *App) void {
    app.settings.sidebar = !app.settings.sidebar;
    applySidebar(app);
    saveSettings(app);
}

fn cmdFind(app: *App) void {
    toggleFind(app);
}

fn cmdCopy(app: *App) void {
    const pane = app.focused orelse return;
    const term = pane.term orelse return;
    const text = term.copySelection(app.gpa) orelse return;
    defer app.gpa.free(text);
    const z = app.gpa.dupeZ(u8, text) catch return;
    defer app.gpa.free(z);
    c.cadex_clipboard_set(pane.area, z.ptr);
}

fn cmdPaste(app: *App) void {
    const pane = app.focused orelse return;
    c.cadex_clipboard_get(pane.area, clipboardText, pane);
}

fn cmdSelectAll(app: *App) void {
    const pane = app.focused orelse return;
    if (pane.term) |term| {
        term.selectAll();
        schedulePaneRedraw(pane);
    }
}

fn cmdSpaceNew(app: *App) void {
    newSpace(app) catch {};
}

fn cmdSpaceNext(app: *App) void {
    if (app.spaces.items.len == 0) return;
    switchSpace(app, (app.space_index + 1) % app.spaces.items.len);
}

fn cmdSpacePrev(app: *App) void {
    if (app.spaces.items.len == 0) return;
    const next = if (app.space_index == 0) app.spaces.items.len - 1 else app.space_index - 1;
    switchSpace(app, next);
}

fn cmdSidebarFiles(app: *App) void {
    c.cadex_stack_set(app.sidebar_stack, "files");
}

fn cmdSidebarGit(app: *App) void {
    c.cadex_stack_set(app.sidebar_stack, "git");
}

fn cmdSidebarHistory(app: *App) void {
    c.cadex_stack_set(app.sidebar_stack, "history");
}

fn sidebarClicked(user: ?*anyopaque) callconv(.c) void {
    const app: *App = @ptrCast(@alignCast(user.?));
    cmdToggleSidebar(app);
}

fn sidebarFilesClicked(user: ?*anyopaque) callconv(.c) void {
    const app: *App = @ptrCast(@alignCast(user.?));
    cmdSidebarFiles(app);
}

fn sidebarGitClicked(user: ?*anyopaque) callconv(.c) void {
    const app: *App = @ptrCast(@alignCast(user.?));
    cmdSidebarGit(app);
}

fn sidebarHistoryClicked(user: ?*anyopaque) callconv(.c) void {
    const app: *App = @ptrCast(@alignCast(user.?));
    cmdSidebarHistory(app);
}

fn paletteClicked(user: ?*anyopaque) callconv(.c) void {
    const app: *App = @ptrCast(@alignCast(user.?));
    paletteOpen(app);
}

fn settingsClicked(user: ?*anyopaque) callconv(.c) void {
    const app: *App = @ptrCast(@alignCast(user.?));
    settingsOpen(app);
}

fn runCommand(app: *App, id: []const u8) void {
    for (commands) |command| {
        if (std.mem.eql(u8, command.id, id)) {
            command.run(app);
            return;
        }
    }
}

fn clipboardText(text: [*c]const u8, user: ?*anyopaque) callconv(.c) void {
    if (text == null) return;
    const pane: *Pane = @ptrCast(@alignCast(user.?));
    if (pane.closed) return;
    if (pane.term) |term| term.paste(std.mem.span(@as([*:0]const u8, @ptrCast(text))));
}

fn toggleFind(app: *App) void {
    if (app.find_open) {
        findEscape(app);
        return;
    }
    app.find_open = true;
    c.cadex_widget_visible(app.find_entry, 1);
    c.cadex_entry_select_all(app.find_entry);
    c.cadex_widget_focus(app.find_entry);
}

fn findChanged(user: ?*anyopaque) callconv(.c) void {
    const app: *App = @ptrCast(@alignCast(user.?));
    const raw = c.cadex_entry_text(app.find_entry);
    if (raw == null) return;
    const text = std.mem.span(@as([*:0]const u8, @ptrCast(raw)));
    const pane = app.focused orelse return;
    const term = pane.term orelse return;
    if (text.len == 0) {
        term.searchStop();
    } else {
        term.searchStart(text);
        _ = term.searchSelect(0);
    }
    schedulePaneRedraw(pane);
}

fn findActivate(user: ?*anyopaque) callconv(.c) void {
    const app: *App = @ptrCast(@alignCast(user.?));
    const pane = app.focused orelse return;
    if (pane.term) |term| _ = term.searchSelect(0);
    schedulePaneRedraw(pane);
}

fn findEscape(user: ?*anyopaque) callconv(.c) void {
    const app: *App = @ptrCast(@alignCast(user.?));
    app.find_open = false;
    c.cadex_widget_visible(app.find_entry, 0);
    if (app.focused) |pane| {
        if (pane.term) |term| term.searchStop();
        c.cadex_widget_focus(pane.area);
    }
}

fn paletteOpen(app: *App) void {
    if (app.palette_window == null) paletteCreate(app);
    const window = app.palette_window orelse return;
    c.cadex_entry_clear(app.palette_entry orelse return);
    paletteFilter(app);
    c.cadex_window_present(window, 0);
    c.cadex_widget_focus(app.palette_entry orelse return);
}

fn paletteCreate(app: *App) void {
    const window = c.cadex_window_new_dialog(app.window, "Cadex", 640, 420) orelse return;
    c.cadex_window_hide_on_close(window);
    c.cadex_widget_on_escape(window, paletteHide, app);
    const box = c.cadex_box_new() orelse return;
    const entry = c.cadex_entry_new() orelse return;
    c.cadex_widget_visible(entry, 1);
    c.cadex_entry_changed(entry, paletteChanged, app);
    c.cadex_entry_activate(entry, paletteActivate, app);
    c.cadex_entry_escape(entry, paletteHide, app);
    c.cadex_box_append(box, entry);
    const list = c.cadex_listbox_new() orelse return;
    c.cadex_listbox_on_activated(list, paletteRow, app);
    const scrolled = c.cadex_scrolled_new(list) orelse return;
    c.cadex_widget_expand(scrolled);
    c.cadex_box_append(box, scrolled);
    c.cadex_window_child(window, box);
    app.palette_window = window;
    app.palette_entry = entry;
    app.palette_list = list;
}

fn paletteFilter(app: *App) void {
    const entry = app.palette_entry orelse return;
    const list = app.palette_list orelse return;
    const raw = c.cadex_entry_text(entry);
    const query = if (raw == null) "" else std.mem.span(@as([*:0]const u8, @ptrCast(raw)));
    c.cadex_listbox_clear(list);
    app.palette_filtered.clearRetainingCapacity();
    for (&commands) |*command| {
        if (query.len > 0 and !containsIgnoreCase(command.title, query) and !containsIgnoreCase(command.keywords, query)) continue;
        app.palette_filtered.append(app.gpa, command) catch return;
        var buf: [160]u8 = undefined;
        const text = if (command.shortcut.len > 0)
            std.fmt.bufPrintZ(&buf, "{s}    {s}", .{ command.title, command.shortcut }) catch command.title
        else
            command.title;
        c.cadex_listbox_append(list, @ptrCast(text.ptr));
    }
}

fn paletteChanged(user: ?*anyopaque) callconv(.c) void {
    const app: *App = @ptrCast(@alignCast(user.?));
    paletteFilter(app);
}

fn paletteActivate(user: ?*anyopaque) callconv(.c) void {
    const app: *App = @ptrCast(@alignCast(user.?));
    if (app.palette_filtered.items.len == 0) return;
    const command = app.palette_filtered.items[0];
    paletteHide(app);
    command.run(app);
}

fn paletteRow(index: c_int, user: ?*anyopaque) callconv(.c) void {
    const app: *App = @ptrCast(@alignCast(user.?));
    if (index < 0) return;
    const at: usize = @intCast(index);
    if (at >= app.palette_filtered.items.len) return;
    const command = app.palette_filtered.items[at];
    paletteHide(app);
    command.run(app);
}

fn paletteHide(user: ?*anyopaque) callconv(.c) void {
    const app: *App = @ptrCast(@alignCast(user.?));
    if (app.palette_window) |window| c.cadex_window_hide(window);
    if (app.focused) |pane| c.cadex_widget_focus(pane.area);
}

fn containsIgnoreCase(haystack: []const u8, needle: []const u8) bool {
    if (needle.len == 0) return true;
    if (needle.len > haystack.len) return false;
    var i: usize = 0;
    while (i + needle.len <= haystack.len) : (i += 1) {
        var j: usize = 0;
        while (j < needle.len) : (j += 1) {
            if (std.ascii.toLower(haystack[i + j]) != std.ascii.toLower(needle[j])) break;
        }
        if (j == needle.len) return true;
    }
    return false;
}

fn settingsOpen(app: *App) void {
    if (app.settings_window == null) settingsCreate(app);
    const window = app.settings_window orelse return;
    if (app.settings_theme) |dd| c.cadex_dropdown_set_selected(dd, @intCast(app.theme_index));
    if (app.settings_font) |spin| c.cadex_spin_set_value(spin, app.settings.font_size);
    if (app.settings_blink) |button| c.cadex_button_set_text(button, if (app.settings.cursor_blink) "On" else "Off");
    if (app.settings_sidebar) |button| c.cadex_button_set_text(button, if (app.settings.sidebar) "On" else "Off");
    c.cadex_window_present(window, 0);
}

fn settingsCreate(app: *App) void {
    const window = c.cadex_window_new_dialog(app.window, "Settings", 620, 400) orelse return;
    c.cadex_window_hide_on_close(window);
    c.cadex_widget_on_escape(window, settingsClose, app);
    const box = c.cadex_box_new() orelse return;
    const title = c.cadex_label_new("Settings") orelse return;
    c.cadex_widget_add_class(title, "cadex-settings-title");
    c.cadex_box_append(box, title);
    const dd = c.cadex_dropdown_new(@ptrCast(&theme_names), @intCast(theme_names.len)) orelse return;
    c.cadex_dropdown_set_selected(dd, @intCast(app.theme_index));
    c.cadex_dropdown_on_changed(dd, settingsThemeChanged, app);
    addRow(app, box, "Theme", dd);
    const spin = c.cadex_spin_new(8, 24, 1) orelse return;
    c.cadex_spin_set_value(spin, app.settings.font_size);
    c.cadex_spin_on_changed(spin, settingsFontChanged, app);
    addRow(app, box, "Font size", spin);
    const blink = c.cadex_button_new(if (app.settings.cursor_blink) "On" else "Off", settingsBlinkClicked, app) orelse return;
    addRow(app, box, "Cursor blink", blink);
    const sidebar = c.cadex_button_new(if (app.settings.sidebar) "On" else "Off", settingsSidebarClicked, app) orelse return;
    addRow(app, box, "Sidebar", sidebar);
    const about = c.cadex_label_new("Cadex — Linux preview\nGTK4 on Wayland") orelse return;
    c.cadex_box_append(box, about);
    const close = c.cadex_button_new("Close", settingsClose, app) orelse return;
    c.cadex_box_append(box, close);
    c.cadex_window_child(window, box);
    app.settings_window = window;
    app.settings_theme = dd;
    app.settings_font = spin;
    app.settings_blink = blink;
    app.settings_sidebar = sidebar;
}

fn addRow(_: *App, box: *anyopaque, text: [:0]const u8, control: *anyopaque) void {
    const row = c.cadex_box_new_h(8) orelse return;
    const label = c.cadex_label_new(text.ptr) orelse return;
    c.cadex_widget_expand(label);
    c.cadex_box_append(row, label);
    c.cadex_box_append(row, control);
    c.cadex_box_append(box, row);
}

fn settingsThemeChanged(user: ?*anyopaque) callconv(.c) void {
    const app: *App = @ptrCast(@alignCast(user.?));
    const dd = app.settings_theme orelse return;
    const selected = c.cadex_dropdown_selected(dd);
    if (selected < 0 or selected >= themes.len) return;
    app.theme_index = @intCast(selected);
    applyTheme(app);
    saveSettings(app);
}

fn settingsFontChanged(user: ?*anyopaque) callconv(.c) void {
    const app: *App = @ptrCast(@alignCast(user.?));
    const spin = app.settings_font orelse return;
    const value = c.cadex_spin_value(spin);
    if (value < 8 or value > 24) return;
    app.settings.font_size = value;
    applyFont(app);
    saveSettings(app);
}

fn settingsBlinkClicked(user: ?*anyopaque) callconv(.c) void {
    const app: *App = @ptrCast(@alignCast(user.?));
    app.settings.cursor_blink = !app.settings.cursor_blink;
    if (app.settings_blink) |button| c.cadex_button_set_text(button, if (app.settings.cursor_blink) "On" else "Off");
    for (app.spaces.items) |space| {
        for (space.tabs.items) |tab| {
            for (tab.panes) |maybe| {
                if (maybe) |pane| if (pane.term) |term| term.setCursor(CURSOR_BLOCK, app.settings.cursor_blink);
            }
        }
    }
    saveSettings(app);
}

fn settingsSidebarClicked(user: ?*anyopaque) callconv(.c) void {
    const app: *App = @ptrCast(@alignCast(user.?));
    app.settings.sidebar = !app.settings.sidebar;
    if (app.settings_sidebar) |button| c.cadex_button_set_text(button, if (app.settings.sidebar) "On" else "Off");
    applySidebar(app);
    saveSettings(app);
}

fn settingsClose(user: ?*anyopaque) callconv(.c) void {
    const app: *App = @ptrCast(@alignCast(user.?));
    if (app.settings_window) |window| c.cadex_window_hide(window);
}

fn themeIndex(name: []const u8) usize {
    for (themes, 0..) |theme, i| if (std.mem.eql(u8, theme.name, name)) return i;
    return 0;
}

fn settingsPath(app: *App) ![:0]u8 {
    if (std.c.getenv("XDG_CONFIG_HOME")) |base_z| {
        const base = std.mem.span(base_z);
        const dir = try std.fmt.allocPrintSentinel(app.gpa, "{s}/cadex", .{base}, 0);
        defer app.gpa.free(dir);
        _ = c.cadex_make_dir(dir.ptr);
        return std.fmt.allocPrintSentinel(app.gpa, "{s}/settings.json", .{dir}, 0);
    }
    const home_z = std.c.getenv("HOME") orelse return error.NoHome;
    const home = std.mem.span(home_z);
    const dir = try std.fmt.allocPrintSentinel(app.gpa, "{s}/.config/cadex", .{home}, 0);
    defer app.gpa.free(dir);
    _ = c.cadex_make_dir(dir.ptr);
    return std.fmt.allocPrintSentinel(app.gpa, "{s}/settings.json", .{dir}, 0);
}

fn loadSettings(app: *App) void {
    const path = settingsPath(app) catch return;
    defer app.gpa.free(path);
    var len: usize = 0;
    const raw = c.cadex_read_file(path.ptr, &len);
    if (raw == null) return;
    defer c.cadex_gtk_free(@ptrCast(raw));
    const Parsed = struct {
        theme: ?[]const u8 = null,
        font_size: ?i32 = null,
        cursor_blink: ?bool = null,
        sidebar: ?bool = null,
    };
    var parsed = std.json.parseFromSlice(Parsed, app.gpa, raw[0..len], .{ .ignore_unknown_fields = true }) catch return;
    defer parsed.deinit();
    if (parsed.value.theme) |name| app.theme_index = themeIndex(name);
    if (parsed.value.font_size) |size| if (size >= 8 and size <= 24) {
        app.settings.font_size = size;
    };
    if (parsed.value.cursor_blink) |value| app.settings.cursor_blink = value;
    if (parsed.value.sidebar) |value| app.settings.sidebar = value;
}

fn saveSettings(app: *App) void {
    const path = settingsPath(app) catch return;
    defer app.gpa.free(path);
    const theme = themes[app.theme_index];
    const data = std.fmt.allocPrint(app.gpa, "{{\"theme\":\"{s}\",\"font_size\":{d},\"cursor_blink\":{s},\"sidebar\":{s}}}\n", .{
        theme.name,
        app.settings.font_size,
        if (app.settings.cursor_blink) "true" else "false",
        if (app.settings.sidebar) "true" else "false",
    }) catch return;
    defer app.gpa.free(data);
    _ = c.cadex_write_file(path.ptr, data.ptr, data.len);
}
