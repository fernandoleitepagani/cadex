//! Cadex on Linux: a GTK4/Wayland shell over the core terminal.

const std = @import("std");
const core = @import("cadex");
const system = @import("system");
const terminal = @import("terminal");
const documents = @import("documents");

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

const TabKind = enum { terminal, document };

const Tab = struct {
    app: *App,
    space: *Space,
    container: *anyopaque,
    content: *anyopaque,
    label_box: *anyopaque,
    title_label: *anyopaque,
    kind: TabKind = .terminal,
    doc: ?*Doc = null,
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

const Doc = struct {
    app: *App,
    tab: *Tab,
    path: [:0]u8, // absolute; empty for virtual documents
    title: [:0]u8,
    view: *anyopaque,
    buffer: *anyopaque,
    scroll: *anyopaque,
    editor: ?*core.cadex_editor_document = null,
    language: []const u8 = "Text",
    markdown: bool = false,
    virtual: bool = false,
    diff: bool = false,
    dirty: bool = false,
    alive: bool = true,
    preview_scroll: ?*anyopaque = null,
    preview_label: ?*anyopaque = null,
    preview_visible: bool = true,
    save_button: ?*anyopaque = null,
    preview_button: ?*anyopaque = null,
    language_buf: [48]u8 = undefined,
};

const Entry = struct {
    name: []u8,
    path: [:0]u8,
    directory: bool,
};

const SearchMode = enum { files, content };

const SpinLock = struct {
    locked: std.atomic.Value(bool) = .init(false),

    fn lock(self: *SpinLock) void {
        while (self.locked.swap(true, .acquire)) std.atomic.spinLoopHint();
    }

    fn unlock(self: *SpinLock) void {
        self.locked.store(false, .release);
    }
};

const SearchHit = struct {
    path: []u8,
    line: u32,
    text: []u8,
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
    message_label: *anyopaque = undefined,
    spaces: std.ArrayList(*Space) = .empty,
    space_index: usize = 0,
    focused: ?*Pane = null,
    active_doc: ?*Doc = null,
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

    // Workspace and explorer (Run 4).
    root: [:0]u8 = undefined,
    files_path: [:0]u8 = undefined,
    files_list: *anyopaque = undefined,
    files_title: *anyopaque = undefined,
    files_entries: std.ArrayList(Entry) = .empty,
    files_watcher: ?*core.cadex_explorer_watcher = null,
    files_pending: std.atomic.Value(bool) = .init(false),

    // Search (Run 4).
    file_search_index: ?*core.cadex_search_index = null,
    search_entry: *anyopaque = undefined,
    search_list: *anyopaque = undefined,
    search_status: *anyopaque = undefined,
    search_mode: SearchMode = .files,
    search_hits: std.ArrayList(SearchHit) = .empty,
    search_mutex: SpinLock = .{},
    search_pending: std.atomic.Value(bool) = .init(false),
    search_content: ?*core.cadex_search_content = null,
    search_done: bool = false,
    search_truncated: bool = false,
    search_files_searched: u32 = 0,

    // Source control (Run 4).
    git_list: *anyopaque = undefined,
    git_branch: *anyopaque = undefined,
    git_status: *anyopaque = undefined,
    git_commit_entry: *anyopaque = undefined,
    git_repo: ?[:0]u8 = null,
    git_status_data: ?documents.git.Status = null,
    git_selected: ?usize = null,

    // History (Run 4).
    history_list: *anyopaque = undefined,
    history_status: *anyopaque = undefined,
    history_log: ?*core.cadex_history = null,
    history_commits: std.ArrayList(documents.git.Commit) = .empty,
    history_has_more: bool = true,
    history_loaded: bool = false,

    // New file/folder prompt.
    prompt_window: ?*anyopaque = null,
    prompt_entry: ?*anyopaque = null,
    prompt_dir: bool = false,
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
    .{ .id = "sidebar.files", .title = "Explorer", .keywords = "sidebar files explorer", .shortcut = "Ctrl+Shift+E", .run = cmdSidebarFiles },
    .{ .id = "sidebar.search", .title = "Search Files and Content", .keywords = "sidebar search find files content", .shortcut = "Ctrl+Shift+P", .run = cmdSidebarSearch },
    .{ .id = "sidebar.git", .title = "Source Control", .keywords = "sidebar git source control", .shortcut = "Ctrl+Shift+G", .run = cmdSidebarGit },
    .{ .id = "sidebar.history", .title = "Git History", .keywords = "sidebar history git log", .shortcut = "Ctrl+Shift+H", .run = cmdSidebarHistory },
    .{ .id = "document.save", .title = "Save Document", .keywords = "save write file", .shortcut = "Ctrl+Shift+S", .run = cmdSaveDocument },
    .{ .id = "document.preview", .title = "Toggle Markdown Preview", .keywords = "preview markdown render", .shortcut = "Ctrl+Shift+M", .run = cmdTogglePreview },
    .{ .id = "explorer.new-file", .title = "New File", .keywords = "explorer file create", .shortcut = "", .run = cmdNewFile },
    .{ .id = "explorer.new-folder", .title = "New Folder", .keywords = "explorer folder create", .shortcut = "", .run = cmdNewFolder },
    .{ .id = "explorer.refresh", .title = "Refresh Explorer", .keywords = "explorer files refresh", .shortcut = "", .run = cmdRefreshExplorer },
    .{ .id = "git.commit-message", .title = "Write Commit Message", .keywords = "git commit message", .shortcut = "Ctrl+Shift+Alt+C", .run = cmdGitCommitMessage },
    .{ .id = "git.refresh", .title = "Refresh Source Control", .keywords = "git status refresh", .shortcut = "", .run = cmdRefreshGit },
    .{ .id = "history.refresh", .title = "Refresh Git History", .keywords = "git history log refresh", .shortcut = "", .run = cmdRefreshHistory },
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
    launch.* = .{
        .background = std.c.getenv("CADEX_BACKGROUND") != null,
        .root = discoverRoot(gpa),
    };
    const gtk_app = c.cadex_app_new() orelse {
        std.debug.print("cadex: cannot create the GTK application\n", .{});
        std.process.exit(1);
    };
    c.cadex_app_activate(gtk_app, onActivate, launch);
    const status = c.cadex_app_run(gtk_app);
    std.process.exit(@intCast(status));
}

extern "c" fn getcwd(buf: [*]u8, size: usize) ?[*:0]u8;
extern "c" fn open(path: [*:0]const u8, flags: c_int, ...) c_int;
extern "c" fn read(fd: c_int, buf: [*]u8, count: usize) isize;
extern "c" fn close(fd: c_int) c_int;

fn discoverRoot(gpa: std.mem.Allocator) ?[:0]u8 {
    var cwd_buf: [4096]u8 = undefined;
    const cwd_ptr = getcwd(&cwd_buf, cwd_buf.len) orelse return null;
    const cwd = std.mem.span(cwd_ptr);
    const cwd_z = gpa.dupeZ(u8, cwd) catch return null;
    defer gpa.free(cwd_z);

    var args_buf: [65536]u8 = undefined;
    var argv: std.ArrayList([*c]const u8) = .empty;
    defer argv.deinit(gpa);
    const fd = open("/proc/self/cmdline", 0);
    if (fd >= 0) {
        defer _ = close(fd);
        const n = read(fd, &args_buf, args_buf.len);
        if (n > 0) {
            var it = std.mem.splitScalar(u8, args_buf[0..@intCast(n)], 0);
            while (it.next()) |part| {
                if (part.len == 0) break;
                argv.append(gpa, @ptrCast(part.ptr)) catch break;
            }
        }
    }

    if (argv.items.len > 0) {
        var out: ?[*]u8 = null;
        var out_len: usize = 0;
        if (core.cadex_workspace_launch_directory(@ptrCast(argv.items.ptr), argv.items.len, cwd_z.ptr, &out, &out_len) == core.CADEX_OK and out != null) {
            const root = gpa.dupeZ(u8, out.?[0..out_len]) catch null;
            core.cadex_free(@ptrCast(out.?));
            if (root) |found| return found;
        }
    }
    return gpa.dupeZ(u8, cwd) catch null;
}

const Launch = struct {
    background: bool,
    root: ?[:0]u8 = null,
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
    initWorkspace(app, launch);

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
    c.cadex_widget_set_size(app.sidebar, 300, -1);
    c.cadex_widget_add_class(app.sidebar, "cadex-sidebar");
    var title_buf: [256]u8 = undefined;
    const sidebar_title = c.cadex_label_new(std.fmt.bufPrintZ(&title_buf, "Cadex · {s}", .{std.fs.path.basename(app.root)}) catch "Cadex") orelse return error.GtkFailed;
    c.cadex_widget_add_class(sidebar_title, "cadex-sidebar-title");
    c.cadex_box_append(app.sidebar, sidebar_title);
    const icons = c.cadex_box_new_h(4) orelse return error.GtkFailed;
    c.cadex_box_append(icons, c.cadex_button_new("Files", sidebarFilesClicked, app) orelse return error.GtkFailed);
    c.cadex_box_append(icons, c.cadex_button_new("Search", sidebarSearchClicked, app) orelse return error.GtkFailed);
    c.cadex_box_append(icons, c.cadex_button_new("Git", sidebarGitClicked, app) orelse return error.GtkFailed);
    c.cadex_box_append(icons, c.cadex_button_new("History", sidebarHistoryClicked, app) orelse return error.GtkFailed);
    c.cadex_box_append(app.sidebar, icons);
    app.sidebar_stack = c.cadex_stack_new() orelse return error.GtkFailed;
    c.cadex_stack_add(app.sidebar_stack, try buildFilesPage(app), "files");
    c.cadex_stack_add(app.sidebar_stack, try buildSearchPage(app), "search");
    c.cadex_stack_add(app.sidebar_stack, try buildGitPage(app), "git");
    c.cadex_stack_add(app.sidebar_stack, try buildHistoryPage(app), "history");
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
    app.message_label = c.cadex_label_new("") orelse return error.GtkFailed;
    c.cadex_label_ellipsize(app.message_label);
    c.cadex_widget_expand_h(app.message_label);
    app.tabs_label = c.cadex_label_new("1 tab") orelse return error.GtkFailed;
    c.cadex_box_append(status, app.cwd_label);
    c.cadex_box_append(status, app.message_label);
    c.cadex_box_append(status, app.tabs_label);
    c.cadex_box_append(app.content, status);

    c.cadex_paned_set_start(main_box, app.sidebar);
    c.cadex_paned_set_end(main_box, app.content);
    c.cadex_paned_set_position(main_box, 300);
    c.cadex_window_child(app.window, main_box);
    c.cadex_window_on_close(app.window, closeCb, app);
    c.cadex_window_on_key(app.window, windowKey, app);

    try newSpace(app);
    applyFont(app);
    applyTheme(app);
    applySidebar(app);
    c.cadex_stack_set(app.sidebar_stack, "files");
    refreshFiles(app);
    refreshGit(app);
    loadHistory(app, false);
    c.cadex_window_present(app.window, @intFromBool(launch.background));
    if (app.focused) |pane| c.cadex_widget_focus(pane.area);
    _ = c.cadex_timeout(1000, statusTimer, app);
}

fn initWorkspace(app: *App, launch: *Launch) void {
    const gpa = app.gpa;
    var root: [:0]u8 = undefined;
    if (launch.root) |given| {
        var out: ?[*]u8 = null;
        var len: usize = 0;
        if (core.cadex_workspace_authorize(given.ptr, &out, &len) == core.CADEX_OK and out != null) {
            const p = out.?;
            root = gpa.dupeZ(u8, p[0..len]) catch (gpa.dupeZ(u8, given) catch return);
            core.cadex_free(@ptrCast(p));
        } else {
            root = gpa.dupeZ(u8, given) catch return;
        }
    } else {
        root = discoverRoot(gpa) orelse return;
    }
    app.root = root;
    app.files_path = gpa.dupeZ(u8, root) catch root;

    var index: ?*core.cadex_search_index = null;
    if (core.cadex_search_index_open(root.ptr, false, &index) == core.CADEX_OK and index != null) {
        app.file_search_index = index;
        core.cadex_search_index_focus(index.?, root.ptr);
    }

    var watcher: ?*core.cadex_explorer_watcher = null;
    if (core.cadex_explorer_watch(root.ptr, app, onWorkspaceChange, &watcher) == core.CADEX_OK) {
        app.files_watcher = watcher;
    }
}

fn onWorkspaceChange(context: ?*anyopaque, changes: [*c]const core.cadex_explorer_change, count: usize) callconv(.c) void {
    _ = changes;
    _ = count;
    const raw = context orelse return;
    const app: *App = @ptrCast(@alignCast(raw));
    if (app.closing) return;
    if (!app.files_pending.swap(true, .acq_rel)) c.cadex_idle(workspaceChangedIdle, app);
}

fn workspaceChangedIdle(user: ?*anyopaque) callconv(.c) void {
    const app: *App = @ptrCast(@alignCast(user.?));
    app.files_pending.store(false, .release);
    if (app.closing) return;
    refreshFiles(app);
    refreshGit(app);
}

fn buildFilesPage(app: *App) !*anyopaque {
    const page = c.cadex_box_new() orelse return error.GtkFailed;
    c.cadex_widget_add_class(page, "cadex-page");
    const head = c.cadex_box_new_h(4) orelse return error.GtkFailed;
    app.files_title = c.cadex_label_new("Files") orelse return error.GtkFailed;
    c.cadex_label_ellipsize(app.files_title);
    c.cadex_widget_expand_h(app.files_title);
    c.cadex_box_append(head, app.files_title);
    c.cadex_box_append(head, c.cadex_button_new("Up", filesUpClicked, app) orelse return error.GtkFailed);
    c.cadex_box_append(page, head);
    const actions = c.cadex_box_new_h(4) orelse return error.GtkFailed;
    c.cadex_box_append(actions, c.cadex_button_new("New File", newFileClicked, app) orelse return error.GtkFailed);
    c.cadex_box_append(actions, c.cadex_button_new("New Folder", newFolderClicked, app) orelse return error.GtkFailed);
    c.cadex_box_append(actions, c.cadex_button_new("Refresh", filesRefreshClicked, app) orelse return error.GtkFailed);
    c.cadex_box_append(page, actions);
    app.files_list = c.cadex_listbox_new() orelse return error.GtkFailed;
    c.cadex_listbox_on_activated(app.files_list, filesRowActivated, app);
    c.cadex_listbox_on_keys(app.files_list, filesRowActivated, app);
    const scrolled = c.cadex_scrolled_new(app.files_list) orelse return error.GtkFailed;
    c.cadex_widget_expand(scrolled);
    c.cadex_box_append(page, scrolled);
    return page;
}

fn buildSearchPage(app: *App) !*anyopaque {
    const page = c.cadex_box_new() orelse return error.GtkFailed;
    c.cadex_widget_add_class(page, "cadex-page");
    const entry = c.cadex_entry_new() orelse return error.GtkFailed;
    c.cadex_entry_set_placeholder(entry, "Search files, Enter for content");
    c.cadex_entry_changed(entry, searchChanged, app);
    c.cadex_entry_activate(entry, searchActivated, app);
    c.cadex_box_append(page, entry);
    app.search_entry = entry;
    const modes = c.cadex_box_new_h(4) orelse return error.GtkFailed;
    c.cadex_box_append(modes, c.cadex_button_new("Files", searchFilesClicked, app) orelse return error.GtkFailed);
    c.cadex_box_append(modes, c.cadex_button_new("Content", searchContentClicked, app) orelse return error.GtkFailed);
    app.search_status = c.cadex_label_new("Files") orelse return error.GtkFailed;
    c.cadex_label_ellipsize(app.search_status);
    c.cadex_widget_expand_h(app.search_status);
    c.cadex_box_append(modes, app.search_status);
    c.cadex_box_append(page, modes);
    app.search_list = c.cadex_listbox_new() orelse return error.GtkFailed;
    c.cadex_listbox_on_activated(app.search_list, searchRowActivated, app);
    c.cadex_listbox_on_keys(app.search_list, searchRowActivated, app);
    const scrolled = c.cadex_scrolled_new(app.search_list) orelse return error.GtkFailed;
    c.cadex_widget_expand(scrolled);
    c.cadex_box_append(page, scrolled);
    return page;
}

fn buildGitPage(app: *App) !*anyopaque {
    const page = c.cadex_box_new() orelse return error.GtkFailed;
    c.cadex_widget_add_class(page, "cadex-page");
    const head = c.cadex_box_new_h(4) orelse return error.GtkFailed;
    app.git_branch = c.cadex_label_new("Source control") orelse return error.GtkFailed;
    c.cadex_label_ellipsize(app.git_branch);
    c.cadex_widget_expand_h(app.git_branch);
    c.cadex_box_append(head, app.git_branch);
    c.cadex_box_append(head, c.cadex_button_new("Refresh", gitRefreshClicked, app) orelse return error.GtkFailed);
    c.cadex_box_append(page, head);
    const stage_row = c.cadex_box_new_h(4) orelse return error.GtkFailed;
    c.cadex_box_append(stage_row, c.cadex_button_new("Stage", gitStageClicked, app) orelse return error.GtkFailed);
    c.cadex_box_append(stage_row, c.cadex_button_new("Unstage", gitUnstageClicked, app) orelse return error.GtkFailed);
    c.cadex_box_append(stage_row, c.cadex_button_new("Discard", gitDiscardClicked, app) orelse return error.GtkFailed);
    c.cadex_box_append(page, stage_row);
    const action_row = c.cadex_box_new_h(4) orelse return error.GtkFailed;
    c.cadex_box_append(action_row, c.cadex_button_new("Commit All", gitCommitClicked, app) orelse return error.GtkFailed);
    c.cadex_box_append(action_row, c.cadex_button_new("Push", gitPushClicked, app) orelse return error.GtkFailed);
    c.cadex_box_append(action_row, c.cadex_button_new("Pull", gitPullClicked, app) orelse return error.GtkFailed);
    c.cadex_box_append(action_row, c.cadex_button_new("Fetch", gitFetchClicked, app) orelse return error.GtkFailed);
    c.cadex_box_append(page, action_row);
    app.git_commit_entry = c.cadex_entry_new() orelse return error.GtkFailed;
    c.cadex_entry_set_placeholder(app.git_commit_entry, "Commit message");
    c.cadex_entry_activate(app.git_commit_entry, gitCommitClicked, app);
    c.cadex_box_append(page, app.git_commit_entry);
    app.git_status = c.cadex_label_new("") orelse return error.GtkFailed;
    c.cadex_label_ellipsize(app.git_status);
    c.cadex_box_append(page, app.git_status);
    app.git_list = c.cadex_listbox_new() orelse return error.GtkFailed;
    c.cadex_listbox_on_activated(app.git_list, gitRowActivated, app);
    c.cadex_listbox_on_keys(app.git_list, gitRowActivated, app);
    const scrolled = c.cadex_scrolled_new(app.git_list) orelse return error.GtkFailed;
    c.cadex_widget_expand(scrolled);
    c.cadex_box_append(page, scrolled);
    return page;
}

fn buildHistoryPage(app: *App) !*anyopaque {
    const page = c.cadex_box_new() orelse return error.GtkFailed;
    c.cadex_widget_add_class(page, "cadex-page");
    const head = c.cadex_box_new_h(4) orelse return error.GtkFailed;
    app.history_status = c.cadex_label_new("History") orelse return error.GtkFailed;
    c.cadex_label_ellipsize(app.history_status);
    c.cadex_widget_expand_h(app.history_status);
    c.cadex_box_append(head, app.history_status);
    c.cadex_box_append(head, c.cadex_button_new("Refresh", historyRefreshClicked, app) orelse return error.GtkFailed);
    c.cadex_box_append(head, c.cadex_button_new("More", historyMoreClicked, app) orelse return error.GtkFailed);
    c.cadex_box_append(page, head);
    app.history_list = c.cadex_listbox_new() orelse return error.GtkFailed;
    c.cadex_listbox_on_activated(app.history_list, historyRowActivated, app);
    c.cadex_listbox_on_keys(app.history_list, historyRowActivated, app);
    const scrolled = c.cadex_scrolled_new(app.history_list) orelse return error.GtkFailed;
    c.cadex_widget_expand(scrolled);
    c.cadex_box_append(page, scrolled);
    return page;
}

fn clearEntries(app: *App) void {
    for (app.files_entries.items) |entry| {
        app.gpa.free(entry.name);
        app.gpa.free(entry.path);
    }
    app.files_entries.clearRetainingCapacity();
}

fn addFilesRow(app: *App, name: []const u8, path: [:0]u8, directory: bool) void {
    const label = std.fmt.allocPrintSentinel(app.gpa, "{s}{s}{s}", .{
        if (directory) "▸ " else "  ",
        name,
        if (directory) "/" else "",
    }, 0) catch {
        app.gpa.free(path);
        return;
    };
    defer app.gpa.free(label);
    const name_copy = app.gpa.dupe(u8, name) catch {
        app.gpa.free(path);
        return;
    };
    app.files_entries.append(app.gpa, .{ .name = name_copy, .path = path, .directory = directory }) catch {
        app.gpa.free(name_copy);
        app.gpa.free(path);
        return;
    };
    c.cadex_listbox_append(app.files_list, label.ptr);
}

fn refreshFiles(app: *App) void {
    if (app.closing) return;
    clearEntries(app);
    c.cadex_listbox_clear(app.files_list);

    var listing: core.cadex_explorer_listing = std.mem.zeroes(core.cadex_explorer_listing);
    if (core.cadex_explorer_list(app.files_path.ptr, &listing) != core.CADEX_OK) {
        c.cadex_label_set(app.files_title, app.files_path.ptr);
        const empty = app.gpa.dupeZ(u8, "") catch return;
        addFilesRow(app, "(cannot read this folder)", empty, false);
        return;
    }
    defer core.cadex_explorer_listing_free(&listing);

    if (!std.mem.eql(u8, app.files_path, app.root)) {
        const parent = std.fs.path.dirname(app.files_path) orelse app.root;
        if (std.mem.startsWith(u8, parent, app.root)) {
            const parent_z = app.gpa.dupeZ(u8, parent) catch return;
            addFilesRow(app, "..", parent_z, true);
        }
    }

    if (listing.names == null) return;
    var i: usize = 0;
    while (i < listing.count) : (i += 1) {
        const entry = listing.entries[i];
        const name = listing.names[entry.name_offset..][0..entry.name_len];
        const full = std.fs.path.join(app.gpa, &.{ app.files_path, name }) catch continue;
        defer app.gpa.free(full);
        const full_z = app.gpa.dupeZ(u8, full) catch continue;
        const directory = entry.kind == core.CADEX_ENTRY_DIRECTORY or entry.link_to_directory;
        addFilesRow(app, name, full_z, directory);
    }

    var title_buf: [512]u8 = undefined;
    const relative = if (std.mem.startsWith(u8, app.files_path, app.root)) app.files_path[app.root.len..] else app.files_path;
    const base = std.fs.path.basename(app.root);
    const title = std.fmt.bufPrintZ(&title_buf, "{s}{s}", .{ base, relative }) catch app.files_path;
    c.cadex_label_set(app.files_title, title.ptr);
}

fn setFilesPath(app: *App, path: []const u8) void {
    const z = app.gpa.dupeZ(u8, path) catch return;
    app.gpa.free(app.files_path);
    app.files_path = z;
    refreshFiles(app);
}

fn filesRowActivated(index: c_int, user: ?*anyopaque) callconv(.c) void {
    const app: *App = @ptrCast(@alignCast(user.?));
    if (index < 0) return;
    const at: usize = @intCast(index);
    if (at >= app.files_entries.items.len) return;
    const entry = app.files_entries.items[at];
    if (entry.path.len == 0) return;
    if (entry.directory) {
        setFilesPath(app, entry.path);
        c.cadex_listbox_focus_first(app.files_list);
    } else {
        openDocument(app, entry.path, 0);
    }
}

fn filesUpClicked(user: ?*anyopaque) callconv(.c) void {
    const app: *App = @ptrCast(@alignCast(user.?));
    const parent = std.fs.path.dirname(app.files_path) orelse return;
    if (parent.len < app.root.len or !std.mem.startsWith(u8, parent, app.root)) return;
    setFilesPath(app, parent);
}

fn filesRefreshClicked(user: ?*anyopaque) callconv(.c) void {
    const app: *App = @ptrCast(@alignCast(user.?));
    refreshFiles(app);
}

fn newFileClicked(user: ?*anyopaque) callconv(.c) void {
    const app: *App = @ptrCast(@alignCast(user.?));
    promptOpen(app, false);
}

fn newFolderClicked(user: ?*anyopaque) callconv(.c) void {
    const app: *App = @ptrCast(@alignCast(user.?));
    promptOpen(app, true);
}

fn promptOpen(app: *App, directory: bool) void {
    app.prompt_dir = directory;
    if (app.prompt_window == null) createPrompt(app);
    const window = app.prompt_window orelse return;
    const entry = app.prompt_entry orelse return;
    c.cadex_entry_set_text(entry, "");
    c.cadex_entry_set_placeholder(entry, if (directory) "Folder name" else "File name");
    c.cadex_window_present(window, 0);
    c.cadex_widget_focus(entry);
}

fn createPrompt(app: *App) void {
    const window = c.cadex_window_new_dialog(app.window, "New", 420, 150) orelse return;
    c.cadex_window_hide_on_close(window);
    c.cadex_widget_on_escape(window, promptCancel, app);
    const box = c.cadex_box_new() orelse return;
    c.cadex_widget_add_class(box, "cadex-page");
    const entry = c.cadex_entry_new() orelse return;
    c.cadex_entry_activate(entry, promptCreate, app);
    c.cadex_entry_escape(entry, promptCancel, app);
    c.cadex_box_append(box, entry);
    const actions = c.cadex_box_new_h(6) orelse return;
    c.cadex_box_append(actions, c.cadex_button_new("Create", promptCreate, app) orelse return);
    c.cadex_box_append(actions, c.cadex_button_new("Cancel", promptCancel, app) orelse return);
    c.cadex_box_append(box, actions);
    c.cadex_window_child(window, box);
    app.prompt_window = window;
    app.prompt_entry = entry;
}

fn promptCreate(user: ?*anyopaque) callconv(.c) void {
    const app: *App = @ptrCast(@alignCast(user.?));
    const entry = app.prompt_entry orelse return;
    const raw = c.cadex_entry_text(entry);
    if (raw == null) return;
    const text = std.mem.span(@as([*:0]const u8, @ptrCast(raw)));
    const name = std.mem.trim(u8, text, " \t");
    if (name.len == 0 or std.mem.indexOfAny(u8, name, "/\\") != null) {
        showMessage(app, "Type a plain file or folder name");
        return;
    }
    const full = std.fs.path.join(app.gpa, &.{ app.files_path, name }) catch return;
    defer app.gpa.free(full);
    const z = app.gpa.dupeZ(u8, full) catch return;
    defer app.gpa.free(z);
    const status = if (app.prompt_dir)
        core.cadex_explorer_create_directory(z.ptr)
    else
        core.cadex_explorer_create_file(z.ptr);
    if (status != core.CADEX_OK) {
        showMessage(app, "Could not create it (the name may exist)");
        return;
    }
    if (app.prompt_window) |window| c.cadex_window_hide(window);
    refreshFiles(app);
    showMessage(app, if (app.prompt_dir) "Folder created" else "File created");
}

fn promptCancel(user: ?*anyopaque) callconv(.c) void {
    const app: *App = @ptrCast(@alignCast(user.?));
    if (app.prompt_window) |window| c.cadex_window_hide(window);
}

fn showMessage(app: *App, text: []const u8) void {
    var buf: [512]u8 = undefined;
    const z = std.fmt.bufPrintZ(&buf, "{s}", .{text}) catch return;
    c.cadex_label_set(app.message_label, z.ptr);
}

const token_dark = [18]u32{
    0x000000, 0x569cd6, 0xce9178, 0xb5cea8, 0x6a9955, 0xdcdcaa, 0x4ec9b0,
    0x4fc1ff, 0x9cdcfe, 0xd4d4d4, 0x808080, 0x9cdcfe, 0x569cd6, 0x9cdcfe,
    0xd7ba7d, 0x569cd6, 0x4fc1ff, 0xd7ba7d,
};

const token_light = [18]u32{
    0x000000, 0x0000ff, 0xa31515, 0x098658, 0x008000, 0x795e26, 0x267f99,
    0x0070c1, 0x001080, 0x383a42, 0x696c77, 0x001080, 0x800000, 0xe50000,
    0x811f3f, 0x0000ff, 0x0070c1, 0x795e26,
};

const token_tags = [18][*:0]const u8{
    "",
    "tok.keyword",
    "tok.string",
    "tok.number",
    "tok.comment",
    "tok.function",
    "tok.type",
    "tok.constant",
    "tok.property",
    "tok.operator",
    "tok.punctuation",
    "tok.variable",
    "tok.tag",
    "tok.attribute",
    "tok.escape",
    "tok.heading",
    "tok.link",
    "tok.emphasis",
};

fn tagName(kind: u8) [*:0]const u8 {
    if (kind >= token_tags.len) return "";
    return token_tags[kind];
}

fn setupDocTags(doc: *Doc) void {
    c.cadex_text_buffer_clear_tags(doc.buffer);
    const theme = themes[doc.app.theme_index];
    const table = if (theme.dark) token_dark else token_light;
    var kind: u8 = 1;
    while (kind < token_tags.len) : (kind += 1) {
        const bold = kind == 1 or kind == 6 or kind == 15;
        const italic = kind == 4 or kind == 17;
        const underline = kind == 16;
        c.cadex_text_buffer_add_tag(
            doc.buffer,
            token_tags[kind],
            table[kind],
            @intFromBool(bold),
            @intFromBool(italic),
            @intFromBool(underline),
        );
    }
    c.cadex_text_buffer_add_tag(doc.buffer, "diff.add", if (theme.dark) 0x4ec9b0 else 0x098658, 0, 0, 0);
    c.cadex_text_buffer_add_tag(doc.buffer, "diff.del", if (theme.dark) 0xf14c4c else 0xa31515, 0, 0, 0);
    c.cadex_text_buffer_add_tag(doc.buffer, "diff.hunk", if (theme.dark) 0x569cd6 else 0x0000ff, 1, 0, 0);
}

fn utf8Len(byte: u8) usize {
    return if (byte < 0x80) 1 else if (byte < 0xE0) 2 else if (byte < 0xF0) 3 else 4;
}

fn applyDocHighlight(doc: *Doc, text: []const u8) void {
    c.cadex_text_buffer_remove_all_tags(doc.buffer);
    if (doc.diff) {
        applyDiffTags(doc, text);
        return;
    }
    const editor = doc.editor orelse return;
    var spans: [*c]core.cadex_editor_span = null;
    var count: usize = 0;
    if (core.cadex_editor_highlights(editor, 0, @intCast(text.len), &spans, &count) != core.CADEX_OK) return;
    if (spans == null or count == 0) return;
    defer core.cadex_free(@ptrCast(spans));

    var byte_at: usize = 0;
    var char_at: usize = 0;
    var i: usize = 0;
    while (i < count) : (i += 1) {
        const span = spans[i];
        const start = @min(@as(usize, span.start), text.len);
        const end = @min(@as(usize, span.end), text.len);
        if (end <= start or end <= byte_at) continue;
        while (byte_at < start) {
            byte_at += utf8Len(text[byte_at]);
            char_at += 1;
        }
        const start_char = char_at;
        while (byte_at < end) {
            byte_at += utf8Len(text[byte_at]);
            char_at += 1;
        }
        c.cadex_text_buffer_apply_tag(doc.buffer, tagName(span.kind), @intCast(start_char), @intCast(char_at));
    }
}

fn applyDiffTags(doc: *Doc, text: []const u8) void {
    var line_start: usize = 0;
    var char_at: usize = 0;
    var byte_at: usize = 0;
    while (line_start <= text.len) {
        const line_end = std.mem.indexOfScalarPos(u8, text, line_start, '\n') orelse text.len;
        const line = text[line_start..line_end];
        const name: ?[*:0]const u8 = if (std.mem.startsWith(u8, line, "+++") or std.mem.startsWith(u8, line, "---"))
            null
        else if (std.mem.startsWith(u8, line, "+"))
            "diff.add"
        else if (std.mem.startsWith(u8, line, "-"))
            "diff.del"
        else if (std.mem.startsWith(u8, line, "@@"))
            "diff.hunk"
        else
            null;
        const start_char = char_at;
        while (byte_at < line_end) {
            byte_at += utf8Len(text[byte_at]);
            char_at += 1;
        }
        if (name) |tag| {
            c.cadex_text_buffer_apply_tag(doc.buffer, tag, @intCast(start_char), @intCast(char_at));
        }
        if (line_end >= text.len) break;
        byte_at += 1;
        char_at += 1;
        line_start = line_end + 1;
    }
}

fn updatePreview(doc: *Doc, text: []const u8) void {
    const label = doc.preview_label orelse return;
    var out: ?[*]u8 = null;
    var len: usize = 0;
    if (core.cadex_markdown_render(text.ptr, text.len, &out, &len) != core.CADEX_OK or out == null) return;
    defer core.cadex_free(@ptrCast(out.?));
    const markup = documents.markdown.toPango(doc.app.gpa, out.?[0..len]) catch return;
    defer doc.app.gpa.free(markup);
    const z = doc.app.gpa.dupeZ(u8, markup) catch return;
    defer doc.app.gpa.free(z);
    c.cadex_label_set_markup_safe(label, z.ptr);
}

fn openDocument(app: *App, path: [:0]const u8, line: usize) void {
    if (path.len == 0) return;
    for (app.spaces.items, 0..) |space, space_index| {
        for (space.tabs.items, 0..) |tab, tab_index| {
            const doc = tab.doc orelse continue;
            if (doc.virtual) continue;
            if (std.mem.eql(u8, doc.path, path)) {
                c.cadex_notebook_set_current(space.notebook, @intCast(tab_index));
                switchSpace(app, space_index);
                c.cadex_text_view_scroll_to_line(doc.view, @intCast(line));
                return;
            }
        }
    }

    var data: ?[*]u8 = null;
    var len: usize = 0;
    if (core.cadex_explorer_read_text(path.ptr, 0, &data, &len) != core.CADEX_OK or data == null) {
        showMessage(app, "Cannot open it (binary, too large or no access)");
        c.cadex_beep(app.window);
        return;
    }
    defer core.cadex_free(@ptrCast(data.?));
    const text = data.?[0..len];
    const title = std.fs.path.basename(path);
    const markdown = endsWithIgnoreCase(title, ".md") or endsWithIgnoreCase(title, ".markdown");
    _ = createDocTab(app, currentSpace(app), path, title, text, markdown, false, false, line) catch {
        showMessage(app, "Could not open the document");
    };
}

fn openTextTab(app: *App, title: []const u8, text: []const u8, diff: bool) void {
    _ = createDocTab(app, currentSpace(app), "", title, text, false, true, diff, 0) catch {
        showMessage(app, "Could not open the view");
    };
}

fn createDocTab(
    app: *App,
    space: *Space,
    path: [:0]const u8,
    title: []const u8,
    text: []const u8,
    markdown: bool,
    virtual: bool,
    diff: bool,
    line: usize,
) !*Doc {
    const gpa = app.gpa;
    const tab = try gpa.create(Tab);
    errdefer gpa.destroy(tab);
    const path_copy = try gpa.dupeZ(u8, path);
    errdefer gpa.free(path_copy);
    const title_copy = try gpa.dupeZ(u8, title);
    errdefer gpa.free(title_copy);

    const container = c.cadex_box_new() orelse return error.GtkFailed;
    const label_box = c.cadex_box_new_h(4) orelse return error.GtkFailed;
    const title_label = c.cadex_label_new(title_copy.ptr) orelse return error.GtkFailed;
    c.cadex_label_ellipsize(title_label);
    c.cadex_widget_set_size(title_label, 160, -1);
    c.cadex_widget_add_class(label_box, "cadex-tab-label");
    c.cadex_box_append(label_box, title_label);
    c.cadex_box_append(label_box, c.cadex_button_new("×", tabCloseClicked, tab) orelse return error.GtkFailed);
    tab.* = .{
        .app = app,
        .space = space,
        .container = container,
        .content = undefined,
        .label_box = label_box,
        .title_label = title_label,
        .kind = .document,
    };

    const doc = try gpa.create(Doc);
    doc.* = .{
        .app = app,
        .tab = tab,
        .path = path_copy,
        .title = title_copy,
        .view = undefined,
        .buffer = undefined,
        .scroll = undefined,
        .language = if (markdown) "Markdown" else "Text",
        .markdown = markdown,
        .virtual = virtual,
        .diff = diff,
    };
    tab.doc = doc;

    const header = c.cadex_box_new_h(6) orelse return error.GtkFailed;
    c.cadex_widget_add_class(header, "cadex-doc-header");
    const doc_title = c.cadex_label_new(title_copy.ptr) orelse return error.GtkFailed;
    c.cadex_label_ellipsize(doc_title);
    c.cadex_widget_expand_h(doc_title);
    c.cadex_box_append(header, doc_title);
    if (!virtual and markdown) {
        doc.save_button = c.cadex_button_new("Save", docSaveClicked, doc) orelse return error.GtkFailed;
        c.cadex_box_append(header, doc.save_button.?);
    }
    if (markdown) {
        doc.preview_button = c.cadex_button_new("Hide Preview", docPreviewClicked, doc) orelse return error.GtkFailed;
        c.cadex_box_append(header, doc.preview_button.?);
    }
    c.cadex_box_append(header, c.cadex_button_new("×", tabCloseClicked, tab) orelse return error.GtkFailed);
    c.cadex_box_append(container, header);

    const view = c.cadex_text_view_new() orelse return error.GtkFailed;
    doc.view = view;
    doc.buffer = c.cadex_text_view_buffer(view) orelse return error.GtkFailed;
    c.cadex_text_view_set_editable(view, @intFromBool(!virtual and markdown));
    c.cadex_text_view_set_wrap(view, @intFromBool(markdown));
    c.cadex_text_view_set_text(view, text.ptr, text.len);
    const scroller = c.cadex_scrolled_new(view) orelse return error.GtkFailed;
    doc.scroll = scroller;
    var content: *anyopaque = scroller;
    if (markdown) {
        const paned = c.cadex_paned_new(HORIZONTAL) orelse return error.GtkFailed;
        const preview_label = c.cadex_label_new("") orelse return error.GtkFailed;
        c.cadex_label_set_wrap(preview_label, 1);
        c.cadex_label_set_selectable(preview_label, 1);
        c.cadex_widget_set_valign(preview_label, 0);
        c.cadex_widget_add_class(preview_label, "cadex-preview");
        const preview_scroll = c.cadex_scrolled_new(preview_label) orelse return error.GtkFailed;
        doc.preview_label = preview_label;
        doc.preview_scroll = preview_scroll;
        c.cadex_paned_set_start(paned, scroller);
        c.cadex_paned_set_end(paned, preview_scroll);
        c.cadex_paned_set_position(paned, 520);
        content = paned;
    }
    tab.content = content;
    c.cadex_widget_expand(content);
    c.cadex_box_append(container, content);

    if (!virtual) {
        var handle: ?*core.cadex_editor_document = null;
        if (core.cadex_editor_open(path.ptr, text.ptr, text.len, core.CADEX_TEXT_UTF8, &handle) == core.CADEX_OK and handle != null) {
            doc.editor = handle;
            const language_ptr = core.cadex_editor_language(handle.?);
            if (language_ptr != null) {
                const language = std.mem.span(@as([*:0]const u8, @ptrCast(language_ptr)));
                if (language.len > 0 and language.len < doc.language_buf.len) {
                    @memcpy(doc.language_buf[0..language.len], language);
                    doc.language = doc.language_buf[0..language.len];
                }
            }
        }
    }
    if (!virtual and markdown) c.cadex_text_view_on_changed(view, docChanged, doc);

    setupDocTags(doc);
    applyDocHighlight(doc, text);
    if (markdown) updatePreview(doc, text);

    c.cadex_notebook_append(space.notebook, container, label_box);
    try space.tabs.append(gpa, tab);
    c.cadex_notebook_set_current(space.notebook, @intCast(space.tabs.items.len - 1));
    app.active_doc = doc;
    app.focused = null;
    c.cadex_widget_focus(view);
    updateTitle(app);
    updateStatus(app);
    if (line > 0) c.cadex_text_view_scroll_to_line(view, @intCast(line));
    return doc;
}

fn docChanged(user: ?*anyopaque) callconv(.c) void {
    const doc: *Doc = @ptrCast(@alignCast(user.?));
    if (!doc.alive) return;
    doc.dirty = true;
    updateDocLabel(doc);
    if (doc.markdown) _ = c.cadex_timeout(400, docRefresh, doc);
}

fn docRefresh(user: ?*anyopaque) callconv(.c) void {
    const doc: *Doc = @ptrCast(@alignCast(user.?));
    if (!doc.alive) return;
    var len: usize = 0;
    const raw = c.cadex_text_view_get_text(doc.view, &len) orelse return;
    defer c.cadex_gtk_free(@ptrCast(raw));
    const text = raw[0..len];

    if (doc.editor) |handle| {
        core.cadex_editor_close(handle);
        doc.editor = null;
    }
    var handle: ?*core.cadex_editor_document = null;
    if (core.cadex_editor_open(doc.path.ptr, text.ptr, text.len, core.CADEX_TEXT_UTF8, &handle) == core.CADEX_OK) {
        doc.editor = handle;
    }
    setupDocTags(doc);
    applyDocHighlight(doc, text);
    if (doc.markdown) updatePreview(doc, text);
}

fn updateDocLabel(doc: *Doc) void {
    var buf: [300]u8 = undefined;
    const label: [:0]const u8 = if (doc.dirty)
        (std.fmt.bufPrintZ(&buf, "{s} •", .{doc.title}) catch doc.title)
    else
        doc.title;
    c.cadex_label_set(doc.tab.title_label, label.ptr);
}

fn saveDoc(doc: *Doc) void {
    if (doc.virtual or doc.tab.closed) return;
    var len: usize = 0;
    const raw = c.cadex_text_view_get_text(doc.view, &len) orelse return;
    defer c.cadex_gtk_free(@ptrCast(raw));
    if (core.cadex_explorer_write_text(doc.path.ptr, raw, len) != core.CADEX_OK) {
        showMessage(doc.app, "Could not save the file");
        return;
    }
    doc.dirty = false;
    updateDocLabel(doc);
    showMessage(doc.app, "Saved");
    updateTitle(doc.app);
}

fn docSaveClicked(user: ?*anyopaque) callconv(.c) void {
    const doc: *Doc = @ptrCast(@alignCast(user.?));
    saveDoc(doc);
}

fn docPreviewClicked(user: ?*anyopaque) callconv(.c) void {
    const doc: *Doc = @ptrCast(@alignCast(user.?));
    togglePreview(doc);
}

fn togglePreview(doc: *Doc) void {
    const preview = doc.preview_scroll orelse return;
    doc.preview_visible = !doc.preview_visible;
    c.cadex_widget_visible(preview, @intFromBool(doc.preview_visible));
    if (doc.preview_button) |button| {
        c.cadex_button_set_text(button, if (doc.preview_visible) "Hide Preview" else "Show Preview");
    }
}

fn endsWithIgnoreCase(haystack: []const u8, needle: []const u8) bool {
    if (needle.len > haystack.len) return false;
    return std.ascii.eqlIgnoreCase(haystack[haystack.len - needle.len ..], needle);
}

fn clearSearchHits(app: *App, clear_ui: bool) void {
    if (clear_ui) c.cadex_listbox_clear(app.search_list);
    app.search_mutex.lock();
    for (app.search_hits.items) |hit| {
        app.gpa.free(hit.path);
        app.gpa.free(hit.text);
    }
    app.search_hits.clearRetainingCapacity();
    app.search_mutex.unlock();
}

fn searchChanged(user: ?*anyopaque) callconv(.c) void {
    const app: *App = @ptrCast(@alignCast(user.?));
    const raw = c.cadex_entry_text(app.search_entry);
    if (raw == null) return;
    const query = std.mem.span(@as([*:0]const u8, @ptrCast(raw)));
    if (app.search_mode == .files) {
        runFileSearch(app, query);
    } else {
        c.cadex_label_set(app.search_status, "Enter to search content");
    }
}

fn searchActivated(user: ?*anyopaque) callconv(.c) void {
    const app: *App = @ptrCast(@alignCast(user.?));
    if (app.search_mode == .content) {
        if (app.search_done and app.search_hits.items.len > 0) {
            searchRowActivated(0, app);
        } else {
            runContentSearch(app);
        }
    } else if (app.search_hits.items.len > 0) {
        searchRowActivated(0, app);
    } else {
        // No file name matched: the same Enter searches the content.
        app.search_mode = .content;
        runContentSearch(app);
    }
}

fn searchFilesClicked(user: ?*anyopaque) callconv(.c) void {
    const app: *App = @ptrCast(@alignCast(user.?));
    app.search_mode = .files;
    const raw = c.cadex_entry_text(app.search_entry);
    if (raw == null) return;
    runFileSearch(app, std.mem.span(@as([*:0]const u8, @ptrCast(raw))));
}

fn searchContentClicked(user: ?*anyopaque) callconv(.c) void {
    const app: *App = @ptrCast(@alignCast(user.?));
    app.search_mode = .content;
    runContentSearch(app);
}

fn runFileSearch(app: *App, query: []const u8) void {
    clearSearchHits(app, true);
    if (query.len == 0) {
        c.cadex_label_set(app.search_status, "Type to search files");
        return;
    }
    const index = app.file_search_index orelse {
        c.cadex_label_set(app.search_status, "No workspace index");
        return;
    };
    var result: core.cadex_search_files_result = std.mem.zeroes(core.cadex_search_files_result);
    if (core.cadex_search_files(index, @ptrCast(query.ptr), query.len, 50, &result) != core.CADEX_OK) {
        c.cadex_label_set(app.search_status, "Search failed");
        return;
    }
    defer core.cadex_search_files_result_free(&result);
    if (result.count == 0 or result.matches == null or result.paths == null) {
        c.cadex_label_set(app.search_status, "No files");
        return;
    }
    var i: usize = 0;
    while (i < result.count) : (i += 1) {
        const match = result.matches[i];
        const path = result.paths[match.path_offset..][0..match.path_len];
        const path_copy = app.gpa.dupe(u8, path) catch continue;
        const text_copy = app.gpa.dupe(u8, "") catch {
            app.gpa.free(path_copy);
            continue;
        };
        app.search_hits.append(app.gpa, .{ .path = path_copy, .line = 0, .text = text_copy }) catch {
            app.gpa.free(path_copy);
            app.gpa.free(text_copy);
            continue;
        };
        const label = app.gpa.dupeZ(u8, path) catch continue;
        defer app.gpa.free(label);
        c.cadex_listbox_append(app.search_list, label.ptr);
    }
    var buf: [128]u8 = undefined;
    const status = std.fmt.bufPrintZ(&buf, "{d} files · Enter for content", .{app.search_hits.items.len}) catch "Files";
    c.cadex_label_set(app.search_status, status.ptr);
}

fn runContentSearch(app: *App) void {
    if (app.search_content) |handle| {
        core.cadex_search_content_cancel(handle);
        app.search_content = null;
    }
    clearSearchHits(app, true);
    const raw = c.cadex_entry_text(app.search_entry);
    if (raw == null) return;
    const query = std.mem.span(@as([*:0]const u8, @ptrCast(raw)));
    if (query.len == 0) {
        c.cadex_label_set(app.search_status, "Type to search content");
        return;
    }
    app.search_done = false;
    app.search_truncated = false;
    app.search_files_searched = 0;
    c.cadex_label_set(app.search_status, "Searching…");

    var options = std.mem.zeroes(core.cadex_search_content_options);
    options.max_results = 500;
    var callbacks = core.cadex_search_content_callbacks{
        .context = app,
        .on_hits = onSearchHits,
        .on_done = onSearchDone,
    };
    var handle: ?*core.cadex_search_content = null;
    if (core.cadex_search_content_start(app.root.ptr, @ptrCast(query.ptr), query.len, &options, &callbacks, &handle) == core.CADEX_OK) {
        app.search_content = handle;
    } else {
        c.cadex_label_set(app.search_status, "Search failed");
    }
}

fn onSearchHits(context: ?*anyopaque, hits: [*c]const core.cadex_search_hit, count: usize) callconv(.c) void {
    const app: *App = @ptrCast(@alignCast(context orelse return));
    if (app.closing) return;
    app.search_mutex.lock();
    var i: usize = 0;
    while (i < count) : (i += 1) {
        const hit = hits[i];
        if (hit.path == null) continue;
        const path = std.mem.span(@as([*:0]const u8, @ptrCast(hit.path)));
        const path_copy = app.gpa.dupe(u8, path) catch continue;
        const source = if (hit.text == null) "" else hit.text[0..hit.text_len];
        const text_copy = app.gpa.dupe(u8, source) catch {
            app.gpa.free(path_copy);
            continue;
        };
        app.search_hits.append(app.gpa, .{ .path = path_copy, .line = hit.line, .text = text_copy }) catch {
            app.gpa.free(path_copy);
            app.gpa.free(text_copy);
        };
    }
    app.search_mutex.unlock();
    if (!app.search_pending.swap(true, .acq_rel)) c.cadex_idle(searchFlushIdle, app);
}

fn onSearchDone(context: ?*anyopaque, truncated: bool, files: u32) callconv(.c) void {
    const app: *App = @ptrCast(@alignCast(context orelse return));
    app.search_mutex.lock();
    app.search_done = true;
    app.search_truncated = truncated;
    app.search_files_searched = files;
    app.search_mutex.unlock();
    if (!app.search_pending.swap(true, .acq_rel)) c.cadex_idle(searchFlushIdle, app);
}

fn searchFlushIdle(user: ?*anyopaque) callconv(.c) void {
    const app: *App = @ptrCast(@alignCast(user.?));
    app.search_pending.store(false, .release);
    if (app.closing) return;

    c.cadex_listbox_clear(app.search_list);
    app.search_mutex.lock();
    for (app.search_hits.items) |hit| {
        const clean = app.gpa.dupe(u8, hit.text) catch continue;
        defer app.gpa.free(clean);
        for (clean) |*byte| {
            if (byte.* == '\n' or byte.* == '\r' or byte.* == '\t') byte.* = ' ';
        }
        const label = if (hit.line > 0)
            std.fmt.allocPrintSentinel(app.gpa, "{s}:{d}  {s}", .{ hit.path, hit.line, clean }, 0) catch continue
        else
            std.fmt.allocPrintSentinel(app.gpa, "{s}", .{hit.path}, 0) catch continue;
        defer app.gpa.free(label);
        c.cadex_listbox_append(app.search_list, label.ptr);
    }
    const count = app.search_hits.items.len;
    const done = app.search_done;
    const truncated = app.search_truncated;
    const files = app.search_files_searched;
    app.search_mutex.unlock();

    var buf: [160]u8 = undefined;
    const status = if (done)
        std.fmt.bufPrintZ(&buf, "{d} hits in {d} files{s}", .{ count, files, if (truncated) " (truncated)" else "" }) catch "Search"
    else
        std.fmt.bufPrintZ(&buf, "Searching… {d} hits", .{count}) catch "Searching…";
    c.cadex_label_set(app.search_status, status.ptr);
}

fn searchRowActivated(index: c_int, user: ?*anyopaque) callconv(.c) void {
    const app: *App = @ptrCast(@alignCast(user.?));
    if (index < 0) return;
    const at: usize = @intCast(index);
    var path_z: ?[:0]u8 = null;
    var line: u32 = 0;
    app.search_mutex.lock();
    if (at < app.search_hits.items.len) {
        const hit = app.search_hits.items[at];
        path_z = app.gpa.dupeZ(u8, hit.path) catch null;
        line = hit.line;
    }
    app.search_mutex.unlock();
    const path = path_z orelse return;
    defer app.gpa.free(path);
    const full = std.fs.path.join(app.gpa, &.{ app.root, path }) catch return;
    defer app.gpa.free(full);
    const full_z = app.gpa.dupeZ(u8, full) catch return;
    defer app.gpa.free(full_z);
    openDocument(app, full_z, if (line > 0) line - 1 else 0);
}

fn openSidebarPage(app: *App, name: [*:0]const u8) void {
    if (!app.settings.sidebar) {
        app.settings.sidebar = true;
        applySidebar(app);
        saveSettings(app);
    }
    c.cadex_stack_set(app.sidebar_stack, name);
    const page = std.mem.span(name);
    if (std.mem.eql(u8, page, "files")) {
        refreshFiles(app);
        c.cadex_listbox_focus_first(app.files_list);
    } else if (std.mem.eql(u8, page, "search")) {
        c.cadex_widget_focus(app.search_entry);
    } else if (std.mem.eql(u8, page, "git")) {
        refreshGit(app);
        c.cadex_listbox_focus_first(app.git_list);
    } else if (std.mem.eql(u8, page, "history")) {
        if (!app.history_loaded) loadHistory(app, false);
        c.cadex_listbox_focus_first(app.history_list);
    }
}

fn cmdSidebarSearch(app: *App) void {
    openSidebarPage(app, "search");
    app.search_mode = .files;
    c.cadex_entry_select_all(app.search_entry);
    c.cadex_widget_focus(app.search_entry);
}

fn refreshGit(app: *App) void {
    if (app.closing) return;
    if (app.git_status_data) |status| {
        status.deinit(app.gpa);
        app.git_status_data = null;
    }
    if (app.git_repo) |repo| {
        app.gpa.free(repo);
        app.git_repo = null;
    }
    app.git_selected = null;
    c.cadex_listbox_clear(app.git_list);

    if (!core.cadex_git_available()) {
        c.cadex_label_set(app.git_branch, "git is not installed");
        c.cadex_label_set(app.git_status, "");
        return;
    }
    var root_out: ?[*]u8 = null;
    var root_len: usize = 0;
    if (core.cadex_git_root(app.root.ptr, &root_out, &root_len) != core.CADEX_OK or root_out == null) {
        c.cadex_label_set(app.git_branch, "No git repository");
        c.cadex_label_set(app.git_status, "");
        return;
    }
    const repo = app.gpa.dupeZ(u8, root_out.?[0..root_len]) catch {
        core.cadex_free(@ptrCast(root_out.?));
        return;
    };
    core.cadex_free(@ptrCast(root_out.?));
    app.git_repo = repo;

    var out: ?[*]u8 = null;
    var len: usize = 0;
    if (core.cadex_git_status(repo.ptr, &out, &len) == core.CADEX_OK and out != null) {
        defer core.cadex_free(@ptrCast(out.?));
        app.git_status_data = documents.git.parseStatus(app.gpa, out.?[0..len]) catch null;
    }
    const status = app.git_status_data orelse {
        c.cadex_label_set(app.git_branch, "git status failed");
        c.cadex_label_set(app.git_status, "");
        return;
    };

    var branch_buf: [200]u8 = undefined;
    const branch = std.fmt.bufPrintZ(&branch_buf, "{s}  ↑{d} ↓{d}", .{
        if (status.branch.len == 0) "(detached)" else status.branch,
        status.ahead,
        status.behind,
    }) catch "Git";
    c.cadex_label_set(app.git_branch, branch.ptr);

    var status_buf: [128]u8 = undefined;
    const status_text = if (status.files.len == 0)
        "Clean"
    else
        std.fmt.bufPrintZ(&status_buf, "{d} change(s)", .{status.files.len}) catch "Changes";
    c.cadex_label_set(app.git_status, status_text.ptr);

    for (status.files) |file| {
        const label = std.fmt.allocPrintSentinel(app.gpa, "{c}{c} {s}{s}{s}", .{
            file.x,
            file.y,
            file.path,
            if (file.orig.len > 0) " ← " else "",
            file.orig,
        }, 0) catch continue;
        defer app.gpa.free(label);
        c.cadex_listbox_append(app.git_list, label.ptr);
    }
}

fn gitRowActivated(index: c_int, user: ?*anyopaque) callconv(.c) void {
    const app: *App = @ptrCast(@alignCast(user.?));
    if (index < 0) return;
    app.git_selected = @intCast(index);
    openGitDiff(app, @intCast(index));
}

fn openGitDiff(app: *App, index: usize) void {
    const repo = app.git_repo orelse return;
    const status = app.git_status_data orelse return;
    if (index >= status.files.len) return;
    const file = status.files[index];
    const path_z = app.gpa.dupeZ(u8, file.path) catch return;
    defer app.gpa.free(path_z);
    const orig_z: ?[:0]u8 = if (file.orig.len > 0) app.gpa.dupeZ(u8, file.orig) catch null else null;
    defer if (orig_z) |orig| app.gpa.free(orig);
    const staged = status.staged(index);

    var title_buf: [300]u8 = undefined;
    const title = std.fmt.bufPrint(&title_buf, "diff: {s}", .{file.path}) catch "diff";

    var sides = std.mem.zeroes(core.cadex_git_diff_sides);
    const rc = core.cadex_git_diff(repo.ptr, path_z.ptr, if (orig_z) |orig| orig.ptr else null, staged, &sides);
    if (rc == core.CADEX_OK) {
        defer core.cadex_git_diff_free(&sides);
        if (sides.binary) {
            openTextTab(app, title, "(binary file)", true);
            return;
        }
        if (sides.too_large) {
            openTextTab(app, title, "(too large to diff)", true);
            return;
        }
        if (sides.patch != null and sides.patch_len > 0) {
            openTextTab(app, title, sides.patch[0..sides.patch_len], true);
            return;
        }
    }
    if (!staged) {
        openUntracked(app, path_z, title);
        return;
    }
    openTextTab(app, title, "(no diff)", true);
}

fn openUntracked(app: *App, path_z: [:0]const u8, title: []const u8) void {
    var data: ?[*]u8 = null;
    var len: usize = 0;
    if (core.cadex_explorer_read_text(path_z.ptr, 0, &data, &len) != core.CADEX_OK) {
        openTextTab(app, title, "(new file)", true);
        return;
    }
    defer if (data) |ptr| core.cadex_free(@ptrCast(ptr));
    var out: std.ArrayList(u8) = .empty;
    defer out.deinit(app.gpa);
    const header = std.fmt.allocPrint(app.gpa, "--- /dev/null\n+++ b/{s}\n", .{path_z}) catch return;
    defer app.gpa.free(header);
    out.appendSlice(app.gpa, header) catch return;
    const body = if (data) |ptr| ptr[0..len] else "";
    var lines = std.mem.splitScalar(u8, body, '\n');
    while (lines.next()) |line| {
        out.append(app.gpa, '+') catch return;
        out.appendSlice(app.gpa, line) catch return;
        out.append(app.gpa, '\n') catch return;
    }
    openTextTab(app, title, out.items, true);
}

fn addGitPath(app: *App, path: []const u8, paths: *std.ArrayList([:0]u8), pointers: *std.ArrayList([*c]const u8)) void {
    const z = app.gpa.dupeZ(u8, path) catch return;
    paths.append(app.gpa, z) catch {
        app.gpa.free(z);
        return;
    };
    pointers.append(app.gpa, z.ptr) catch {};
}

const GitPathList = struct {
    paths: std.ArrayList([:0]u8),
    pointers: std.ArrayList([*c]const u8),
};

fn collectGitPaths(app: *App, only_selected: bool) GitPathList {
    var result: GitPathList = .{
        .paths = std.ArrayList([:0]u8).empty,
        .pointers = std.ArrayList([*c]const u8).empty,
    };
    const status = app.git_status_data orelse return result;
    if (only_selected) {
        if (app.git_selected) |index| {
            if (index < status.files.len) addGitPath(app, status.files[index].path, &result.paths, &result.pointers);
        }
    } else {
        for (status.files) |file| addGitPath(app, file.path, &result.paths, &result.pointers);
    }
    return result;
}

fn freeGitPaths(app: *App, paths: *std.ArrayList([:0]u8), pointers: *std.ArrayList([*c]const u8)) void {
    for (paths.items) |z| app.gpa.free(z);
    paths.deinit(app.gpa);
    pointers.deinit(app.gpa);
}

fn finishGit(app: *App, status: core.cadex_status, message_ptr: ?[*]u8, message_len: usize, ok_text: []const u8) void {
    if (message_ptr) |message| {
        defer core.cadex_free(@ptrCast(message));
        if (message_len > 0) {
            showMessage(app, std.mem.sliceTo(message[0..message_len], '\n'));
        } else {
            showMessage(app, ok_text);
        }
    } else if (status == core.CADEX_OK) {
        showMessage(app, ok_text);
    }
    refreshGit(app);
    loadHistory(app, false);
}

fn gitStageClicked(user: ?*anyopaque) callconv(.c) void {
    const app: *App = @ptrCast(@alignCast(user.?));
    const repo = app.git_repo orelse return;
    var collected = collectGitPaths(app, true);
    defer freeGitPaths(app, &collected.paths, &collected.pointers);
    if (collected.pointers.items.len == 0) {
        showMessage(app, "Select a file first");
        return;
    }
    var message: ?[*]u8 = null;
    var len: usize = 0;
    const status = core.cadex_git_stage(repo.ptr, @ptrCast(collected.pointers.items.ptr), collected.pointers.items.len, &message, &len);
    finishGit(app, status, message, len, "Staged");
}

fn gitUnstageClicked(user: ?*anyopaque) callconv(.c) void {
    const app: *App = @ptrCast(@alignCast(user.?));
    const repo = app.git_repo orelse return;
    var collected = collectGitPaths(app, app.git_selected != null);
    defer freeGitPaths(app, &collected.paths, &collected.pointers);
    if (collected.pointers.items.len == 0) {
        showMessage(app, "Select a file first");
        return;
    }
    var message: ?[*]u8 = null;
    var len: usize = 0;
    const status = core.cadex_git_unstage(repo.ptr, @ptrCast(collected.pointers.items.ptr), collected.pointers.items.len, &message, &len);
    finishGit(app, status, message, len, "Unstaged");
}

fn gitDiscardClicked(user: ?*anyopaque) callconv(.c) void {
    const app: *App = @ptrCast(@alignCast(user.?));
    const repo = app.git_repo orelse return;
    const selected = app.git_selected orelse {
        showMessage(app, "Select a file first");
        return;
    };
    var collected = collectGitPaths(app, true);
    defer freeGitPaths(app, &collected.paths, &collected.pointers);
    if (collected.pointers.items.len == 0) return;
    _ = selected;
    var message: ?[*]u8 = null;
    var len: usize = 0;
    const status = core.cadex_git_discard(repo.ptr, @ptrCast(collected.pointers.items.ptr), collected.pointers.items.len, &message, &len);
    finishGit(app, status, message, len, "Discarded");
}

fn gitCommitClicked(user: ?*anyopaque) callconv(.c) void {
    const app: *App = @ptrCast(@alignCast(user.?));
    const repo = app.git_repo orelse return;
    const raw = c.cadex_entry_text(app.git_commit_entry);
    if (raw == null) return;
    const text = std.mem.span(@as([*:0]const u8, @ptrCast(raw)));
    if (std.mem.trim(u8, text, " \t\n").len == 0) {
        showMessage(app, "Type a commit message");
        return;
    }
    const z = app.gpa.dupeZ(u8, text) catch return;
    defer app.gpa.free(z);
    var message: ?[*]u8 = null;
    var len: usize = 0;
    const status = core.cadex_git_commit(repo.ptr, z.ptr, true, &message, &len);
    if (status == core.CADEX_OK) c.cadex_entry_set_text(app.git_commit_entry, "");
    finishGit(app, status, message, len, "Committed");
}

fn gitPushClicked(user: ?*anyopaque) callconv(.c) void {
    const app: *App = @ptrCast(@alignCast(user.?));
    const repo = app.git_repo orelse return;
    var message: ?[*]u8 = null;
    var len: usize = 0;
    const status = core.cadex_git_push(repo.ptr, null, &message, &len);
    finishGit(app, status, message, len, "Pushed");
}

fn gitPullClicked(user: ?*anyopaque) callconv(.c) void {
    const app: *App = @ptrCast(@alignCast(user.?));
    const repo = app.git_repo orelse return;
    var message: ?[*]u8 = null;
    var len: usize = 0;
    const status = core.cadex_git_pull(repo.ptr, &message, &len);
    finishGit(app, status, message, len, "Pulled");
}

fn gitFetchClicked(user: ?*anyopaque) callconv(.c) void {
    const app: *App = @ptrCast(@alignCast(user.?));
    const repo = app.git_repo orelse return;
    var message: ?[*]u8 = null;
    var len: usize = 0;
    const status = core.cadex_git_fetch(repo.ptr, &message, &len);
    finishGit(app, status, message, len, "Fetched");
}

fn gitRefreshClicked(user: ?*anyopaque) callconv(.c) void {
    const app: *App = @ptrCast(@alignCast(user.?));
    refreshGit(app);
}

fn clearHistory(app: *App) void {
    for (app.history_commits.items) |record| documents.git.freeCommit(app.gpa, record);
    app.history_commits.clearRetainingCapacity();
    c.cadex_listbox_clear(app.history_list);
    if (app.history_log) |log| {
        core.cadex_history_close(log);
        app.history_log = null;
    }
    app.history_has_more = true;
    app.history_loaded = false;
}

fn loadHistory(app: *App, more: bool) void {
    if (app.closing) return;
    if (!more or app.history_log == null) {
        clearHistory(app);
        const repo = app.git_repo orelse {
            c.cadex_label_set(app.history_status, "No git repository");
            return;
        };
        var log: ?*core.cadex_history = null;
        if (core.cadex_history_open(repo.ptr, "", true, &log) != core.CADEX_OK or log == null) {
            c.cadex_label_set(app.history_status, "No history");
            return;
        }
        app.history_log = log;
        app.history_has_more = true;
    }
    const log = app.history_log orelse return;
    if (!app.history_has_more) {
        c.cadex_label_set(app.history_status, "End of history");
        return;
    }
    var out: ?[*]u8 = null;
    var len: usize = 0;
    if (core.cadex_history_next(log, 40, &out, &len) != core.CADEX_OK or out == null) {
        app.history_has_more = false;
        c.cadex_label_set(app.history_status, "End of history");
        return;
    }
    defer core.cadex_free(@ptrCast(out.?));
    const commits = documents.git.parseLog(app.gpa, out.?[0..len]) catch return;
    if (commits.len == 0) {
        documents.git.freeLog(app.gpa, commits);
        app.history_has_more = false;
    } else {
        for (commits) |record| {
            const short = record.sha[0..@min(record.sha.len, 8)];
            const label = std.fmt.allocPrintSentinel(app.gpa, "{s}  {s} — {s}", .{ short, record.subject, record.author }, 0) catch {
                documents.git.freeCommit(app.gpa, record);
                continue;
            };
            defer app.gpa.free(label);
            c.cadex_listbox_append(app.history_list, label.ptr);
            app.history_commits.append(app.gpa, record) catch documents.git.freeCommit(app.gpa, record);
        }
        app.gpa.free(commits);
    }
    app.history_loaded = true;
    var buf: [128]u8 = undefined;
    const status = std.fmt.bufPrintZ(&buf, "{d} commit(s){s}", .{
        app.history_commits.items.len,
        if (app.history_has_more) " · More" else " · end",
    }) catch "History";
    c.cadex_label_set(app.history_status, status.ptr);
}

fn historyRowActivated(index: c_int, user: ?*anyopaque) callconv(.c) void {
    const app: *App = @ptrCast(@alignCast(user.?));
    if (index < 0) return;
    const at: usize = @intCast(index);
    if (at >= app.history_commits.items.len) return;
    showCommit(app, at);
}

fn appendFormatted(out: *std.ArrayList(u8), allocator: std.mem.Allocator, comptime format: []const u8, args: anytype) void {
    const text = std.fmt.allocPrint(allocator, format, args) catch return;
    defer allocator.free(text);
    out.appendSlice(allocator, text) catch {};
}

fn showCommit(app: *App, index: usize) void {
    const repo = app.git_repo orelse return;
    const record = app.history_commits.items[index];
    var out: ?[*]u8 = null;
    var len: usize = 0;
    const sha_z = app.gpa.dupeZ(u8, record.sha) catch return;
    defer app.gpa.free(sha_z);
    if (core.cadex_history_details(repo.ptr, sha_z.ptr, &out, &len) != core.CADEX_OK or out == null) {
        showMessage(app, "Could not load the commit");
        return;
    }
    defer core.cadex_free(@ptrCast(out.?));
    var details = documents.git.parseDetails(app.gpa, out.?[0..len]) catch {
        showMessage(app, "Could not parse the commit");
        return;
    };
    defer details.deinit(app.gpa);

    var text: std.ArrayList(u8) = .empty;
    defer text.deinit(app.gpa);
    appendFormatted(&text, app.gpa, "commit {s}\nAuthor: {s} <{s}>\nDate: {d}\n\n", .{
        record.sha, record.author, record.email, record.time,
    });
    appendFormatted(&text, app.gpa, "{s}\n\nFiles:\n", .{details.message});
    for (details.changes) |change| {
        appendFormatted(&text, app.gpa, "  {s} +{s} -{s}  {s}\n", .{
            change.letter, change.added, change.removed, change.path,
        });
    }
    var title_buf: [128]u8 = undefined;
    const title = std.fmt.bufPrint(&title_buf, "commit {s}", .{record.sha[0..@min(record.sha.len, 8)]}) catch "commit";
    openTextTab(app, title, text.items, false);
}

fn historyRefreshClicked(user: ?*anyopaque) callconv(.c) void {
    const app: *App = @ptrCast(@alignCast(user.?));
    loadHistory(app, false);
}

fn historyMoreClicked(user: ?*anyopaque) callconv(.c) void {
    const app: *App = @ptrCast(@alignCast(user.?));
    loadHistory(app, true);
}

fn closeCb(user: ?*anyopaque) callconv(.c) c_int {
    const app: *App = @ptrCast(@alignCast(user.?));
    app.closing = true;
    if (app.files_watcher) |watcher| {
        core.cadex_explorer_watch_stop(watcher);
        app.files_watcher = null;
    }
    if (app.search_content) |handle| {
        core.cadex_search_content_cancel(handle);
        app.search_content = null;
    }
    if (app.file_search_index) |index| {
        core.cadex_search_index_close(index);
        app.file_search_index = null;
    }
    clearSearchHits(app, false);
    clearEntries(app);
    if (app.git_status_data) |status| {
        status.deinit(app.gpa);
        app.git_status_data = null;
    }
    if (app.git_repo) |repo| {
        app.gpa.free(repo);
        app.git_repo = null;
    }
    for (app.history_commits.items) |record| documents.git.freeCommit(app.gpa, record);
    app.history_commits.clearRetainingCapacity();
    if (app.history_log) |log| {
        core.cadex_history_close(log);
        app.history_log = null;
    }
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
            if (tab.doc) |doc| {
                doc.alive = false;
                if (doc.editor) |handle| {
                    core.cadex_editor_close(handle);
                    doc.editor = null;
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
        activateTab(app, space.tabs.items[@min(page, space.tabs.items.len - 1)]);
    } else {
        app.active_doc = null;
        app.focused = null;
    }
    updateTitle(app);
    updateStatus(app);
}

fn activateTab(app: *App, tab: *Tab) void {
    if (tab.kind == .document) {
        const doc = tab.doc orelse return;
        app.active_doc = doc;
        app.focused = null;
        c.cadex_widget_focus(doc.view);
    } else {
        app.active_doc = null;
        app.focused = tab.panes[0];
        if (tab.panes[0]) |pane| c.cadex_widget_focus(pane.area);
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
    activateTab(app, space.tabs.items[at]);
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
    app.active_doc = null;
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
    pane.term = try terminal.Terminal.open(gpa, 80, 24, app.root, .{
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
    if (app.active_doc) |doc| {
        c.cadex_window_title(app.window, doc.title.ptr);
        var buf: [320]u8 = undefined;
        const text = std.fmt.bufPrintZ(&buf, "{s} — {s}{s}", .{
            doc.title,
            doc.language,
            if (doc.dirty) " •" else "",
        }) catch doc.title;
        c.cadex_label_set(app.header_title, text.ptr);
        return;
    }
    const pane = app.focused orelse return;
    if (pane.closed) return;
    c.cadex_window_title(app.window, pane.title.ptr);
    c.cadex_label_set(app.header_title, pane.title.ptr);
}

fn updateStatus(app: *App) void {
    if (app.closing) return;
    if (app.active_doc) |doc| {
        const shown = if (doc.path.len > 0) doc.path else doc.title;
        var buf: [512]u8 = undefined;
        const z = std.fmt.bufPrintZ(&buf, "{s}", .{shown}) catch doc.title;
        c.cadex_label_set(app.cwd_label, z.ptr);
    } else if (app.focused) |pane| {
        if (pane.term) |term| {
            if (term.copyWorkingDirectory(app.gpa)) |cwd_text| {
                defer app.gpa.free(cwd_text);
                if (app.gpa.dupeZ(u8, cwd_text) catch null) |z| {
                    defer app.gpa.free(z);
                    c.cadex_label_set(app.cwd_label, z.ptr);
                }
            }
        }
    }
    const count = c.cadex_notebook_count(currentSpace(app).notebook);
    var buf: [160]u8 = undefined;
    const branch = if (app.git_status_data) |status| status.branch else "";
    const text = std.fmt.bufPrintZ(&buf, "{d} tab(s){s}{s}", .{
        count,
        if (branch.len > 0) " · " else "",
        branch,
    }) catch return;
    c.cadex_label_set(app.tabs_label, text.ptr);
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
    applyTheme(app);
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
            ".cadex-term {{ background-color: #{x:0>6}; }}\n" ++
            ".cadex-page {{ padding: 6px; }}\n" ++
            ".cadex-doc-header {{ background-color: #{x:0>6}; color: #{x:0>6}; padding: 4px; }}\n" ++
            ".cadex-preview {{ background-color: #{x:0>6}; color: #{x:0>6}; padding: 12px; }}\n" ++
            "textview {{ background-color: #{x:0>6}; color: #{x:0>6}; font-size: {d}px; }}\n" ++
            "textview text {{ background-color: #{x:0>6}; color: #{x:0>6}; font-size: {d}px; }}\n",
        .{
            theme.background, theme.foreground,
            theme.panel,      theme.foreground,
            theme.panel,      theme.foreground,
            theme.panel,      theme.foreground,
            theme.panel,      theme.foreground,
            theme.panel,      theme.foreground,
            theme.background,
            theme.panel,      theme.foreground,
            theme.background, theme.foreground,
            theme.background, theme.foreground, app.settings.font_size,
            theme.background, theme.foreground, app.settings.font_size,
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
    reapplyDocs(app);
}

fn reapplyDocs(app: *App) void {
    for (app.spaces.items) |space| {
        for (space.tabs.items) |tab| {
            const doc = tab.doc orelse continue;
            if (!doc.alive) continue;
            var len: usize = 0;
            const raw = c.cadex_text_view_get_text(doc.view, &len) orelse continue;
            defer c.cadex_gtk_free(@ptrCast(raw));
            setupDocTags(doc);
            applyDocHighlight(doc, raw[0..len]);
            if (doc.markdown) updatePreview(doc, raw[0..len]);
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

fn windowKey(keyval: c_uint, keycode: c_uint, state: c_uint, user: ?*anyopaque) callconv(.c) c_int {
    _ = keycode;
    const app: *App = @ptrCast(@alignCast(user.?));
    return @intFromBool(handleShortcut(app, keyval, state));
}

fn key(keyval: c_uint, keycode: c_uint, state: c_uint, user: ?*anyopaque) callconv(.c) c_int {
    _ = keycode;
    const pane: *Pane = @ptrCast(@alignCast(user.?));
    const app = pane.app;
    if (pane.closed) return 0;
    app.active_doc = null;
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
        'c', 'C' => if (alt) "git.commit-message" else "terminal.copy",
        'v', 'V' => "terminal.paste",
        'a', 'A' => "terminal.select-all",
        'b', 'B' => "view.toggle-sidebar",
        'e', 'E' => "sidebar.files",
        'p', 'P' => "sidebar.search",
        'g', 'G' => "sidebar.git",
        'h', 'H' => "sidebar.history",
        's', 'S' => "document.save",
        'm', 'M' => "document.preview",
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
    app.active_doc = null;
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
    if (tab.doc) |doc| {
        doc.alive = false;
        if (doc.editor) |handle| {
            core.cadex_editor_close(handle);
            doc.editor = null;
        }
        if (app.active_doc == doc) app.active_doc = null;
        app.gpa.free(doc.path);
        app.gpa.free(doc.title);
        app.gpa.destroy(doc);
        tab.doc = null;
    }
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
        activateTab(app, tab.space.tabs.items[@min(page, tab.space.tabs.items.len - 1)]);
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
    if (app.active_doc) |doc| {
        closeTab(doc.tab);
        return;
    }
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
    if (app.active_doc != null) {
        openSidebarPage(app, "search");
        app.search_mode = .content;
        c.cadex_entry_select_all(app.search_entry);
        c.cadex_widget_focus(app.search_entry);
        return;
    }
    toggleFind(app);
}

fn cmdCopy(app: *App) void {
    if (app.active_doc) |doc| {
        c.cadex_text_view_copy(doc.view);
        return;
    }
    const pane = app.focused orelse return;
    const term = pane.term orelse return;
    const text = term.copySelection(app.gpa) orelse return;
    defer app.gpa.free(text);
    const z = app.gpa.dupeZ(u8, text) catch return;
    defer app.gpa.free(z);
    c.cadex_clipboard_set(pane.area, z.ptr);
}

fn cmdPaste(app: *App) void {
    if (app.active_doc) |doc| {
        c.cadex_text_view_paste(doc.view);
        return;
    }
    const pane = app.focused orelse return;
    c.cadex_clipboard_get(pane.area, clipboardText, pane);
}

fn cmdSelectAll(app: *App) void {
    if (app.active_doc) |doc| {
        c.cadex_text_view_select_all(doc.view);
        return;
    }
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
    openSidebarPage(app, "files");
}

fn cmdSidebarGit(app: *App) void {
    openSidebarPage(app, "git");
}

fn cmdSidebarHistory(app: *App) void {
    openSidebarPage(app, "history");
}

fn cmdSaveDocument(app: *App) void {
    if (app.active_doc) |doc| {
        saveDoc(doc);
    } else {
        showMessage(app, "Open a document first");
    }
}

fn cmdTogglePreview(app: *App) void {
    if (app.active_doc) |doc| togglePreview(doc);
}

fn cmdNewFile(app: *App) void {
    promptOpen(app, false);
}

fn cmdNewFolder(app: *App) void {
    promptOpen(app, true);
}

fn cmdRefreshExplorer(app: *App) void {
    refreshFiles(app);
}

fn cmdGitCommitMessage(app: *App) void {
    openSidebarPage(app, "git");
    c.cadex_widget_focus(app.git_commit_entry);
    showMessage(app, "Type a commit message and press Enter");
}

fn cmdRefreshGit(app: *App) void {
    refreshGit(app);
}

fn cmdRefreshHistory(app: *App) void {
    loadHistory(app, false);
}

fn sidebarClicked(user: ?*anyopaque) callconv(.c) void {
    const app: *App = @ptrCast(@alignCast(user.?));
    cmdToggleSidebar(app);
}

fn sidebarFilesClicked(user: ?*anyopaque) callconv(.c) void {
    const app: *App = @ptrCast(@alignCast(user.?));
    cmdSidebarFiles(app);
}

fn sidebarSearchClicked(user: ?*anyopaque) callconv(.c) void {
    const app: *App = @ptrCast(@alignCast(user.?));
    cmdSidebarSearch(app);
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
    if (app.active_doc) |doc| {
        c.cadex_widget_focus(doc.view);
    } else if (app.focused) |pane| {
        c.cadex_widget_focus(pane.area);
    }
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
    const close_button = c.cadex_button_new("Close", settingsClose, app) orelse return;
    c.cadex_box_append(box, close_button);
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
    c.cadex_widget_expand_h(label);
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
