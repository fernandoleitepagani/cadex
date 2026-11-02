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

const Interface = struct {
    /// Title bar, the gaps between panels and the status bar.
    chrome: u32,
    /// The rounded sidebar and content panels.
    panel: u32,
    panel_border: u32,
    tab_active: u32,
    field: u32,
    text: u32,
    secondary_text: u32,
    accent: u32,
};

const Theme = struct {
    name: []const u8,
    dark: bool,
    background: u32,
    foreground: u32,
    cursor: u32,
    panel: u32,
    ansi: [16]u32,
    /// The interface palette (macOS Cadex has one per theme). When absent the
    /// palette is derived from the terminal colors.
    interface: ?Interface = null,
};

const themes = [_]Theme{
    .{
        .name = "Caffeine",
        .dark = true,
        .background = 0x111111,
        .foreground = 0xeeeeee,
        .cursor = 0xffe0c2,
        .panel = 0x111111,
        .ansi = .{ 0x2c2c2c, 0xe54d2e, 0x87ba88, 0xffe0c1, 0x84aee3, 0xc897ca, 0x5dbcc1, 0xc6c6c6, 0xb4b4b4, 0xfe6545, 0x9dd19e, 0xfdebd9, 0x9ac4fb, 0xdfade1, 0x74d3d8, 0xeeeeee },
        .interface = .{
            .chrome = 0x222222,
            .panel = 0x111111,
            .panel_border = 0x201e18,
            .tab_active = 0x534c45,
            .field = 0x2e2e2e,
            .text = 0xeeeeee,
            .secondary_text = 0xb4b4b4,
            .accent = 0xffe0c2,
        },
    },
    .{
        .name = "Caffeine Light",
        .dark = false,
        .background = 0xf9f9f9,
        .foreground = 0x202020,
        .cursor = 0x644a40,
        .panel = 0xf9f9f9,
        .ansi = .{ 0x202020, 0xe54d2e, 0x467748, 0xa48d6e, 0x446b9c, 0x835685, 0x1b777b, 0xc3c3c3, 0x646464, 0xcc3412, 0x326335, 0x8e785a, 0x315786, 0x6e4270, 0x0d6165, 0xe3e3e3 },
        .interface = .{
            .chrome = 0xefefef,
            .panel = 0xf9f9f9,
            .panel_border = 0xd8d8d8,
            .tab_active = 0xd0cbc8,
            .field = 0xe3e3e3,
            .text = 0x202020,
            .secondary_text = 0x646464,
            .accent = 0x644a40,
        },
    },
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
    .{
        .name = "Nord",
        .dark = true,
        .background = 0x2e3440,
        .foreground = 0xd8dee9,
        .cursor = 0xd8dee9,
        .panel = 0x3b4252,
        .ansi = .{ 0x3b4252, 0xbf616a, 0xa3be8c, 0xebcb8b, 0x81a1c1, 0xb48ead, 0x88c0d0, 0xe5e9f0, 0x4c566a, 0xbf616a, 0xa3be8c, 0xebcb8b, 0x81a1c1, 0xb48ead, 0x8fbcbb, 0xeceff4 },
    },
    .{
        .name = "Dracula",
        .dark = true,
        .background = 0x282a36,
        .foreground = 0xf8f8f2,
        .cursor = 0xf8f8f2,
        .panel = 0x44475a,
        .ansi = .{ 0x21222c, 0xff5555, 0x50fa7b, 0xf1fa8c, 0xbd93f9, 0xff79c6, 0x8be9fd, 0xf8f8f2, 0x6272a4, 0xff6e6e, 0x69ff94, 0xffffa5, 0xd6acff, 0xff92df, 0xa4ffff, 0xffffff },
    },
    .{
        .name = "Gruvbox Dark",
        .dark = true,
        .background = 0x282828,
        .foreground = 0xebdbb2,
        .cursor = 0xebdbb2,
        .panel = 0x3c3836,
        .ansi = .{ 0x282828, 0xcc241d, 0x98971a, 0xd79921, 0x458588, 0xb16286, 0x689d6a, 0xa89984, 0x928374, 0xfb4934, 0xb8bb26, 0xfabd2f, 0x83a598, 0xd3869b, 0x8ec07c, 0xebdbb2 },
    },
    .{
        .name = "Tokyo Night",
        .dark = true,
        .background = 0x1a1b26,
        .foreground = 0xc0caf5,
        .cursor = 0xc0caf5,
        .panel = 0x24283b,
        .ansi = .{ 0x15161e, 0xf7768e, 0x9ece6a, 0xe0af68, 0x7aa2f7, 0xbb9af7, 0x7dcfff, 0xa9b1d6, 0x414868, 0xf7768e, 0x9ece6a, 0xe0af68, 0x7aa2f7, 0xbb9af7, 0x7dcfff, 0xc0caf5 },
    },
    .{
        .name = "One Dark",
        .dark = true,
        .background = 0x282c34,
        .foreground = 0xabb2bf,
        .cursor = 0x528bff,
        .panel = 0x21252b,
        .ansi = .{ 0x282c34, 0xe06c75, 0x98c379, 0xe5c07b, 0x61afef, 0xc678dd, 0x56b6c2, 0xabb2bf, 0x5c6370, 0xe06c75, 0x98c379, 0xe5c07b, 0x61afef, 0xc678dd, 0x56b6c2, 0xffffff },
    },
    .{
        .name = "Catppuccin Mocha",
        .dark = true,
        .background = 0x1e1e2e,
        .foreground = 0xcdd6f4,
        .cursor = 0xf5e0dc,
        .panel = 0x313244,
        .ansi = .{ 0x45475a, 0xf38ba8, 0xa6e3a1, 0xf9e2af, 0x89b4fa, 0xf5c2e7, 0x94e2d5, 0xbac2de, 0x585b70, 0xf38ba8, 0xa6e3a1, 0xf9e2af, 0x89b4fa, 0xf5c2e7, 0x94e2d5, 0xa6adc8 },
    },
};

const theme_names = [_][*:0]const u8{
    "Caffeine",
    "Caffeine Light",
    "Cadex Dark",
    "Cadex Light",
    "Solarized Dark",
    "Solarized Light",
    "Nord",
    "Dracula",
    "Gruvbox Dark",
    "Tokyo Night",
    "One Dark",
    "Catppuccin Mocha",
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

const Node = struct {
    parent: ?*Split = null,
    kind: enum { leaf, split } = .leaf,
    pane: ?*Pane = null,
    split: ?*Split = null,
};

const Split = struct {
    orientation: c_int,
    widget: *anyopaque,
    first: *Node,
    second: *Node,
    node: *Node,
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
    root: ?*Node = null,
    leaves: std.ArrayList(*Pane) = .empty,
    closed: bool = false,
};

const Pane = struct {
    app: *App,
    tab: *Tab,
    term: ?*terminal.Terminal = null,
    container: *anyopaque,
    area: *anyopaque,
    header_label: *anyopaque,
    header_box: *anyopaque = undefined,
    title: [:0]u8,
    node: *Node = undefined,
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
    preview_view: ?*anyopaque = null,
    preview_visible: bool = true,
    media: bool = false,
    save_button: ?*anyopaque = null,
    preview_button: ?*anyopaque = null,
    notes_button: ?*anyopaque = null,
    language_buf: [48]u8 = undefined,
};

const Entry = struct {
    name: []u8,
    path: [:0]u8,
    directory: bool,
};

const SearchMode = enum { files, content };

const Page = enum { terminal, files, search, git, history, agents, ssh };

const PromptMode = enum { file, folder, rename, url };

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

const NoteRow = struct {
    kind: enum { heading, backlink },
    line: usize,
    path: ?[:0]u8 = null,
};

const AgentState = enum { idle, working, waiting, done };

const AgentSession = struct {
    path: [:0]u8,
    label: []u8,
    mtime: i64,
    state: AgentState = .idle,
    tokens: u64 = 0,
};

const App = struct {
    gpa: std.mem.Allocator,
    window: *anyopaque,
    header: ?*anyopaque = null,
    header_tabs: ?*anyopaque = null,
    branch_label: ?*anyopaque = null,
    sidebar: *anyopaque,
    sidebar_stack: *anyopaque = undefined,
    content: *anyopaque = undefined,
    split_view: ?*anyopaque = null,
    toast_overlay: ?*anyopaque = null,
    pages_stack: ?*anyopaque = null,
    terminal_page: ?*anyopaque = null,
    nav_list: ?*anyopaque = null,
    space_switcher: ?*anyopaque = null,
    page: Page = .terminal,
    spaces_stack: *anyopaque = undefined,
    find_entry: *anyopaque,
    find_open: bool = false,
    cwd_label: *anyopaque,
    stats_label: ?*anyopaque = null,
    tabs_label: *anyopaque,
    message_label: *anyopaque = undefined,
    spaces: std.ArrayList(*Space) = .empty,
    space_index: usize = 0,
    restoring_spaces: bool = false,
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
    files_selected: ?usize = null,
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
    search_case: bool = false,
    search_regex: bool = false,
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
    branch_window: ?*anyopaque = null,
    branch_list: ?*anyopaque = null,
    branch_names: std.ArrayList([]u8) = .empty,

    // History (Run 4).
    history_list: *anyopaque = undefined,
    history_status: *anyopaque = undefined,
    history_log: ?*core.cadex_history = null,
    history_commits: std.ArrayList(documents.git.Commit) = .empty,
    history_selected: ?usize = null,
    history_has_more: bool = true,
    history_loaded: bool = false,

    // Agents, SSH, power and notifications (Run 5).
    agents_list: *anyopaque = undefined,
    agents_status: *anyopaque = undefined,
    agent_sessions: std.ArrayList(AgentSession) = .empty,
    ssh_list: *anyopaque = undefined,
    ssh_status: *anyopaque = undefined,
    ssh_hosts: std.ArrayList([]u8) = .empty,
    ssh_statuses: std.ArrayList(u8) = .empty,
    ssh_selected: ?usize = null,
    ssh_probed: usize = 0,
    ssh_up: usize = 0,
    power_button: ?*anyopaque = null,
    power_pid: i32 = 0,

    // Markdown notes index (headings and backlinks).
    notes_window: ?*anyopaque = null,
    notes_list: ?*anyopaque = null,
    notes_index: ?*core.cadex_markdown_index = null,
    notes_doc: ?*Doc = null,
    notes_rows: std.ArrayList(NoteRow) = .empty,
    notes_tries: u32 = 0,

    // New file/folder prompt.
    prompt_window: ?*anyopaque = null,
    prompt_entry: ?*anyopaque = null,
    prompt_create: ?*anyopaque = null,
    prompt_mode: PromptMode = .file,
    prompt_target: ?[:0]u8 = null,
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
    .{ .id = "sidebar.agents", .title = "Agents", .keywords = "agents claude sessions", .shortcut = "", .run = cmdSidebarAgents },
    .{ .id = "sidebar.ssh", .title = "SSH Hosts", .keywords = "ssh hosts remote", .shortcut = "", .run = cmdSidebarSsh },
    .{ .id = "power.toggle", .title = "Keep Awake", .keywords = "power inhibit sleep awake", .shortcut = "Ctrl+Shift+Alt+P", .run = cmdTogglePower },
    .{ .id = "app.test-notification", .title = "Test Notification", .keywords = "notification test", .shortcut = "", .run = cmdTestNotification },
    .{ .id = "document.save", .title = "Save Document", .keywords = "save write file", .shortcut = "Ctrl+Shift+S", .run = cmdSaveDocument },
    .{ .id = "document.preview", .title = "Toggle Markdown Preview", .keywords = "preview markdown render", .shortcut = "Ctrl+Shift+M", .run = cmdTogglePreview },
    .{ .id = "markdown.notes", .title = "Markdown Headings and Backlinks", .keywords = "markdown notes headings backlinks outline", .shortcut = "Ctrl+Shift+Alt+M", .run = cmdMarkdownNotes },
    .{ .id = "preview.url", .title = "Open URL Preview", .keywords = "preview web url http", .shortcut = "Ctrl+Shift+Alt+U", .run = cmdOpenUrl },
    .{ .id = "preview.test-pick", .title = "Test Element Picker", .keywords = "preview pick element test", .shortcut = "", .run = cmdTestPick },
    .{ .id = "explorer.new-file", .title = "New File", .keywords = "explorer file create", .shortcut = "", .run = cmdNewFile },
    .{ .id = "explorer.new-folder", .title = "New Folder", .keywords = "explorer folder create", .shortcut = "", .run = cmdNewFolder },
    .{ .id = "explorer.rename", .title = "Rename File", .keywords = "explorer rename", .shortcut = "", .run = cmdRenameFile },
    .{ .id = "explorer.delete", .title = "Move to Trash", .keywords = "explorer delete trash", .shortcut = "", .run = cmdDeleteFile },
    .{ .id = "explorer.refresh", .title = "Refresh Explorer", .keywords = "explorer files refresh", .shortcut = "", .run = cmdRefreshExplorer },
    .{ .id = "git.commit-message", .title = "Write Commit Message", .keywords = "git commit message", .shortcut = "Ctrl+Shift+Alt+C", .run = cmdGitCommitMessage },
    .{ .id = "git.branches", .title = "Switch Branch", .keywords = "git branch checkout", .shortcut = "", .run = cmdGitBranches },
    .{ .id = "git.side-diff", .title = "Side-by-Side Diff", .keywords = "git diff side split", .shortcut = "", .run = cmdGitSideDiff },
    .{ .id = "git.init", .title = "Initialize Repository", .keywords = "git init repository", .shortcut = "", .run = cmdGitInit },
    .{ .id = "git.refresh", .title = "Refresh Source Control", .keywords = "git status refresh", .shortcut = "", .run = cmdRefreshGit },
    .{ .id = "history.refresh", .title = "Refresh Git History", .keywords = "git history log refresh", .shortcut = "", .run = cmdRefreshHistory },
    .{ .id = "settings.open", .title = "Settings", .keywords = "settings preferences theme font", .shortcut = "Ctrl+Shift+,", .run = cmdSettings },
    .{ .id = "app.quit", .title = "Quit Cadex", .keywords = "quit exit", .shortcut = "Ctrl+Shift+Q", .run = cmdQuit },
};

// Mac commands that have a Linux equivalent under a different id. They are
// runnable (palette by id) but not listed twice in the palette.
const command_aliases = [_]Command{
    .{ .id = "edit.copy", .title = "Copy", .keywords = "", .shortcut = "", .run = cmdCopy },
    .{ .id = "edit.paste", .title = "Paste", .keywords = "", .shortcut = "", .run = cmdPaste },
    .{ .id = "edit.select-all", .title = "Select All", .keywords = "", .shortcut = "", .run = cmdSelectAll },
    .{ .id = "edit.find", .title = "Find", .keywords = "", .shortcut = "", .run = cmdFind },
    .{ .id = "edit.cut", .title = "Cut", .keywords = "", .shortcut = "", .run = cmdTextCut },
    .{ .id = "edit.undo", .title = "Undo", .keywords = "", .shortcut = "", .run = cmdTextUndo },
    .{ .id = "edit.redo", .title = "Redo", .keywords = "", .shortcut = "", .run = cmdTextRedo },
    .{ .id = "app.hide", .title = "Hide Window", .keywords = "", .shortcut = "", .run = cmdAppHide },
    .{ .id = "editor.save", .title = "Save", .keywords = "", .shortcut = "", .run = cmdSaveDocument },
    .{ .id = "explorer.open", .title = "Open", .keywords = "", .shortcut = "", .run = cmdExplorerOpen },
    .{ .id = "explorer.trash", .title = "Move to Trash", .keywords = "", .shortcut = "", .run = cmdDeleteFile },
    .{ .id = "explorer.copy-path", .title = "Copy Path", .keywords = "", .shortcut = "", .run = cmdExplorerCopyPath },
    .{ .id = "explorer.focus", .title = "Focus Explorer", .keywords = "", .shortcut = "", .run = cmdSidebarFiles },
    .{ .id = "explorer.row", .title = "Open Row", .keywords = "", .shortcut = "", .run = cmdExplorerOpen },
    .{ .id = "explorer.open-in-tab", .title = "Open in Tab", .keywords = "", .shortcut = "", .run = cmdExplorerOpen },
    .{ .id = "explorer.open-beside", .title = "Open", .keywords = "", .shortcut = "", .run = cmdExplorerOpen },
    .{ .id = "explorer.open-in-finder", .title = "Reveal Folder", .keywords = "", .shortcut = "", .run = cmdExplorerReveal },
    .{ .id = "explorer.copy-relative-path", .title = "Copy Relative Path", .keywords = "", .shortcut = "", .run = cmdExplorerCopyRelative },
    .{ .id = "explorer.open-in-terminal", .title = "Open in Terminal", .keywords = "", .shortcut = "", .run = cmdExplorerOpenTerminal },
    .{ .id = "explorer.reveal", .title = "Reveal Folder", .keywords = "", .shortcut = "", .run = cmdExplorerReveal },
    .{ .id = "git.stage", .title = "Stage", .keywords = "", .shortcut = "", .run = cmdGitStage },
    .{ .id = "git.unstage", .title = "Unstage", .keywords = "", .shortcut = "", .run = cmdGitUnstage },
    .{ .id = "git.discard", .title = "Discard", .keywords = "", .shortcut = "", .run = cmdGitDiscard },
    .{ .id = "git.commit", .title = "Commit", .keywords = "", .shortcut = "", .run = cmdGitCommitMessage },
    .{ .id = "git.push", .title = "Push", .keywords = "", .shortcut = "", .run = cmdGitPush },
    .{ .id = "git.pull", .title = "Pull", .keywords = "", .shortcut = "", .run = cmdGitPull },
    .{ .id = "git.fetch", .title = "Fetch", .keywords = "", .shortcut = "", .run = cmdGitFetch },
    .{ .id = "git.stage-all", .title = "Stage All", .keywords = "", .shortcut = "", .run = cmdGitStageAll },
    .{ .id = "git.unstage-all", .title = "Unstage All", .keywords = "", .shortcut = "", .run = cmdGitUnstageAll },
    .{ .id = "git.open-file", .title = "Open File", .keywords = "", .shortcut = "", .run = cmdGitOpenFile },
    .{ .id = "git.open-file-in-tab", .title = "Open File", .keywords = "", .shortcut = "", .run = cmdGitOpenFile },
    .{ .id = "git.open-file-beside", .title = "Open File", .keywords = "", .shortcut = "", .run = cmdGitOpenFile },
    .{ .id = "git.reveal", .title = "Reveal Folder", .keywords = "", .shortcut = "", .run = cmdGitReveal },
    .{ .id = "git.open-diff-in-tab", .title = "Open Diff", .keywords = "", .shortcut = "", .run = cmdGitOpenDiff },
    .{ .id = "git.open-diff-beside", .title = "Open Diff", .keywords = "", .shortcut = "", .run = cmdGitSideDiff },
    .{ .id = "git.history-in-tab", .title = "History", .keywords = "", .shortcut = "", .run = cmdSidebarHistory },
    .{ .id = "git.open-diff", .title = "Open Diff", .keywords = "", .shortcut = "", .run = cmdGitOpenDiff },
    .{ .id = "git.switch-branch", .title = "Switch Branch", .keywords = "", .shortcut = "", .run = cmdGitBranches },
    .{ .id = "git.history", .title = "History", .keywords = "", .shortcut = "", .run = cmdSidebarHistory },
    .{ .id = "git.show", .title = "Source Control", .keywords = "", .shortcut = "", .run = cmdSidebarGit },
    .{ .id = "markdown.backlinks", .title = "Backlinks", .keywords = "", .shortcut = "", .run = cmdMarkdownNotes },
    .{ .id = "markdown.toggle-preview", .title = "Toggle Preview", .keywords = "", .shortcut = "", .run = cmdTogglePreview },
    .{ .id = "pane.next", .title = "Next Pane", .keywords = "", .shortcut = "", .run = cmdPaneNext },
    .{ .id = "pane.previous", .title = "Previous Pane", .keywords = "", .shortcut = "", .run = cmdPanePrev },
    .{ .id = "power.keep-awake", .title = "Keep Awake", .keywords = "", .shortcut = "", .run = cmdPowerKeepAwake },
    .{ .id = "power.allow-sleep", .title = "Allow Sleep", .keywords = "", .shortcut = "", .run = cmdPowerAllowSleep },
    .{ .id = "preview.open", .title = "Open Preview", .keywords = "", .shortcut = "", .run = cmdOpenUrl },
    .{ .id = "preview.back", .title = "Back", .keywords = "", .shortcut = "", .run = cmdPreviewBack },
    .{ .id = "preview.forward", .title = "Forward", .keywords = "", .shortcut = "", .run = cmdPreviewForward },
    .{ .id = "preview.reload", .title = "Reload", .keywords = "", .shortcut = "", .run = cmdPreviewReload },
    .{ .id = "preview.open-in-tab", .title = "Open Preview", .keywords = "", .shortcut = "", .run = cmdOpenUrl },
    .{ .id = "search.files", .title = "Search Files", .keywords = "", .shortcut = "", .run = cmdSearchFiles },
    .{ .id = "search.content", .title = "Search Content", .keywords = "", .shortcut = "", .run = cmdSearchContent },
    .{ .id = "theme.choose", .title = "Next Theme", .keywords = "", .shortcut = "", .run = cmdThemeNext },
    .{ .id = "theme.choose-dark", .title = "Dark Theme", .keywords = "", .shortcut = "", .run = cmdThemeDark },
    .{ .id = "theme.choose-light", .title = "Light Theme", .keywords = "", .shortcut = "", .run = cmdThemeLight },
    .{ .id = "diff.toggle-layout", .title = "Side-by-Side Diff", .keywords = "", .shortcut = "", .run = cmdGitSideDiff },
    .{ .id = "window.new", .title = "New Space", .keywords = "", .shortcut = "", .run = cmdWindowNew },
    .{ .id = "space.switch", .title = "Next Space", .keywords = "", .shortcut = "", .run = cmdSpaceNext },
    .{ .id = "tab.previous-used", .title = "Previous Tab", .keywords = "", .shortcut = "", .run = cmdPrevTab },
    .{ .id = "terminal.scroll-top", .title = "Scroll to Top", .keywords = "", .shortcut = "", .run = cmdTerminalScrollTop },
    .{ .id = "terminal.scroll-bottom", .title = "Scroll to Bottom", .keywords = "", .shortcut = "", .run = cmdTerminalScrollBottom },
    .{ .id = "terminal.clear", .title = "Clear Terminal", .keywords = "", .shortcut = "", .run = cmdTerminalClear },
    .{ .id = "history.copy-sha", .title = "Copy Commit SHA", .keywords = "", .shortcut = "", .run = cmdHistoryCopySha },
    .{ .id = "history.current-branch", .title = "Current Branch", .keywords = "", .shortcut = "", .run = cmdHistoryCurrentBranch },
    .{ .id = "history.open-remote", .title = "Open Commit on the Remote", .keywords = "", .shortcut = "", .run = cmdHistoryOpenRemote },
    .{ .id = "search.toggle-case", .title = "Toggle Case Sensitivity", .keywords = "", .shortcut = "", .run = cmdSearchToggleCase },
    .{ .id = "search.toggle-regex", .title = "Toggle Regex", .keywords = "", .shortcut = "", .run = cmdSearchToggleRegex },
    .{ .id = "power.keep-awake-while-running", .title = "Keep Awake", .keywords = "", .shortcut = "", .run = cmdPowerKeepAwake },
    .{ .id = "settings.open-themes", .title = "Themes", .keywords = "", .shortcut = "", .run = cmdSettings },
    .{ .id = "settings.open-terminal", .title = "Terminal Settings", .keywords = "", .shortcut = "", .run = cmdSettings },
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
        .sidebar = undefined,
        .find_entry = undefined,
        .cwd_label = undefined,
        .tabs_label = undefined,
    };
    loadSettings(app);
    initWorkspace(app, launch);

    app.window = c.cadex_window_new(gtk_app, "Cadex", 1180, 780) orelse return error.GtkFailed;
    app.toast_overlay = c.cadex_adw_toast_overlay_new() orelse return error.GtkFailed;
    app.split_view = c.cadex_adw_window_split_new() orelse return error.GtkFailed;

    // Terminal home page: spaces stack + terminal find bar.
    app.spaces_stack = c.cadex_stack_new() orelse return error.GtkFailed;
    c.cadex_widget_expand(app.spaces_stack);
    c.cadex_stack_on_changed(app.spaces_stack, onSpaceChanged, app);

    app.terminal_page = c.cadex_box_new() orelse return error.GtkFailed;
    app.find_entry = c.cadex_entry_new() orelse return error.GtkFailed;
    c.cadex_widget_visible(app.find_entry, 0);
    c.cadex_entry_changed(app.find_entry, findChanged, app);
    c.cadex_entry_activate(app.find_entry, findActivate, app);
    c.cadex_entry_escape(app.find_entry, findEscape, app);
    c.cadex_widget_expand(app.terminal_page.?);
    c.cadex_box_append(app.terminal_page.?, app.find_entry);
    c.cadex_box_append(app.terminal_page.?, app.spaces_stack);

    app.pages_stack = c.cadex_stack_new() orelse return error.GtkFailed;
    c.cadex_widget_expand(app.pages_stack);
    c.cadex_stack_add(app.pages_stack.?, app.terminal_page.?, "terminal");
    c.cadex_stack_add(app.pages_stack.?, try buildFilesPage(app), "files");
    c.cadex_stack_add(app.pages_stack.?, try buildSearchPage(app), "search");
    c.cadex_stack_add(app.pages_stack.?, try buildGitPage(app), "git");
    c.cadex_stack_add(app.pages_stack.?, try buildHistoryPage(app), "history");
    c.cadex_stack_add(app.pages_stack.?, try buildAgentsPage(app), "agents");
    c.cadex_stack_add(app.pages_stack.?, try buildSshPage(app), "ssh");
    c.cadex_adw_split_set_content(app.split_view.?, app.pages_stack.?);
    c.cadex_widget_add_class(app.pages_stack.?, "cadex-content-panel");
    c.cadex_widget_set_margins(app.pages_stack.?, 3, 6, 6, 6);
    c.cadex_widget_clip(app.pages_stack.?);

    // Bottom status bar, like macOS Cadex.
    const status = try buildStatusBar(app);
    c.cadex_window_set_bottom_bar(app.window, status);

    // Sidebar: app title, project name, navigation rows.
    app.sidebar = c.cadex_box_new() orelse return error.GtkFailed;
    c.cadex_widget_add_class(app.sidebar, "cadex-sidebar-panel");
    c.cadex_widget_set_margins(app.sidebar, 6, 3, 6, 6);
    c.cadex_widget_set_size(app.sidebar, 240, -1);
    c.cadex_widget_clip(app.sidebar);
    const sidebar_title = c.cadex_label_new("Cadex") orelse return error.GtkFailed;
    c.cadex_widget_add_class(sidebar_title, "title-4");
    c.cadex_label_set_xalign(sidebar_title, 0);
    c.cadex_widget_set_margins(sidebar_title, 12, 12, 8, 0);
    c.cadex_box_append(app.sidebar, sidebar_title);
    var project_buf: [256]u8 = undefined;
    const project_text = std.fmt.bufPrintZ(&project_buf, "{s}", .{std.fs.path.basename(app.root)}) catch "Cadex";
    const project_label = c.cadex_label_new(project_text.ptr) orelse return error.GtkFailed;
    c.cadex_widget_add_class(project_label, "dim-label");
    c.cadex_label_set_xalign(project_label, 0);
    c.cadex_widget_set_margins(project_label, 12, 12, 0, 10);
    c.cadex_box_append(app.sidebar, project_label);

    app.nav_list = c.cadex_listbox_new() orelse return error.GtkFailed;
    c.cadex_widget_add_class(app.nav_list.?, "navigation-sidebar");
    const nav_items = [_]struct { icon: [*:0]const u8, label: [*:0]const u8 }{
        .{ .icon = "utilities-terminal-symbolic", .label = "Terminal" },
        .{ .icon = "folder-symbolic", .label = "Files" },
        .{ .icon = "system-search-symbolic", .label = "Search" },
        .{ .icon = "view-list-symbolic", .label = "Git" },
        .{ .icon = "document-open-recent-symbolic", .label = "History" },
        .{ .icon = "system-run-symbolic", .label = "Agents" },
        .{ .icon = "network-server-symbolic", .label = "SSH" },
    };
    for (nav_items) |item| {
        const row = c.cadex_adw_nav_row_new(item.icon, item.label) orelse continue;
        c.cadex_listbox_append_widget(app.nav_list.?, row);
    }
    c.cadex_listbox_on_activated(app.nav_list.?, navRowActivated, app);
    c.cadex_listbox_on_keys(app.nav_list.?, navRowActivated, app);
    c.cadex_widget_expand(app.nav_list.?);
    c.cadex_box_append(app.sidebar, app.nav_list.?);
    c.cadex_widget_expand(app.sidebar);
    c.cadex_adw_split_set_sidebar(app.split_view.?, app.sidebar);
    c.cadex_adw_split_set_sidebar_width(app.split_view.?, 240);
    c.cadex_adw_split_set_show_sidebar(app.split_view.?, 1);

    // Integrated top bar: controls, the current space's tabs and actions,
    // all in one slim row (the macOS Cadex title bar).
    const header = c.cadex_header_new(app.window) orelse return error.GtkFailed;
    app.header = header;
    const controls = c.cadex_box_new_h(4) orelse return error.GtkFailed;
    const sidebar_button = c.cadex_adw_icon_button("sidebar-show-symbolic", sidebarClicked, app) orelse return error.GtkFailed;
    c.cadex_widget_set_tooltip(sidebar_button, "Toggle sidebar");
    c.cadex_box_append(controls, sidebar_button);
    const search_button = c.cadex_adw_icon_button("system-search-symbolic", searchPageClicked, app) orelse return error.GtkFailed;
    c.cadex_widget_set_tooltip(search_button, "Search files and content");
    c.cadex_box_append(controls, search_button);
    app.space_switcher = c.cadex_adw_view_switcher_new(app.spaces_stack) orelse return error.GtkFailed;
    c.cadex_box_append(controls, app.space_switcher.?);
    c.cadex_header_widget_start(header, controls);

    app.header_tabs = c.cadex_adw_tab_bar_new();
    if (app.header_tabs) |bar| c.cadex_header_set_title_widget(header, bar);

    // Primary menu.
    const menu_popover = c.cadex_adw_popover_new() orelse return error.GtkFailed;
    const menu_box = c.cadex_box_new() orelse return error.GtkFailed;
    c.cadex_widget_set_margins(menu_box, 6, 6, 6, 6);
    app.power_button = c.cadex_button_new("Keep Awake", powerClicked, app) orelse return error.GtkFailed;
    c.cadex_widget_set_flat(app.power_button.?);
    c.cadex_box_append(menu_box, app.power_button.?);
    const new_space_item = c.cadex_button_new("New Space", newSpaceClicked, app) orelse return error.GtkFailed;
    c.cadex_widget_set_flat(new_space_item);
    c.cadex_box_append(menu_box, new_space_item);
    const palette_item = c.cadex_button_new("Command Palette", paletteClicked, app) orelse return error.GtkFailed;
    c.cadex_widget_set_flat(palette_item);
    c.cadex_box_append(menu_box, palette_item);
    const settings_item = c.cadex_button_new("Settings", settingsClicked, app) orelse return error.GtkFailed;
    c.cadex_widget_set_flat(settings_item);
    c.cadex_box_append(menu_box, settings_item);
    const test_notify_item = c.cadex_button_new("Test Notification", testNotificationClicked, app) orelse return error.GtkFailed;
    c.cadex_widget_set_flat(test_notify_item);
    c.cadex_box_append(menu_box, test_notify_item);
    const quit_item = c.cadex_button_new("Quit Cadex", quitClicked, app) orelse return error.GtkFailed;
    c.cadex_widget_set_flat(quit_item);
    c.cadex_box_append(menu_box, quit_item);
    c.cadex_adw_popover_set_child(menu_popover, menu_box);
    const menu_button = c.cadex_adw_menu_button_new("open-menu-symbolic", menu_popover) orelse return error.GtkFailed;
    c.cadex_widget_set_tooltip(menu_button, "Main menu");
    c.cadex_header_widget_end(header, menu_button);
    const new_tab_button = c.cadex_adw_icon_button("list-add-symbolic", newTabClicked, app) orelse return error.GtkFailed;
    c.cadex_widget_set_tooltip(new_tab_button, "New terminal tab");
    c.cadex_header_widget_end(header, new_tab_button);

    c.cadex_adw_toast_overlay_set_child(app.toast_overlay.?, app.split_view.?);
    c.cadex_window_child(app.window, app.toast_overlay.?);
    c.cadex_window_on_close(app.window, closeCb, app);
    c.cadex_window_on_key(app.window, windowKey, app);

    try restoreSpaces(app);
    applyFont(app);
    applyTheme(app);
    applySidebar(app);
    openPage(app, .terminal);
    refreshFiles(app);
    refreshGit(app);
    loadHistory(app, false);
    updateStats(app);
    c.cadex_window_present(app.window, @intFromBool(launch.background));
    c.cadex_tray_start(app.window, trayActivated, app);
    if (app.focused) |pane| c.cadex_widget_focus(pane.area);
    _ = c.cadex_timeout(1000, statusTimer, app);
}

fn updateSpaceSwitcher(app: *App) void {
    if (app.space_switcher) |switcher| {
        const show = app.page == .terminal and app.spaces.items.len > 1;
        c.cadex_widget_visible(switcher, @intFromBool(show));
    }
}

fn pageName(page: Page) []const u8 {
    return switch (page) {
        .terminal => "Terminal",
        .files => "Files",
        .search => "Search",
        .git => "Git",
        .history => "History",
        .agents => "Agents",
        .ssh => "SSH",
    };
}

fn pageId(page: Page) [*:0]const u8 {
    return switch (page) {
        .terminal => "terminal",
        .files => "files",
        .search => "search",
        .git => "git",
        .history => "history",
        .agents => "agents",
        .ssh => "ssh",
    };
}

fn openPage(app: *App, page: Page) void {
    if (app.pages_stack == null) return;
    app.page = page;
    if (app.pages_stack) |stack| c.cadex_stack_set(stack, pageId(page));
    if (app.nav_list) |list| c.cadex_listbox_select(list, @intFromEnum(page));
    updateSpaceSwitcher(app);
    switch (page) {
        .files => {
            refreshFiles(app);
            c.cadex_listbox_focus_first(app.files_list);
        },
        .search => {
            c.cadex_widget_focus(app.search_entry);
        },
        .git => {
            refreshGit(app);
            c.cadex_listbox_focus_first(app.git_list);
        },
        .history => {
            if (!app.history_loaded) loadHistory(app, false);
            c.cadex_listbox_focus_first(app.history_list);
        },
        .agents => {
            refreshAgents(app);
            c.cadex_listbox_focus_first(app.agents_list);
        },
        .ssh => {
            refreshSsh(app);
            c.cadex_listbox_focus_first(app.ssh_list);
        },
        .terminal => {
            if (app.focused) |pane| c.cadex_widget_focus(pane.area);
        },
    }
    updateTitle(app);
    updateStatus(app);
}

fn navRowActivated(index: c_int, user: ?*anyopaque) callconv(.c) void {
    const app: *App = @ptrCast(@alignCast(user.?));
    if (index < 0 or index > 6) return;
    openPage(app, @enumFromInt(@as(u8, @intCast(index))));
}

fn onSpaceChanged(name: [*c]const u8, user: ?*anyopaque) callconv(.c) void {
    const app: *App = @ptrCast(@alignCast(user orelse return));
    if (name == null or app.restoring_spaces) return;
    const text = std.mem.span(@as([*:0]const u8, @ptrCast(name)));
    for (app.spaces.items, 0..) |space, index| {
        if (!std.mem.eql(u8, space.name, text)) continue;
        if (index == app.space_index) return;
        app.space_index = index;
        updateHeaderTabs(app, space);
        if (space.tabs.items.len > 0) {
            const page: usize = @intCast(@max(0, c.cadex_notebook_current(space.notebook)));
            activateTab(app, space.tabs.items[@min(page, space.tabs.items.len - 1)]);
        }
        updateTitle(app);
        updateStatus(app);
        return;
    }
}

fn searchPageClicked(user: ?*anyopaque) callconv(.c) void {
    const app: *App = @ptrCast(@alignCast(user.?));
    openPage(app, .search);
}

fn newTabClicked(user: ?*anyopaque) callconv(.c) void {
    const app: *App = @ptrCast(@alignCast(user.?));
    openPage(app, .terminal);
    cmdNewTab(app);
}

fn newSpaceClicked(user: ?*anyopaque) callconv(.c) void {
    const app: *App = @ptrCast(@alignCast(user.?));
    cmdSpaceNew(app);
}

fn testNotificationClicked(user: ?*anyopaque) callconv(.c) void {
    const app: *App = @ptrCast(@alignCast(user.?));
    cmdTestNotification(app);
}

fn quitClicked(user: ?*anyopaque) callconv(.c) void {
    const app: *App = @ptrCast(@alignCast(user.?));
    c.cadex_window_close(app.window);
}

fn closeWindowClicked(user: ?*anyopaque) callconv(.c) void {
    const app: *App = @ptrCast(@alignCast(user.?));
    c.cadex_window_close(app.window);
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

fn buildStatusBar(app: *App) !*anyopaque {
    const bar = c.cadex_box_new_h(8) orelse return error.GtkFailed;
    c.cadex_widget_add_class(bar, "cadex-status");

    const folder_icon = c.cadex_image_new("folder-symbolic") orelse return error.GtkFailed;
    c.cadex_box_append(bar, folder_icon);
    app.cwd_label = c.cadex_label_new("") orelse return error.GtkFailed;
    c.cadex_widget_add_class(app.cwd_label, "cadex-status-strong");
    c.cadex_label_ellipsize(app.cwd_label);
    c.cadex_widget_set_size(app.cwd_label, 220, -1);
    c.cadex_box_append(bar, app.cwd_label);

    const branch_icon = c.cadex_image_new("view-list-symbolic") orelse return error.GtkFailed;
    c.cadex_box_append(bar, branch_icon);
    const branch = c.cadex_label_new("") orelse return error.GtkFailed;
    app.branch_label = branch;
    c.cadex_label_ellipsize(branch);
    c.cadex_box_append(bar, branch);

    const spacer = c.cadex_box_new() orelse return error.GtkFailed;
    c.cadex_widget_expand_h(spacer);
    c.cadex_box_append(bar, spacer);

    app.stats_label = c.cadex_label_new("") orelse return error.GtkFailed;
    c.cadex_box_append(bar, app.stats_label);
    app.tabs_label = c.cadex_label_new("") orelse return error.GtkFailed;
    c.cadex_box_append(bar, app.tabs_label);
    return bar;
}

fn buildFilesPage(app: *App) !*anyopaque {
    const page = c.cadex_box_new() orelse return error.GtkFailed;
    c.cadex_widget_set_margins(page, 18, 18, 12, 18);
    const head = c.cadex_box_new_h(6) orelse return error.GtkFailed;
    app.files_title = c.cadex_label_new("Files") orelse return error.GtkFailed;
    c.cadex_label_ellipsize(app.files_title);
    c.cadex_widget_add_class(app.files_title, "title-4");
    c.cadex_widget_expand_h(app.files_title);
    c.cadex_box_append(head, app.files_title);
    const up = c.cadex_adw_icon_button("go-up-symbolic", filesUpClicked, app) orelse return error.GtkFailed;
    c.cadex_widget_set_tooltip(up, "Parent folder");
    c.cadex_box_append(head, up);
    const refresh = c.cadex_adw_icon_button("view-refresh-symbolic", filesRefreshClicked, app) orelse return error.GtkFailed;
    c.cadex_widget_set_tooltip(refresh, "Refresh");
    c.cadex_box_append(head, refresh);
    c.cadex_box_append(page, head);

    const actions = c.cadex_box_new_h(6) orelse return error.GtkFailed;
    const new_file = c.cadex_adw_icon_button("document-new-symbolic", newFileClicked, app) orelse return error.GtkFailed;
    c.cadex_widget_set_tooltip(new_file, "New file");
    c.cadex_box_append(actions, new_file);
    const new_folder = c.cadex_adw_icon_button("folder-new-symbolic", newFolderClicked, app) orelse return error.GtkFailed;
    c.cadex_widget_set_tooltip(new_folder, "New folder");
    c.cadex_box_append(actions, new_folder);
    const rename = c.cadex_adw_icon_button("document-edit-symbolic", filesRenameClicked, app) orelse return error.GtkFailed;
    c.cadex_widget_set_tooltip(rename, "Rename");
    c.cadex_box_append(actions, rename);
    const trash = c.cadex_adw_icon_button("user-trash-symbolic", filesDeleteClicked, app) orelse return error.GtkFailed;
    c.cadex_widget_set_tooltip(trash, "Move to Trash");
    c.cadex_box_append(actions, trash);
    c.cadex_widget_set_margins(actions, 0, 0, 8, 8);
    c.cadex_box_append(page, actions);

    app.files_list = c.cadex_listbox_new() orelse return error.GtkFailed;
    c.cadex_widget_add_class(app.files_list, "boxed-list");
    c.cadex_listbox_on_activated(app.files_list, filesRowActivated, app);
    c.cadex_listbox_on_keys(app.files_list, filesRowActivated, app);
    const scrolled = c.cadex_scrolled_new(app.files_list) orelse return error.GtkFailed;
    c.cadex_widget_expand(scrolled);
    c.cadex_box_append(page, scrolled);
    return page;
}

fn buildSearchPage(app: *App) !*anyopaque {
    const page = c.cadex_box_new() orelse return error.GtkFailed;
    c.cadex_widget_set_margins(page, 18, 18, 12, 18);
    const title = c.cadex_label_new("Search") orelse return error.GtkFailed;
    c.cadex_label_set_xalign(title, 0);
    c.cadex_widget_add_class(title, "title-4");
    c.cadex_widget_set_margins(title, 0, 0, 0, 8);
    c.cadex_box_append(page, title);
    const entry = c.cadex_entry_new() orelse return error.GtkFailed;
    c.cadex_entry_set_placeholder(entry, "Search files, Enter for content");
    c.cadex_entry_changed(entry, searchChanged, app);
    c.cadex_entry_activate(entry, searchActivated, app);
    c.cadex_widget_set_margins(entry, 0, 0, 0, 6);
    c.cadex_box_append(page, entry);
    app.search_entry = entry;
    const modes = c.cadex_box_new_h(6) orelse return error.GtkFailed;
    c.cadex_box_append(modes, c.cadex_button_new("Files", searchFilesClicked, app) orelse return error.GtkFailed);
    c.cadex_box_append(modes, c.cadex_button_new("Content", searchContentClicked, app) orelse return error.GtkFailed);
    c.cadex_box_append(modes, c.cadex_button_new("Cancel", searchCancelClicked, app) orelse return error.GtkFailed);
    app.search_status = c.cadex_label_new("Files") orelse return error.GtkFailed;
    c.cadex_label_ellipsize(app.search_status);
    c.cadex_widget_add_class(app.search_status, "dim-label");
    c.cadex_widget_expand_h(app.search_status);
    c.cadex_box_append(modes, app.search_status);
    c.cadex_widget_set_margins(modes, 0, 0, 0, 8);
    c.cadex_box_append(page, modes);
    app.search_list = c.cadex_listbox_new() orelse return error.GtkFailed;
    c.cadex_widget_add_class(app.search_list, "boxed-list");
    c.cadex_listbox_on_activated(app.search_list, searchRowActivated, app);
    c.cadex_listbox_on_keys(app.search_list, searchRowActivated, app);
    const scrolled = c.cadex_scrolled_new(app.search_list) orelse return error.GtkFailed;
    c.cadex_widget_expand(scrolled);
    c.cadex_box_append(page, scrolled);
    return page;
}

fn buildGitPage(app: *App) !*anyopaque {
    const page = c.cadex_box_new() orelse return error.GtkFailed;
    c.cadex_widget_set_margins(page, 18, 18, 12, 18);
    const head = c.cadex_box_new_h(6) orelse return error.GtkFailed;
    app.git_branch = c.cadex_label_new("Source control") orelse return error.GtkFailed;
    c.cadex_label_ellipsize(app.git_branch);
    c.cadex_widget_add_class(app.git_branch, "title-4");
    c.cadex_widget_expand_h(app.git_branch);
    c.cadex_box_append(head, app.git_branch);
    const branches = c.cadex_adw_icon_button("view-list-symbolic", gitBranchesClicked, app) orelse return error.GtkFailed;
    c.cadex_widget_set_tooltip(branches, "Switch branch");
    c.cadex_box_append(head, branches);
    const init = c.cadex_adw_icon_button("document-new-symbolic", gitInitClicked, app) orelse return error.GtkFailed;
    c.cadex_widget_set_tooltip(init, "Initialize repository");
    c.cadex_box_append(head, init);
    const refresh = c.cadex_adw_icon_button("view-refresh-symbolic", gitRefreshClicked, app) orelse return error.GtkFailed;
    c.cadex_widget_set_tooltip(refresh, "Refresh");
    c.cadex_box_append(head, refresh);
    c.cadex_box_append(page, head);

    const actions = c.cadex_box_new_h(6) orelse return error.GtkFailed;
    const stage = c.cadex_adw_icon_button("list-add-symbolic", gitStageClicked, app) orelse return error.GtkFailed;
    c.cadex_widget_set_tooltip(stage, "Stage selected file");
    c.cadex_box_append(actions, stage);
    const unstage = c.cadex_adw_icon_button("list-remove-symbolic", gitUnstageClicked, app) orelse return error.GtkFailed;
    c.cadex_widget_set_tooltip(unstage, "Unstage selected file");
    c.cadex_box_append(actions, unstage);
    const discard = c.cadex_adw_icon_button("user-trash-symbolic", gitDiscardClicked, app) orelse return error.GtkFailed;
    c.cadex_widget_set_tooltip(discard, "Discard changes");
    c.cadex_box_append(actions, discard);
    const side = c.cadex_adw_icon_button("view-dual-symbolic", gitSideDiffClicked, app) orelse return error.GtkFailed;
    c.cadex_widget_set_tooltip(side, "Side-by-side diff");
    c.cadex_box_append(actions, side);
    const pull = c.cadex_adw_icon_button("go-down-symbolic", gitPullClicked, app) orelse return error.GtkFailed;
    c.cadex_widget_set_tooltip(pull, "Pull");
    c.cadex_box_append(actions, pull);
    const push = c.cadex_adw_icon_button("go-up-symbolic", gitPushClicked, app) orelse return error.GtkFailed;
    c.cadex_widget_set_tooltip(push, "Push");
    c.cadex_box_append(actions, push);
    const fetch = c.cadex_adw_icon_button("view-refresh-symbolic", gitFetchClicked, app) orelse return error.GtkFailed;
    c.cadex_widget_set_tooltip(fetch, "Fetch");
    c.cadex_box_append(actions, fetch);
    c.cadex_widget_set_margins(actions, 0, 0, 8, 8);
    c.cadex_box_append(page, actions);

    const commit_row = c.cadex_box_new_h(6) orelse return error.GtkFailed;
    app.git_commit_entry = c.cadex_entry_new() orelse return error.GtkFailed;
    c.cadex_entry_set_placeholder(app.git_commit_entry, "Commit message");
    c.cadex_entry_activate(app.git_commit_entry, gitCommitClicked, app);
    c.cadex_widget_expand_h(app.git_commit_entry);
    c.cadex_box_append(commit_row, app.git_commit_entry);
    const commit_button = c.cadex_button_new("Commit All", gitCommitClicked, app) orelse return error.GtkFailed;
    c.cadex_widget_add_class(commit_button, "suggested-action");
    c.cadex_box_append(commit_row, commit_button);
    c.cadex_widget_set_margins(commit_row, 0, 0, 0, 10);
    c.cadex_box_append(page, commit_row);

    app.git_status = c.cadex_label_new("") orelse return error.GtkFailed;
    c.cadex_label_ellipsize(app.git_status);
    c.cadex_widget_add_class(app.git_status, "dim-label");
    c.cadex_box_append(page, app.git_status);
    const changes = c.cadex_label_new("Changes") orelse return error.GtkFailed;
    c.cadex_label_set_xalign(changes, 0);
    c.cadex_widget_add_class(changes, "heading");
    c.cadex_widget_set_margins(changes, 0, 0, 4, 4);
    c.cadex_box_append(page, changes);
    app.git_list = c.cadex_listbox_new() orelse return error.GtkFailed;
    c.cadex_widget_add_class(app.git_list, "boxed-list");
    c.cadex_listbox_on_activated(app.git_list, gitRowActivated, app);
    c.cadex_listbox_on_keys(app.git_list, gitRowActivated, app);
    const scrolled = c.cadex_scrolled_new(app.git_list) orelse return error.GtkFailed;
    c.cadex_widget_expand(scrolled);
    c.cadex_box_append(page, scrolled);
    return page;
}

fn buildHistoryPage(app: *App) !*anyopaque {
    const page = c.cadex_box_new() orelse return error.GtkFailed;
    c.cadex_widget_set_margins(page, 18, 18, 12, 18);
    const head = c.cadex_box_new_h(6) orelse return error.GtkFailed;
    app.history_status = c.cadex_label_new("History") orelse return error.GtkFailed;
    c.cadex_label_ellipsize(app.history_status);
    c.cadex_widget_add_class(app.history_status, "title-4");
    c.cadex_widget_expand_h(app.history_status);
    c.cadex_box_append(head, app.history_status);
    const refresh = c.cadex_adw_icon_button("view-refresh-symbolic", historyRefreshClicked, app) orelse return error.GtkFailed;
    c.cadex_widget_set_tooltip(refresh, "Refresh");
    c.cadex_box_append(head, refresh);
    const more = c.cadex_adw_icon_button("go-down-symbolic", historyMoreClicked, app) orelse return error.GtkFailed;
    c.cadex_widget_set_tooltip(more, "Load more");
    c.cadex_box_append(head, more);
    c.cadex_widget_set_margins(head, 0, 0, 0, 8);
    c.cadex_box_append(page, head);
    app.history_list = c.cadex_listbox_new() orelse return error.GtkFailed;
    c.cadex_widget_add_class(app.history_list, "boxed-list");
    c.cadex_listbox_on_activated(app.history_list, historyRowActivated, app);
    c.cadex_listbox_on_keys(app.history_list, historyRowActivated, app);
    const scrolled = c.cadex_scrolled_new(app.history_list) orelse return error.GtkFailed;
    c.cadex_widget_expand(scrolled);
    c.cadex_box_append(page, scrolled);
    return page;
}

fn buildAgentsPage(app: *App) !*anyopaque {
    const page = c.cadex_box_new() orelse return error.GtkFailed;
    c.cadex_widget_set_margins(page, 18, 18, 12, 18);
    const head = c.cadex_box_new_h(6) orelse return error.GtkFailed;
    const title = c.cadex_label_new("Claude sessions") orelse return error.GtkFailed;
    c.cadex_label_ellipsize(title);
    c.cadex_widget_add_class(title, "title-4");
    c.cadex_widget_expand_h(title);
    c.cadex_box_append(head, title);
    const refresh = c.cadex_adw_icon_button("view-refresh-symbolic", agentsRefreshClicked, app) orelse return error.GtkFailed;
    c.cadex_widget_set_tooltip(refresh, "Refresh");
    c.cadex_box_append(head, refresh);
    c.cadex_widget_set_margins(head, 0, 0, 0, 8);
    c.cadex_box_append(page, head);
    app.agents_status = c.cadex_label_new("") orelse return error.GtkFailed;
    c.cadex_label_ellipsize(app.agents_status);
    c.cadex_widget_add_class(app.agents_status, "dim-label");
    c.cadex_widget_set_margins(app.agents_status, 0, 0, 0, 8);
    c.cadex_box_append(page, app.agents_status);
    app.agents_list = c.cadex_listbox_new() orelse return error.GtkFailed;
    c.cadex_widget_add_class(app.agents_list, "boxed-list");
    c.cadex_listbox_on_activated(app.agents_list, agentsRowActivated, app);
    c.cadex_listbox_on_keys(app.agents_list, agentsRowActivated, app);
    const scrolled = c.cadex_scrolled_new(app.agents_list) orelse return error.GtkFailed;
    c.cadex_widget_expand(scrolled);
    c.cadex_box_append(page, scrolled);
    return page;
}

fn buildSshPage(app: *App) !*anyopaque {
    const page = c.cadex_box_new() orelse return error.GtkFailed;
    c.cadex_widget_set_margins(page, 18, 18, 12, 18);
    const head = c.cadex_box_new_h(6) orelse return error.GtkFailed;
    const title = c.cadex_label_new("SSH hosts") orelse return error.GtkFailed;
    c.cadex_label_ellipsize(title);
    c.cadex_widget_add_class(title, "title-4");
    c.cadex_widget_expand_h(title);
    c.cadex_box_append(head, title);
    const test_button = c.cadex_adw_icon_button("network-transmit-receive-symbolic", sshTestClicked, app) orelse return error.GtkFailed;
    c.cadex_widget_set_tooltip(test_button, "Test hosts");
    c.cadex_box_append(head, test_button);
    const refresh = c.cadex_adw_icon_button("view-refresh-symbolic", sshRefreshClicked, app) orelse return error.GtkFailed;
    c.cadex_widget_set_tooltip(refresh, "Refresh");
    c.cadex_box_append(head, refresh);
    c.cadex_widget_set_margins(head, 0, 0, 0, 8);
    c.cadex_box_append(page, head);
    app.ssh_status = c.cadex_label_new("") orelse return error.GtkFailed;
    c.cadex_label_ellipsize(app.ssh_status);
    c.cadex_widget_add_class(app.ssh_status, "dim-label");
    c.cadex_widget_set_margins(app.ssh_status, 0, 0, 0, 8);
    c.cadex_box_append(page, app.ssh_status);
    app.ssh_list = c.cadex_listbox_new() orelse return error.GtkFailed;
    c.cadex_widget_add_class(app.ssh_list, "boxed-list");
    c.cadex_listbox_on_activated(app.ssh_list, sshRowActivated, app);
    c.cadex_listbox_on_keys(app.ssh_list, sshRowActivated, app);
    const scrolled = c.cadex_scrolled_new(app.ssh_list) orelse return error.GtkFailed;
    c.cadex_widget_expand(scrolled);
    c.cadex_box_append(page, scrolled);
    return page;
}

fn clearAgents(app: *App) void {
    for (app.agent_sessions.items) |session| {
        app.gpa.free(session.path);
        app.gpa.free(session.label);
    }
    app.agent_sessions.clearRetainingCapacity();
}

fn numberAfter(line: []const u8, needle: []const u8) ?u64 {
    const at = std.mem.indexOf(u8, line, needle) orelse return null;
    var start = at + needle.len;
    while (start < line.len and (line[start] == ' ' or line[start] == '"')) start += 1;
    var end = start;
    while (end < line.len and line[end] >= '0' and line[end] <= '9') end += 1;
    if (end == start) return null;
    return std.fmt.parseInt(u64, line[start..end], 10) catch null;
}

fn inspectSession(path: [:0]const u8) struct { state: AgentState, tokens: u64 } {
    var data: ?[*]u8 = null;
    var len: usize = 0;
    var status = core.cadex_explorer_read_text(path.ptr, 512 * 1024, &data, &len);
    if (status == core.CADEX_TOO_LARGE) {
        status = core.cadex_explorer_read_text_head(path.ptr, 512 * 1024, &data, &len, null);
    }
    if (status != core.CADEX_OK or data == null) return .{ .state = .idle, .tokens = 0 };
    defer core.cadex_free(@ptrCast(data.?));
    const text = data.?[0..len];
    var state: AgentState = .idle;
    var tokens: u64 = 0;
    var lines = std.mem.splitScalar(u8, text, '\n');
    while (lines.next()) |line| {
        if (std.mem.indexOf(u8, line, "\"type\":\"assistant\"") != null) state = .working;
        if (std.mem.indexOf(u8, line, "\"type\":\"user\"") != null) state = .waiting;
        if (std.mem.indexOf(u8, line, "\"type\":\"result\"") != null or std.mem.indexOf(u8, line, "\"is_error\":true") != null) state = .done;
        if (numberAfter(line, "\"input_tokens\":")) |value| tokens += value;
        if (numberAfter(line, "\"output_tokens\":")) |value| tokens += value;
    }
    return .{ .state = state, .tokens = tokens };
}

fn stateName(state: AgentState) []const u8 {
    return switch (state) {
        .idle => "idle",
        .working => "working",
        .waiting => "waiting",
        .done => "done",
    };
}

fn refreshAgents(app: *App) void {
    clearAgents(app);
    c.cadex_listbox_clear(app.agents_list);
    const home_z = std.c.getenv("HOME") orelse {
        c.cadex_label_set(app.agents_status, "HOME is not set");
        return;
    };
    const home = std.mem.span(home_z);
    const root = std.fmt.allocPrintSentinel(app.gpa, "{s}/.claude/projects", .{home}, 0) catch return;
    defer app.gpa.free(root);
    var auth_out: ?[*]u8 = null;
    var auth_len: usize = 0;
    if (core.cadex_workspace_authorize(root.ptr, &auth_out, &auth_len) == core.CADEX_OK and auth_out != null) {
        core.cadex_free(@ptrCast(auth_out.?));
    }
    const names_ptr = c.cadex_list_dir(root.ptr) orelse {
        c.cadex_label_set(app.agents_status, "No ~/.claude/projects folder");
        return;
    };
    defer c.cadex_gtk_free(@ptrCast(names_ptr));
    const names = std.mem.span(@as([*:0]const u8, @ptrCast(names_ptr)));

    var candidates: std.ArrayList(AgentSession) = .empty;
    var projects = std.mem.splitScalar(u8, names, '\n');
    while (projects.next()) |project| {
        if (project.len == 0 or project[0] == '.') continue;
        const dir = std.fs.path.join(app.gpa, &.{ root, project }) catch continue;
        defer app.gpa.free(dir);
        const dir_z = app.gpa.dupeZ(u8, dir) catch continue;
        defer app.gpa.free(dir_z);
        const files_ptr = c.cadex_list_dir(dir_z.ptr) orelse continue;
        defer c.cadex_gtk_free(@ptrCast(files_ptr));
        const files = std.mem.span(@as([*:0]const u8, @ptrCast(files_ptr)));
        var entries = std.mem.splitScalar(u8, files, '\n');
        while (entries.next()) |name| {
            if (!endsWithIgnoreCase(name, ".jsonl")) continue;
            const full = std.fs.path.join(app.gpa, &.{ dir, name }) catch continue;
            defer app.gpa.free(full);
            const full_z = app.gpa.dupeZ(u8, full) catch continue;
            var is_dir: c_int = 0;
            var mtime: c_longlong = 0;
            var size: c_longlong = 0;
            if (c.cadex_path_info(full_z.ptr, &is_dir, &mtime, &size) == 0 or is_dir != 0) {
                app.gpa.free(full_z);
                continue;
            }
            const inspected = inspectSession(full_z);
            const label = std.fmt.allocPrint(app.gpa, "{s}/{s}  ·  {s}  ·  {d}k", .{
                project, name, stateName(inspected.state), inspected.tokens / 1000,
            }) catch {
                app.gpa.free(full_z);
                continue;
            };
            candidates.append(app.gpa, .{
                .path = full_z,
                .label = label,
                .mtime = @intCast(mtime),
                .state = inspected.state,
                .tokens = inspected.tokens,
            }) catch {
                app.gpa.free(full_z);
                app.gpa.free(label);
            };
        }
    }

    std.mem.sort(AgentSession, candidates.items, {}, struct {
        fn lessThan(_: void, a: AgentSession, b: AgentSession) bool {
            return a.mtime > b.mtime;
        }
    }.lessThan);

    var shown: usize = 0;
    for (candidates.items) |session| {
        if (shown >= 40) {
            app.gpa.free(session.path);
            app.gpa.free(session.label);
            continue;
        }
        const label = app.gpa.dupeZ(u8, session.label) catch {
            app.gpa.free(session.path);
            app.gpa.free(session.label);
            continue;
        };
        defer app.gpa.free(label);
        c.cadex_listbox_append_action(app.agents_list, "system-run-symbolic", label.ptr, "Claude session");
        app.agent_sessions.append(app.gpa, session) catch {
            app.gpa.free(session.path);
            app.gpa.free(session.label);
        };
        shown += 1;
    }
    candidates.deinit(app.gpa);

    var buf: [96]u8 = undefined;
    const status = std.fmt.bufPrintZ(&buf, "Sessions: {d}", .{app.agent_sessions.items.len}) catch "Agents";
    c.cadex_label_set(app.agents_status, status.ptr);
}

fn agentsRowActivated(index: c_int, user: ?*anyopaque) callconv(.c) void {
    const app: *App = @ptrCast(@alignCast(user.?));
    if (index < 0) return;
    const at: usize = @intCast(index);
    if (at >= app.agent_sessions.items.len) return;
    openDocument(app, app.agent_sessions.items[at].path, 0);
}

fn agentsRefreshClicked(user: ?*anyopaque) callconv(.c) void {
    const app: *App = @ptrCast(@alignCast(user.?));
    refreshAgents(app);
}

fn clearSsh(app: *App) void {
    for (app.ssh_hosts.items) |host| app.gpa.free(host);
    app.ssh_hosts.clearRetainingCapacity();
    app.ssh_statuses.clearRetainingCapacity();
    app.ssh_selected = null;
    app.ssh_probed = 0;
    app.ssh_up = 0;
}

fn rebuildSshRows(app: *App) void {
    c.cadex_listbox_clear(app.ssh_list);
    for (app.ssh_hosts.items, 0..) |host, index| {
        const mark = if (index < app.ssh_statuses.items.len) switch (app.ssh_statuses.items[index]) {
            1 => "up",
            2 => "down",
            else => "testing…",
        } else "testing…";
        const title = app.gpa.dupeZ(u8, host) catch continue;
        defer app.gpa.free(title);
        c.cadex_listbox_append_action(app.ssh_list, "network-server-symbolic", title.ptr, @ptrCast(mark.ptr));
    }
}

fn updateSshStatus(app: *App) void {
    var buf: [128]u8 = undefined;
    const text = if (app.ssh_hosts.items.len == 0)
        "No hosts in ~/.ssh/config"
    else
        std.fmt.bufPrintZ(&buf, "Hosts: {d} · {d} up · {d}/{d} tested", .{
            app.ssh_hosts.items.len, app.ssh_up, app.ssh_probed, app.ssh_hosts.items.len,
        }) catch "SSH";
    c.cadex_label_set(app.ssh_status, text.ptr);
}

fn onSshProbe(host: [*c]const u8, ok: c_int, user: ?*anyopaque) callconv(.c) void {
    const app: *App = @ptrCast(@alignCast(user orelse return));
    if (host == null or app.closing) return;
    const name = std.mem.span(@as([*:0]const u8, @ptrCast(host)));
    for (app.ssh_hosts.items, 0..) |known, index| {
        if (!std.mem.eql(u8, known, name)) continue;
        if (index >= app.ssh_statuses.items.len) return;
        app.ssh_statuses.items[index] = if (ok != 0) 1 else 2;
        app.ssh_probed += 1;
        if (ok != 0) app.ssh_up += 1;
        break;
    }
    rebuildSshRows(app);
    updateSshStatus(app);
}

fn probeSsh(app: *App) void {
    app.ssh_probed = 0;
    app.ssh_up = 0;
    for (app.ssh_statuses.items) |*status| status.* = 0;
    rebuildSshRows(app);
    updateSshStatus(app);
    for (app.ssh_hosts.items) |host| {
        const z = app.gpa.dupeZ(u8, host) catch continue;
        defer app.gpa.free(z);
        c.cadex_ssh_probe(z.ptr, onSshProbe, app);
    }
}

fn refreshSsh(app: *App) void {
    clearSsh(app);
    c.cadex_listbox_clear(app.ssh_list);
    const home_z = std.c.getenv("HOME") orelse {
        c.cadex_label_set(app.ssh_status, "HOME is not set");
        return;
    };
    const path = std.fmt.allocPrintSentinel(app.gpa, "{s}/.ssh/config", .{std.mem.span(home_z)}, 0) catch return;
    defer app.gpa.free(path);
    var len: usize = 0;
    const raw = c.cadex_read_file(path.ptr, &len);
    if (raw == null) {
        c.cadex_label_set(app.ssh_status, "No ~/.ssh/config");
        return;
    }
    defer c.cadex_gtk_free(@ptrCast(raw));
    const text = raw[0..len];
    var lines = std.mem.splitScalar(u8, text, '\n');
    while (lines.next()) |line| {
        const trimmed = std.mem.trim(u8, line, " \t\r");
        if (!std.ascii.startsWithIgnoreCase(trimmed, "host ")) continue;
        var fields = std.mem.tokenizeAny(u8, trimmed[5..], " \t\r");
        while (fields.next()) |host| {
            if (host.len == 0 or std.mem.indexOfAny(u8, host, "*?!") != null) continue;
            var exists = false;
            for (app.ssh_hosts.items) |known| {
                if (std.mem.eql(u8, known, host)) {
                    exists = true;
                    break;
                }
            }
            if (exists) continue;
            const copy = app.gpa.dupe(u8, host) catch continue;
            app.ssh_hosts.append(app.gpa, copy) catch {
                app.gpa.free(copy);
                continue;
            };
        }
    }
    for (app.ssh_hosts.items) |_| app.ssh_statuses.append(app.gpa, 0) catch {};
    rebuildSshRows(app);
    updateSshStatus(app);
    probeSsh(app);
}

fn sshRowActivated(index: c_int, user: ?*anyopaque) callconv(.c) void {
    const app: *App = @ptrCast(@alignCast(user.?));
    if (index < 0) return;
    const at: usize = @intCast(index);
    if (at >= app.ssh_hosts.items.len) return;
    app.ssh_selected = at;
    const host = app.ssh_hosts.items[at];
    newTab(app, currentSpace(app)) catch return;
    const pane = app.focused orelse return;
    const term = pane.term orelse return;
    const command = std.fmt.allocPrint(app.gpa, "ssh {s}\n", .{host}) catch return;
    defer app.gpa.free(command);
    term.write(command);
    showMessage(app, "Connecting with ssh");
}

fn sshRefreshClicked(user: ?*anyopaque) callconv(.c) void {
    const app: *App = @ptrCast(@alignCast(user.?));
    refreshSsh(app);
}

fn sshTestClicked(user: ?*anyopaque) callconv(.c) void {
    const app: *App = @ptrCast(@alignCast(user.?));
    probeSsh(app);
}

fn clearEntries(app: *App) void {
    for (app.files_entries.items) |entry| {
        app.gpa.free(entry.name);
        app.gpa.free(entry.path);
    }
    app.files_entries.clearRetainingCapacity();
}

fn addFilesRow(app: *App, name: []const u8, path: [:0]u8, directory: bool) void {
    const title = std.fmt.allocPrintSentinel(app.gpa, "{s}{s}", .{
        name,
        if (directory) "/" else "",
    }, 0) catch {
        app.gpa.free(path);
        return;
    };
    defer app.gpa.free(title);
    const name_copy = app.gpa.dupe(u8, name) catch {
        app.gpa.free(path);
        return;
    };
    app.files_entries.append(app.gpa, .{ .name = name_copy, .path = path, .directory = directory }) catch {
        app.gpa.free(name_copy);
        app.gpa.free(path);
        return;
    };
    const icon: [*:0]const u8 = if (directory) "folder-symbolic" else "text-x-generic-symbolic";
    const subtitle: [*:0]const u8 = if (directory) "Folder" else "File";
    c.cadex_listbox_append_action(app.files_list, icon, title.ptr, subtitle);
}

fn refreshFiles(app: *App) void {
    if (app.closing) return;
    app.files_selected = null;
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
    app.files_selected = at;
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
    promptOpen(app, .file);
}

fn newFolderClicked(user: ?*anyopaque) callconv(.c) void {
    const app: *App = @ptrCast(@alignCast(user.?));
    promptOpen(app, .folder);
}

fn filesRenameClicked(user: ?*anyopaque) callconv(.c) void {
    const app: *App = @ptrCast(@alignCast(user.?));
    const index = app.files_selected orelse {
        showMessage(app, "Select a file first");
        return;
    };
    if (index >= app.files_entries.items.len) return;
    const entry = app.files_entries.items[index];
    if (entry.path.len == 0) return;
    if (app.prompt_target) |old| app.gpa.free(old);
    app.prompt_target = app.gpa.dupeZ(u8, entry.path) catch null;
    promptOpen(app, .rename);
}

fn filesDeleteClicked(user: ?*anyopaque) callconv(.c) void {
    const app: *App = @ptrCast(@alignCast(user.?));
    const index = app.files_selected orelse {
        showMessage(app, "Select a file first");
        return;
    };
    if (index >= app.files_entries.items.len) return;
    const entry = app.files_entries.items[index];
    if (entry.path.len == 0) return;
    if (c.cadex_trash_file(entry.path.ptr) != 0) {
        showMessage(app, "Moved to the Trash");
        refreshFiles(app);
    } else {
        showMessage(app, "Could not move it to the Trash");
    }
}

fn promptOpen(app: *App, mode: PromptMode) void {
    app.prompt_mode = mode;
    if (app.prompt_window == null) createPrompt(app);
    const window = app.prompt_window orelse return;
    const entry = app.prompt_entry orelse return;
    c.cadex_entry_set_text(entry, "");
    c.cadex_entry_set_placeholder(entry, switch (mode) {
        .file => "File name",
        .folder => "Folder name",
        .rename => "New name",
        .url => "https://example.com",
    });
    c.cadex_window_title(window, switch (mode) {
        .file => "New file",
        .folder => "New folder",
        .rename => "Rename",
        .url => "Open URL preview",
    });
    if (app.prompt_create) |button| {
        c.cadex_button_set_text(button, switch (mode) {
            .file, .folder => "Create",
            .rename => "Rename",
            .url => "Open",
        });
    }
    if (mode == .rename) {
        if (app.prompt_target) |target| {
            const base_z = app.gpa.dupeZ(u8, std.fs.path.basename(target)) catch return;
            defer app.gpa.free(base_z);
            c.cadex_entry_set_text(entry, base_z.ptr);
        }
    }
    c.cadex_window_present(window, 0);
    c.cadex_widget_focus(entry);
}

fn createPrompt(app: *App) void {
    const window = c.cadex_window_new_dialog(app.window, "New", 460, 190) orelse return;
    c.cadex_window_hide_on_close(window);
    c.cadex_widget_on_escape(window, promptCancel, app);
    const box = c.cadex_box_new() orelse return;
    c.cadex_widget_set_margins(box, 18, 18, 18, 18);
    const entry = c.cadex_entry_new() orelse return;
    c.cadex_entry_activate(entry, promptCreate, app);
    c.cadex_entry_escape(entry, promptCancel, app);
    c.cadex_box_append(box, entry);
    const actions = c.cadex_box_new_h(6) orelse return;
    c.cadex_widget_set_margins(actions, 0, 0, 10, 0);
    const create_button = c.cadex_button_new("Create", promptCreate, app) orelse return;
    c.cadex_box_append(actions, create_button);
    c.cadex_widget_add_class(create_button, "suggested-action");
    c.cadex_box_append(actions, c.cadex_button_new("Cancel", promptCancel, app) orelse return);
    c.cadex_box_append(box, actions);
    c.cadex_window_child(window, box);
    app.prompt_window = window;
    app.prompt_entry = entry;
    app.prompt_create = create_button;
}

fn promptCreate(user: ?*anyopaque) callconv(.c) void {
    const app: *App = @ptrCast(@alignCast(user.?));
    const entry = app.prompt_entry orelse return;
    const raw = c.cadex_entry_text(entry);
    if (raw == null) return;
    const text = std.mem.span(@as([*:0]const u8, @ptrCast(raw)));
    const name = std.mem.trim(u8, text, " \t");
    if (app.prompt_mode == .url) {
        const url_z = app.gpa.dupeZ(u8, name) catch return;
        defer app.gpa.free(url_z);
        if (!std.mem.startsWith(u8, name, "http://") and !std.mem.startsWith(u8, name, "https://")) {
            showMessage(app, "The URL must start with http:// or https://");
            return;
        }
        if (app.prompt_window) |window| c.cadex_window_hide(window);
        openUrlTab(app, url_z);
        return;
    }
    if (name.len == 0 or std.mem.indexOfAny(u8, name, "/\\") != null) {
        showMessage(app, "Type a plain file or folder name");
        return;
    }
    if (app.prompt_mode == .rename) {
        const target = app.prompt_target orelse return;
        const name_z = app.gpa.dupeZ(u8, name) catch return;
        defer app.gpa.free(name_z);
        var out: ?[*]u8 = null;
        var out_len: usize = 0;
        const status = core.cadex_explorer_rename(target.ptr, name_z.ptr, &out, &out_len);
        if (out != null) core.cadex_free(@ptrCast(out.?));
        if (status != core.CADEX_OK) {
            showMessage(app, "Could not rename it (the name may exist)");
            return;
        }
        if (app.prompt_window) |window| c.cadex_window_hide(window);
        refreshFiles(app);
        showMessage(app, "Renamed");
        return;
    }
    const full = std.fs.path.join(app.gpa, &.{ app.files_path, name }) catch return;
    defer app.gpa.free(full);
    const z = app.gpa.dupeZ(u8, full) catch return;
    defer app.gpa.free(z);
    const status = if (app.prompt_mode == .folder)
        core.cadex_explorer_create_directory(z.ptr)
    else
        core.cadex_explorer_create_file(z.ptr);
    if (status != core.CADEX_OK) {
        showMessage(app, "Could not create it (the name may exist)");
        return;
    }
    if (app.prompt_window) |window| c.cadex_window_hide(window);
    refreshFiles(app);
    showMessage(app, if (app.prompt_mode == .folder) "Folder created" else "File created");
}

fn promptCancel(user: ?*anyopaque) callconv(.c) void {
    const app: *App = @ptrCast(@alignCast(user.?));
    if (app.prompt_window) |window| c.cadex_window_hide(window);
}

fn showMessage(app: *App, text: []const u8) void {
    const overlay = app.toast_overlay orelse return;
    var buf: [512]u8 = undefined;
    const z = std.fmt.bufPrintZ(&buf, "{s}", .{text}) catch return;
    c.cadex_adw_toast(overlay, z.ptr);
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
    if (doc.media) return;
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
    if (doc.preview_view) |webview| {
        const html = buildPreviewHtml(doc.app, text) catch return;
        defer doc.app.gpa.free(html);
        c.cadex_webview_load_html(webview, html.ptr, null);
        return;
    }
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

fn buildPreviewHtml(app: *App, text: []const u8) ![:0]u8 {
    var out: std.ArrayList(u8) = .empty;
    defer out.deinit(app.gpa);
    var body: ?[*]u8 = null;
    var body_len: usize = 0;
    if (core.cadex_markdown_render(text.ptr, text.len, &body, &body_len) != core.CADEX_OK or body == null) {
        return error.Markdown;
    }
    defer core.cadex_free(@ptrCast(body.?));
    const theme = themes[app.theme_index];
    const head = try std.fmt.allocPrint(app.gpa, "<!doctype html><html><head><meta charset=\"utf-8\"><style>" ++
        "body{{background:#{x:0>6};color:#{x:0>6};font-family:system-ui,sans-serif;" ++
        "font-size:15px;line-height:1.55;padding:18px;margin:0;}}" ++
        "a{{color:#4fc1ff;}}pre{{background:#{x:0>6};padding:12px;border-radius:6px;overflow:auto;}}" ++
        "code{{background:#{x:0>6};padding:1px 4px;border-radius:4px;font-family:monospace;}}" ++
        "pre code{{background:transparent;padding:0;}}" ++
        "blockquote{{border-left:3px solid #4fc1ff;margin-left:0;padding-left:12px;color:#9aa0a6;}}" ++
        "table{{border-collapse:collapse;}}td,th{{border:1px solid #555;padding:4px 8px;}}" ++
        "img{{max-width:100%;}}</style></head><body>", .{ theme.background, theme.foreground, theme.panel, theme.panel });
    defer app.gpa.free(head);
    try out.appendSlice(app.gpa, head);
    try out.appendSlice(app.gpa, body.?[0..body_len]);
    try out.appendSlice(app.gpa, "</body></html>");
    return app.gpa.dupeZ(u8, out.items);
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
                openPage(app, .terminal);
                c.cadex_text_view_scroll_to_line(doc.view, @intCast(line));
                return;
            }
        }
    }

    const title = std.fs.path.basename(path);
    if (endsWithIgnoreCase(title, ".pdf")) {
        openPdfTab(app, path, title);
        return;
    }
    switch (mediaKind(title)) {
        .image => {
            openMediaTab(app, path, title, .image);
            return;
        },
        .video => {
            openMediaTab(app, path, title, .video);
            return;
        },
        .audio => {
            openMediaTab(app, path, title, .audio);
            return;
        },
        .none => {},
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

const MediaKind = enum { none, image, video, audio };

const image_exts = [_][]const u8{ ".png", ".jpg", ".jpeg", ".gif", ".webp", ".bmp", ".svg", ".ico", ".avif" };
const video_exts = [_][]const u8{ ".mp4", ".webm", ".mkv", ".mov", ".avi", ".m4v", ".ogv" };
const audio_exts = [_][]const u8{ ".mp3", ".ogg", ".oga", ".flac", ".wav", ".m4a", ".opus" };

fn mediaKind(name: []const u8) MediaKind {
    for (image_exts) |ext| if (endsWithIgnoreCase(name, ext)) return .image;
    for (video_exts) |ext| if (endsWithIgnoreCase(name, ext)) return .video;
    for (audio_exts) |ext| if (endsWithIgnoreCase(name, ext)) return .audio;
    return .none;
}

fn openUrlTab(app: *App, url: [:0]const u8) void {
    openWebTab(app, url, url, false);
}

fn openPdfTab(app: *App, path: [:0]const u8, title: []const u8) void {
    openWebTab(app, title, path, true);
}

fn openWebTab(app: *App, title_text: []const u8, source: [:0]const u8, file: bool) void {
    if (c.cadex_webkit_available() == 0) {
        showMessage(app, "WebKitGTK is not available in this build");
        return;
    }
    const gpa = app.gpa;
    const tab = gpa.create(Tab) catch return;
    const title = gpa.dupeZ(u8, title_text) catch return;
    const path_copy = if (file) gpa.dupeZ(u8, source) catch return else gpa.dupeZ(u8, "") catch return;
    const container = c.cadex_box_new() orelse return;
    const label_box = c.cadex_box_new_h(4) orelse return;
    const title_label = c.cadex_label_new(title.ptr) orelse return;
    c.cadex_label_ellipsize(title_label);
    c.cadex_widget_set_size(title_label, 160, -1);
    c.cadex_widget_add_class(label_box, "cadex-tab-label");
    c.cadex_box_append(label_box, title_label);
    c.cadex_box_append(label_box, c.cadex_button_new("×", tabCloseClicked, tab) orelse return);
    tab.* = .{
        .app = app,
        .space = currentSpace(app),
        .container = container,
        .content = undefined,
        .label_box = label_box,
        .title_label = title_label,
        .kind = .document,
    };
    const doc = gpa.create(Doc) catch return;
    doc.* = .{
        .app = app,
        .tab = tab,
        .path = path_copy,
        .title = title,
        .view = undefined,
        .buffer = undefined,
        .scroll = undefined,
        .language = if (file) "PDF" else "Web",
        .virtual = true,
        .media = true,
    };
    tab.doc = doc;
    const header = c.cadex_box_new_h(6) orelse return;
    c.cadex_widget_add_class(header, "cadex-doc-header");
    const doc_title = c.cadex_label_new(title.ptr) orelse return;
    c.cadex_label_ellipsize(doc_title);
    c.cadex_widget_expand_h(doc_title);
    c.cadex_box_append(header, doc_title);
    const pick = c.cadex_adw_icon_button("edit-find-symbolic", webPickClicked, doc) orelse return;
    c.cadex_widget_set_tooltip(pick, "Pick an element");
    c.cadex_box_append(header, pick);
    const web_close = c.cadex_adw_icon_button("window-close-symbolic", tabCloseClicked, tab) orelse return;
    c.cadex_widget_set_tooltip(web_close, "Close tab");
    c.cadex_box_append(header, web_close);
    c.cadex_box_append(container, header);
    const webview = c.cadex_webview_new() orelse return;
    _ = c.cadex_webview_enable_picker(webview, onPickMessage, doc);
    if (file) {
        c.cadex_webview_load_file(webview, source.ptr);
    } else {
        c.cadex_webview_load_uri(webview, source.ptr);
    }
    doc.view = webview;
    doc.scroll = webview;
    c.cadex_widget_expand(webview);
    c.cadex_box_append(container, webview);
    tab.content = webview;
    c.cadex_notebook_append(tab.space.notebook, container, label_box);
    tab.space.tabs.append(gpa, tab) catch return;
    c.cadex_notebook_set_current(tab.space.notebook, @intCast(tab.space.tabs.items.len - 1));
    app.active_doc = doc;
    app.focused = null;
    updateTitle(app);
    updateStatus(app);
    openPage(app, .terminal);
}

fn webPickClicked(user: ?*anyopaque) callconv(.c) void {
    const doc: *Doc = @ptrCast(@alignCast(user.?));
    c.cadex_webview_set_picking(doc.view, 1);
    showMessage(doc.app, "Click an element in the page");
}

fn onPickMessage(payload: [*c]const u8, user: ?*anyopaque) callconv(.c) void {
    const doc: *Doc = @ptrCast(@alignCast(user orelse return));
    if (payload == null) return;
    const text = std.mem.span(@as([*:0]const u8, @ptrCast(payload)));
    c.cadex_clipboard_set(doc.app.window, text.ptr);
    showMessage(doc.app, "Element copied to the clipboard");
}

fn openMediaTab(app: *App, path: [:0]const u8, title: []const u8, kind: MediaKind) void {
    const gpa = app.gpa;
    const tab = gpa.create(Tab) catch return;
    const path_copy = gpa.dupeZ(u8, path) catch return;
    const title_copy = gpa.dupeZ(u8, title) catch return;
    const container = c.cadex_box_new() orelse return;
    const label_box = c.cadex_box_new_h(4) orelse return;
    const title_label = c.cadex_label_new(title_copy.ptr) orelse return;
    c.cadex_label_ellipsize(title_label);
    c.cadex_widget_set_size(title_label, 160, -1);
    c.cadex_widget_add_class(label_box, "cadex-tab-label");
    c.cadex_box_append(label_box, title_label);
    c.cadex_box_append(label_box, c.cadex_button_new("×", tabCloseClicked, tab) orelse return);
    tab.* = .{
        .app = app,
        .space = currentSpace(app),
        .container = container,
        .content = undefined,
        .label_box = label_box,
        .title_label = title_label,
        .kind = .document,
    };
    const doc = gpa.create(Doc) catch return;
    doc.* = .{
        .app = app,
        .tab = tab,
        .path = path_copy,
        .title = title_copy,
        .view = undefined,
        .buffer = undefined,
        .scroll = undefined,
        .language = switch (kind) {
            .image => "Image",
            .video => "Video",
            .audio => "Audio",
            .none => "Media",
        },
        .virtual = true,
        .media = true,
    };
    tab.doc = doc;

    const header = c.cadex_box_new_h(6) orelse return;
    c.cadex_widget_add_class(header, "cadex-doc-header");
    const doc_title = c.cadex_label_new(title_copy.ptr) orelse return;
    c.cadex_label_ellipsize(doc_title);
    c.cadex_widget_expand_h(doc_title);
    c.cadex_box_append(header, doc_title);
    c.cadex_box_append(header, c.cadex_button_new("×", tabCloseClicked, tab) orelse return);
    c.cadex_box_append(container, header);

    const content: *anyopaque = switch (kind) {
        .image => c.cadex_picture_new(path.ptr),
        .video, .audio => c.cadex_video_new(path.ptr),
        .none => null,
    } orelse {
        showMessage(app, "Could not open this media file");
        return;
    };
    doc.view = content;
    doc.scroll = content;
    c.cadex_widget_expand(content);
    c.cadex_box_append(container, content);
    tab.content = content;
    c.cadex_notebook_append(tab.space.notebook, container, label_box);
    tab.space.tabs.append(gpa, tab) catch return;
    c.cadex_notebook_set_current(tab.space.notebook, @intCast(tab.space.tabs.items.len - 1));
    app.active_doc = doc;
    app.focused = null;
    updateTitle(app);
    updateStatus(app);
    openPage(app, .terminal);
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
        doc.save_button = c.cadex_adw_icon_button("document-save-symbolic", docSaveClicked, doc) orelse return error.GtkFailed;
        c.cadex_widget_set_tooltip(doc.save_button.?, "Save");
        c.cadex_box_append(header, doc.save_button.?);
    }
    if (markdown) {
        doc.notes_button = c.cadex_adw_icon_button("view-list-symbolic", docNotesClicked, doc) orelse return error.GtkFailed;
        c.cadex_widget_set_tooltip(doc.notes_button.?, "Headings and backlinks");
        c.cadex_box_append(header, doc.notes_button.?);
        doc.preview_button = c.cadex_adw_icon_button("view-conceal-symbolic", docPreviewClicked, doc) orelse return error.GtkFailed;
        c.cadex_widget_set_tooltip(doc.preview_button.?, "Hide preview");
        c.cadex_box_append(header, doc.preview_button.?);
    }
    c.cadex_box_append(header, c.cadex_adw_icon_button("window-close-symbolic", tabCloseClicked, tab) orelse return error.GtkFailed);
    c.cadex_box_append(container, header);

    const view = c.cadex_text_view_new() orelse return error.GtkFailed;
    doc.view = view;
    doc.buffer = c.cadex_text_view_buffer(view) orelse return error.GtkFailed;
    c.cadex_text_view_set_editable(view, @intFromBool(!virtual and markdown));
    c.cadex_text_view_set_wrap(view, @intFromBool(markdown));
    c.cadex_text_view_set_text(view, text.ptr, text.len);
    const editor_box = c.cadex_text_view_with_gutter(view) orelse view;
    const scroller = c.cadex_scrolled_new(editor_box) orelse return error.GtkFailed;
    doc.scroll = scroller;
    var content: *anyopaque = scroller;
    if (markdown) {
        const paned = c.cadex_paned_new(HORIZONTAL) orelse return error.GtkFailed;
        if (c.cadex_webkit_available() != 0) {
            const webview = c.cadex_webview_new() orelse return error.GtkFailed;
            doc.preview_view = webview;
            doc.preview_scroll = webview;
            c.cadex_paned_set_end(paned, webview);
        } else {
            const preview_label = c.cadex_label_new("") orelse return error.GtkFailed;
            c.cadex_label_set_wrap(preview_label, 1);
            c.cadex_label_set_selectable(preview_label, 1);
            c.cadex_widget_set_valign(preview_label, 0);
            c.cadex_widget_add_class(preview_label, "cadex-preview");
            const preview_scroll = c.cadex_scrolled_new(preview_label) orelse return error.GtkFailed;
            doc.preview_label = preview_label;
            doc.preview_scroll = preview_scroll;
            c.cadex_paned_set_end(paned, preview_scroll);
        }
        c.cadex_paned_set_start(paned, scroller);
        c.cadex_paned_set_position(paned, 520);
        content = paned;
    }
    tab.content = content;
    c.cadex_widget_expand(container);
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
    openPage(app, .terminal);
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
    c.cadex_notebook_set_title(doc.tab.space.notebook, doc.tab.container, label.ptr);
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

fn docNotesClicked(user: ?*anyopaque) callconv(.c) void {
    const doc: *Doc = @ptrCast(@alignCast(user.?));
    notesOpen(doc);
}

fn clearNoteRows(app: *App) void {
    for (app.notes_rows.items) |row| {
        if (row.path) |path| app.gpa.free(path);
    }
    app.notes_rows.clearRetainingCapacity();
}

fn notesOpen(doc: *Doc) void {
    const app = doc.app;
    app.notes_doc = doc;
    app.notes_tries = 0;
    if (app.notes_window == null) {
        const window = c.cadex_window_new_dialog(app.window, "Notes", 520, 520) orelse return;
        c.cadex_window_hide_on_close(window);
        c.cadex_widget_on_escape(window, notesHide, app);
        const box = c.cadex_box_new() orelse return;
        c.cadex_widget_set_margins(box, 12, 12, 12, 12);
        const title = c.cadex_label_new("Headings and backlinks") orelse return;
        c.cadex_widget_add_class(title, "heading");
        c.cadex_box_append(box, title);
        const list = c.cadex_listbox_new() orelse return;
        c.cadex_widget_add_class(list, "boxed-list");
        c.cadex_listbox_on_activated(list, notesRowActivated, app);
        c.cadex_listbox_on_keys(list, notesRowActivated, app);
        const scrolled = c.cadex_scrolled_new(list) orelse return;
        c.cadex_widget_expand(scrolled);
        c.cadex_box_append(box, scrolled);
        const close_button = c.cadex_button_new("Close", notesHide, app) orelse return;
        c.cadex_widget_set_halign(close_button, 2);
        c.cadex_widget_set_margins(close_button, 0, 0, 8, 0);
        c.cadex_box_append(box, close_button);
        c.cadex_window_child(window, box);
        app.notes_window = window;
        app.notes_list = list;
    }
    refreshNotes(app);
    if (app.notes_window) |window| c.cadex_window_present(window, 0);
    if (app.notes_list) |list| c.cadex_listbox_focus_first(list);
}

fn refreshNotes(app: *App) void {
    const list = app.notes_list orelse return;
    const doc = app.notes_doc orelse return;
    c.cadex_listbox_clear(list);
    clearNoteRows(app);
    if (app.notes_index == null) {
        var index: ?*core.cadex_markdown_index = null;
        if (core.cadex_markdown_index_open(app.root.ptr, &index) != core.CADEX_OK or index == null) {
            c.cadex_listbox_append(list, "No Markdown index");
            return;
        }
        app.notes_index = index;
    }
    const index = app.notes_index.?;
    if (!core.cadex_markdown_index_ready(index)) {
        if (app.notes_tries < 20) {
            app.notes_tries += 1;
            c.cadex_listbox_append(list, "Indexing…");
            _ = c.cadex_timeout(250, notesRetry, app);
        } else {
            c.cadex_listbox_append(list, "Index is not ready");
        }
        return;
    }
    if (std.fs.path.dirname(doc.path)) |folder| {
        const folder_z = app.gpa.dupeZ(u8, folder) catch null;
        if (folder_z) |z| {
            defer app.gpa.free(z);
            core.cadex_markdown_index_focus(index, z.ptr);
        }
    }
    var headings_out: ?[*]u8 = null;
    var headings_len: usize = 0;
    if (core.cadex_markdown_headings(index, doc.path.ptr, &headings_out, &headings_len) == core.CADEX_OK and headings_out != null) {
        defer core.cadex_free(@ptrCast(headings_out.?));
        var lines = std.mem.splitScalar(u8, headings_out.?[0..headings_len], '\n');
        while (lines.next()) |line| {
            if (line.len == 0) continue;
            var fields = std.mem.splitScalar(u8, line, '\t');
            const level = fields.next() orelse "1";
            const line_text = fields.next() orelse "1";
            const anchor = fields.next() orelse "";
            _ = anchor;
            const text = fields.next() orelse "";
            const number = std.fmt.parseInt(usize, line_text, 10) catch 1;
            app.notes_rows.append(app.gpa, .{ .kind = .heading, .line = number }) catch continue;
            const label = std.fmt.allocPrintSentinel(app.gpa, "{s}", .{text}, 0) catch continue;
            defer app.gpa.free(label);
            const subtitle = std.fmt.allocPrintSentinel(app.gpa, "Heading {s} · line {d}", .{ level, number }, 0) catch continue;
            defer app.gpa.free(subtitle);
            c.cadex_listbox_append_action(list, "text-x-generic-symbolic", label.ptr, subtitle.ptr);
        }
    }
    var backlinks_out: ?[*]u8 = null;
    var backlinks_len: usize = 0;
    if (core.cadex_markdown_backlinks(index, doc.path.ptr, &backlinks_out, &backlinks_len) == core.CADEX_OK and backlinks_out != null) {
        defer core.cadex_free(@ptrCast(backlinks_out.?));
        var lines = std.mem.splitScalar(u8, backlinks_out.?[0..backlinks_len], '\n');
        while (lines.next()) |line| {
            if (line.len == 0) continue;
            var fields = std.mem.splitScalar(u8, line, '\t');
            const path = fields.next() orelse continue;
            const line_text = fields.next() orelse "1";
            const path_z = app.gpa.dupeZ(u8, path) catch continue;
            const number = std.fmt.parseInt(usize, line_text, 10) catch 1;
            app.notes_rows.append(app.gpa, .{ .kind = .backlink, .line = number, .path = path_z }) catch {
                app.gpa.free(path_z);
                continue;
            };
            const label = std.fmt.allocPrintSentinel(app.gpa, "{s}", .{std.fs.path.basename(path)}, 0) catch continue;
            defer app.gpa.free(label);
            const subtitle = std.fmt.allocPrintSentinel(app.gpa, "Backlink · line {d}", .{number}, 0) catch continue;
            defer app.gpa.free(subtitle);
            c.cadex_listbox_append_action(list, "insert-link-symbolic", label.ptr, subtitle.ptr);
        }
    }
    if (app.notes_rows.items.len == 0) c.cadex_listbox_append(list, "No headings or backlinks");
}

fn notesRetry(user: ?*anyopaque) callconv(.c) void {
    const app: *App = @ptrCast(@alignCast(user.?));
    if (app.closing or app.notes_window == null or app.notes_doc == null) return;
    refreshNotes(app);
}

fn notesRowActivated(index: c_int, user: ?*anyopaque) callconv(.c) void {
    const app: *App = @ptrCast(@alignCast(user.?));
    if (index < 0) return;
    const at: usize = @intCast(index);
    if (at >= app.notes_rows.items.len) return;
    const row = app.notes_rows.items[at];
    switch (row.kind) {
        .heading => {
            if (app.notes_doc) |doc| c.cadex_text_view_scroll_to_line(doc.view, @intCast(row.line -| 1));
        },
        .backlink => {
            if (row.path) |path| {
                if (app.notes_window) |window| c.cadex_window_hide(window);
                openDocument(app, path, row.line -| 1);
            }
        },
    }
}

fn notesHide(user: ?*anyopaque) callconv(.c) void {
    const app: *App = @ptrCast(@alignCast(user.?));
    if (app.notes_window) |window| c.cadex_window_hide(window);
}

fn togglePreview(doc: *Doc) void {
    const preview = doc.preview_scroll orelse return;
    doc.preview_visible = !doc.preview_visible;
    c.cadex_widget_visible(preview, @intFromBool(doc.preview_visible));
    if (doc.preview_button) |button| {
        c.cadex_button_set_icon(button, if (doc.preview_visible) "view-conceal-symbolic" else "view-reveal-symbolic");
        c.cadex_widget_set_tooltip(button, if (doc.preview_visible) "Hide preview" else "Show preview");
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

fn searchCancelClicked(user: ?*anyopaque) callconv(.c) void {
    const app: *App = @ptrCast(@alignCast(user.?));
    if (app.search_content) |handle| {
        core.cadex_search_content_cancel(handle);
        app.search_content = null;
    }
    clearSearchHits(app, true);
    app.search_mode = .files;
    app.search_done = false;
    c.cadex_label_set(app.search_status, "Cancelled");
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
        c.cadex_listbox_append_action(app.search_list, "text-x-generic-symbolic", label.ptr, "File");
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
    options.case_sensitive = app.search_case;
    options.regex = app.search_regex;
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
        const title = std.fmt.allocPrintSentinel(app.gpa, "{s}", .{hit.path}, 0) catch continue;
        defer app.gpa.free(title);
        const subtitle = if (hit.line > 0)
            std.fmt.allocPrintSentinel(app.gpa, "{d} · {s}", .{ hit.line, clean }, 0) catch continue
        else
            app.gpa.dupeZ(u8, "File") catch continue;
        defer app.gpa.free(subtitle);
        const icon: [*:0]const u8 = if (hit.line > 0) "system-search-symbolic" else "text-x-generic-symbolic";
        c.cadex_listbox_append_action(app.search_list, icon, title.ptr, subtitle.ptr);
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
    const text = std.mem.span(name);
    const page: Page = if (std.mem.eql(u8, text, "files"))
        .files
    else if (std.mem.eql(u8, text, "search"))
        .search
    else if (std.mem.eql(u8, text, "git"))
        .git
    else if (std.mem.eql(u8, text, "history"))
        .history
    else if (std.mem.eql(u8, text, "agents"))
        .agents
    else if (std.mem.eql(u8, text, "ssh"))
        .ssh
    else
        .terminal;
    openPage(app, page);
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
        const title = std.fmt.allocPrintSentinel(app.gpa, "{s}{s}{s}", .{
            file.path,
            if (file.orig.len > 0) " ← " else "",
            file.orig,
        }, 0) catch continue;
        defer app.gpa.free(title);
        const subtitle = std.fmt.allocPrintSentinel(app.gpa, "{c}{c}", .{ file.x, file.y }, 0) catch continue;
        defer app.gpa.free(subtitle);
        const icon: [*:0]const u8 = if (file.kind == 3) "list-add-symbolic" else if (file.kind == 2) "dialog-warning-symbolic" else "text-x-generic-symbolic";
        c.cadex_listbox_append_action(app.git_list, icon, title.ptr, subtitle.ptr);
    }
}

fn gitSideDiffClicked(user: ?*anyopaque) callconv(.c) void {
    const app: *App = @ptrCast(@alignCast(user.?));
    const index = app.git_selected orelse {
        showMessage(app, "Select a file first");
        return;
    };
    openSideDiff(app, index);
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

fn openSideDiff(app: *App, index: usize) void {
    const repo = app.git_repo orelse return;
    const status = app.git_status_data orelse return;
    if (index >= status.files.len) return;
    const file = status.files[index];
    const path_z = app.gpa.dupeZ(u8, file.path) catch return;
    defer app.gpa.free(path_z);
    const orig_z: ?[:0]u8 = if (file.orig.len > 0) app.gpa.dupeZ(u8, file.orig) catch null else null;
    defer if (orig_z) |orig| app.gpa.free(orig);
    var sides = std.mem.zeroes(core.cadex_git_diff_sides);
    const rc = core.cadex_git_diff(repo.ptr, path_z.ptr, if (orig_z) |orig| orig.ptr else null, status.staged(index), &sides);
    defer if (rc == core.CADEX_OK) core.cadex_git_diff_free(&sides);
    const before = if (rc == core.CADEX_OK and sides.before != null) sides.before[0..sides.before_len] else "";
    var after = if (rc == core.CADEX_OK and sides.after != null) sides.after[0..sides.after_len] else "";
    var fallback: ?[*]u8 = null;
    var fallback_len: usize = 0;
    if (after.len == 0 and core.cadex_explorer_read_text(path_z.ptr, 0, &fallback, &fallback_len) == core.CADEX_OK and fallback != null) {
        defer core.cadex_free(@ptrCast(fallback.?));
        after = fallback.?[0..fallback_len];
    }
    var title_buf: [300]u8 = undefined;
    const title = std.fmt.bufPrint(&title_buf, "diff (side): {s}", .{file.path}) catch "diff (side)";
    openSideBySideTab(app, title, before, after);
}

fn openSideBySideTab(app: *App, title: []const u8, before: []const u8, after: []const u8) void {
    const gpa = app.gpa;
    const tab = gpa.create(Tab) catch return;
    const path_copy = gpa.dupeZ(u8, "") catch return;
    const title_copy = gpa.dupeZ(u8, title) catch return;
    const container = c.cadex_box_new() orelse return;
    const label_box = c.cadex_box_new_h(4) orelse return;
    const title_label = c.cadex_label_new(title_copy.ptr) orelse return;
    c.cadex_label_ellipsize(title_label);
    c.cadex_widget_set_size(title_label, 160, -1);
    c.cadex_widget_add_class(label_box, "cadex-tab-label");
    c.cadex_box_append(label_box, title_label);
    c.cadex_box_append(label_box, c.cadex_button_new("×", tabCloseClicked, tab) orelse return);
    tab.* = .{
        .app = app,
        .space = currentSpace(app),
        .container = container,
        .content = undefined,
        .label_box = label_box,
        .title_label = title_label,
        .kind = .document,
    };
    const doc = gpa.create(Doc) catch return;
    doc.* = .{
        .app = app,
        .tab = tab,
        .path = path_copy,
        .title = title_copy,
        .view = undefined,
        .buffer = undefined,
        .scroll = undefined,
        .language = "Diff",
        .virtual = true,
        .media = true,
    };
    tab.doc = doc;
    const header = c.cadex_box_new_h(6) orelse return;
    c.cadex_widget_add_class(header, "cadex-doc-header");
    const doc_title = c.cadex_label_new(title_copy.ptr) orelse return;
    c.cadex_label_ellipsize(doc_title);
    c.cadex_widget_expand_h(doc_title);
    c.cadex_box_append(header, doc_title);
    c.cadex_box_append(header, c.cadex_button_new("×", tabCloseClicked, tab) orelse return);
    c.cadex_box_append(container, header);
    const paned = c.cadex_paned_new(HORIZONTAL) orelse return;
    const before_view = makeTextView(before, "Before") orelse return;
    const after_view = makeTextView(after, "After") orelse return;
    c.cadex_paned_set_start(paned, before_view);
    c.cadex_paned_set_end(paned, after_view);
    c.cadex_paned_set_position(paned, 440);
    doc.view = before_view;
    doc.scroll = paned;
    c.cadex_widget_expand(paned);
    c.cadex_box_append(container, paned);
    tab.content = paned;
    c.cadex_notebook_append(tab.space.notebook, container, label_box);
    tab.space.tabs.append(gpa, tab) catch return;
    c.cadex_notebook_set_current(tab.space.notebook, @intCast(tab.space.tabs.items.len - 1));
    app.active_doc = doc;
    app.focused = null;
    updateTitle(app);
    updateStatus(app);
    openPage(app, .terminal);
}

fn makeTextView(text: []const u8, label: []const u8) ?*anyopaque {
    const box = c.cadex_box_new() orelse return null;
    const heading = c.cadex_label_new(@ptrCast(label.ptr)) orelse return null;
    c.cadex_widget_add_class(heading, "cadex-doc-header");
    c.cadex_box_append(box, heading);
    const view = c.cadex_text_view_new() orelse return null;
    c.cadex_text_view_set_editable(view, 0);
    c.cadex_text_view_set_wrap(view, 0);
    c.cadex_text_view_set_text(view, text.ptr, text.len);
    const with_gutter = c.cadex_text_view_with_gutter(view) orelse view;
    const scrolled = c.cadex_scrolled_new(with_gutter) orelse return null;
    c.cadex_widget_expand(scrolled);
    c.cadex_box_append(box, scrolled);
    return box;
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

fn gitBranchesClicked(user: ?*anyopaque) callconv(.c) void {
    const app: *App = @ptrCast(@alignCast(user.?));
    branchOpen(app);
}

fn gitInitClicked(user: ?*anyopaque) callconv(.c) void {
    const app: *App = @ptrCast(@alignCast(user.?));
    gitInit(app);
}

fn clearBranches(app: *App) void {
    for (app.branch_names.items) |name| app.gpa.free(name);
    app.branch_names.clearRetainingCapacity();
}

fn branchOpen(app: *App) void {
    if (app.branch_window == null) {
        const window = c.cadex_window_new_dialog(app.window, "Branches", 420, 460) orelse return;
        c.cadex_window_hide_on_close(window);
        c.cadex_widget_on_escape(window, branchHide, app);
        const box = c.cadex_box_new() orelse return;
        c.cadex_widget_set_margins(box, 12, 12, 12, 12);
        const title = c.cadex_label_new("Local branches") orelse return;
        c.cadex_widget_add_class(title, "heading");
        c.cadex_box_append(box, title);
        const list = c.cadex_listbox_new() orelse return;
        c.cadex_widget_add_class(list, "boxed-list");
        c.cadex_listbox_on_activated(list, branchRowActivated, app);
        c.cadex_listbox_on_keys(list, branchRowActivated, app);
        const scrolled = c.cadex_scrolled_new(list) orelse return;
        c.cadex_widget_expand(scrolled);
        c.cadex_box_append(box, scrolled);
        const close_button = c.cadex_button_new("Close", branchHide, app) orelse return;
        c.cadex_widget_set_halign(close_button, 2);
        c.cadex_widget_set_margins(close_button, 0, 0, 8, 0);
        c.cadex_box_append(box, close_button);
        c.cadex_window_child(window, box);
        app.branch_window = window;
        app.branch_list = list;
    }
    refreshBranches(app);
    if (app.branch_window) |window| c.cadex_window_present(window, 0);
    if (app.branch_list) |list| c.cadex_listbox_focus_first(list);
}

fn refreshBranches(app: *App) void {
    const list = app.branch_list orelse return;
    c.cadex_listbox_clear(list);
    clearBranches(app);
    const repo = app.git_repo orelse {
        c.cadex_listbox_append(list, "No git repository");
        return;
    };
    var out: ?[*]u8 = null;
    var len: usize = 0;
    if (core.cadex_git_branches(repo.ptr, &out, &len) != core.CADEX_OK or out == null) {
        c.cadex_listbox_append(list, "Could not list branches");
        return;
    }
    defer core.cadex_free(@ptrCast(out.?));
    var lines = std.mem.splitScalar(u8, out.?[0..len], '\n');
    while (lines.next()) |line| {
        if (line.len == 0) continue;
        var fields = std.mem.splitScalar(u8, line, '\t');
        const kind = fields.next() orelse continue;
        if (!std.mem.eql(u8, kind, "local")) continue;
        const name = fields.next() orelse continue;
        const copy = app.gpa.dupe(u8, name) catch continue;
        app.branch_names.append(app.gpa, copy) catch {
            app.gpa.free(copy);
            continue;
        };
        const current = if (app.git_status_data) |status| std.mem.eql(u8, status.branch, name) else false;
        const label = app.gpa.dupeZ(u8, name) catch continue;
        defer app.gpa.free(label);
        c.cadex_listbox_append_action(list, "view-list-symbolic", label.ptr, if (current) "Current branch" else "Local branch");
    }
}

fn branchRowActivated(index: c_int, user: ?*anyopaque) callconv(.c) void {
    const app: *App = @ptrCast(@alignCast(user.?));
    if (index < 0) return;
    const at: usize = @intCast(index);
    if (at >= app.branch_names.items.len) return;
    const repo = app.git_repo orelse return;
    const z = app.gpa.dupeZ(u8, app.branch_names.items[at]) catch return;
    defer app.gpa.free(z);
    var message: ?[*]u8 = null;
    var len: usize = 0;
    const status = core.cadex_git_switch(repo.ptr, z.ptr, false, &message, &len);
    if (app.branch_window) |window| c.cadex_window_hide(window);
    finishGit(app, status, message, len, "Branch switched");
}

fn branchHide(user: ?*anyopaque) callconv(.c) void {
    const app: *App = @ptrCast(@alignCast(user.?));
    if (app.branch_window) |window| c.cadex_window_hide(window);
}

fn gitInit(app: *App) void {
    var message: ?[*]u8 = null;
    var len: usize = 0;
    const status = core.cadex_git_init(app.root.ptr, &message, &len);
    finishGit(app, status, message, len, "Repository initialized");
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
            const title = std.fmt.allocPrintSentinel(app.gpa, "{s}", .{record.subject}, 0) catch {
                documents.git.freeCommit(app.gpa, record);
                continue;
            };
            defer app.gpa.free(title);
            const subtitle = std.fmt.allocPrintSentinel(app.gpa, "{s} · {s}", .{ short, record.author }, 0) catch {
                documents.git.freeCommit(app.gpa, record);
                continue;
            };
            defer app.gpa.free(subtitle);
            c.cadex_listbox_append_action(app.history_list, "document-open-recent-symbolic", title.ptr, subtitle.ptr);
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
    app.history_selected = at;
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

fn trayActivated(user: ?*anyopaque) callconv(.c) void {
    const app: *App = @ptrCast(@alignCast(user orelse return));
    c.cadex_window_present(app.window, 0);
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
            for (tab.leaves.items) |pane| {
                pane.closed = true;
                if (pane.term) |term| {
                    term.close(app.gpa);
                    pane.term = null;
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
    c.cadex_notebook_on_close(space.notebook, onTabBarClose, space);
    c.cadex_widget_expand(space.notebook);
    c.cadex_stack_add(app.spaces_stack, space.notebook, space.name.ptr);
    try app.spaces.append(gpa, space);
    switchSpace(app, app.spaces.items.len - 1);
    try newTab(app, space);
    saveSpaces(app);
}

fn switchSpace(app: *App, index: usize) void {
    if (index >= app.spaces.items.len) return;
    app.space_index = index;
    const space = app.spaces.items[index];
    c.cadex_stack_set(app.spaces_stack, space.name.ptr);
    updateHeaderTabs(app, space);
    if (space.tabs.items.len > 0) {
        const page: usize = @intCast(@max(0, c.cadex_notebook_current(space.notebook)));
        activateTab(app, space.tabs.items[@min(page, space.tabs.items.len - 1)]);
    } else {
        app.active_doc = null;
        app.focused = null;
    }
    updateTitle(app);
    updateStatus(app);
    saveSpaces(app);
}

fn activateTab(app: *App, tab: *Tab) void {
    if (tab.kind == .document) {
        const doc = tab.doc orelse return;
        app.active_doc = doc;
        app.focused = null;
        c.cadex_widget_focus(doc.view);
    } else {
        app.active_doc = null;
        if (tab.leaves.items.len > 0) {
            const pane = tab.leaves.items[0];
            app.focused = pane;
            c.cadex_widget_focus(pane.area);
        } else {
            app.focused = null;
        }
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
    tab.root = pane.node;
    try tab.leaves.append(gpa, pane);
    tab.content = pane.container;
    c.cadex_widget_expand(tab.container);
    c.cadex_widget_expand(pane.container);
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
    saveSpaces(app);
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
    pane.node = try gpa.create(Node);
    pane.node.* = .{ .kind = .leaf, .pane = pane };
    pane.container = c.cadex_box_new() orelse return error.GtkFailed;
    const header = c.cadex_box_new_h(4) orelse return error.GtkFailed;
    c.cadex_widget_add_class(header, "cadex-pane-header");
    pane.header_box = header;
    c.cadex_widget_visible(header, 0);
    pane.header_label = c.cadex_label_new("Terminal") orelse return error.GtkFailed;
    c.cadex_label_ellipsize(pane.header_label);
    c.cadex_box_append(header, pane.header_label);
    c.cadex_box_append(header, c.cadex_adw_icon_button("window-close-symbolic", paneCloseClicked, pane) orelse return error.GtkFailed);
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

/// Blend `a` into `b`; `a_pct` is the weight of `a` (0..100).
fn mixColor(a: u32, b: u32, a_pct: u32) u32 {
    const ar = (a >> 16) & 0xff;
    const ag = (a >> 8) & 0xff;
    const ab = a & 0xff;
    const br = (b >> 16) & 0xff;
    const bg = (b >> 8) & 0xff;
    const bb = b & 0xff;
    const r = (ar * a_pct + br * (100 - a_pct)) / 100;
    const g = (ag * a_pct + bg * (100 - a_pct)) / 100;
    const bl = (ab * a_pct + bb * (100 - a_pct)) / 100;
    return (r << 16) | (g << 8) | bl;
}

fn interfaceColors(theme: Theme) Interface {
    if (theme.interface) |ui| return ui;
    const bg = theme.background;
    const fg = theme.foreground;
    if (theme.dark) {
        return .{
            .chrome = mixColor(bg, 0x000000, 72),
            .panel = mixColor(bg, 0xffffff, 94),
            .panel_border = mixColor(bg, fg, 86),
            .tab_active = mixColor(bg, fg, 74),
            .field = mixColor(bg, fg, 90),
            .text = fg,
            .secondary_text = mixColor(fg, bg, 58),
            .accent = theme.ansi[4],
        };
    }
    return .{
        .chrome = mixColor(bg, 0xffffff, 68),
        .panel = bg,
        .panel_border = mixColor(bg, fg, 84),
        .tab_active = mixColor(bg, fg, 78),
        .field = mixColor(bg, fg, 92),
        .text = fg,
        .secondary_text = mixColor(fg, bg, 58),
        .accent = theme.ansi[4],
    };
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
    var z: [:0]u8 = undefined;
    if (term.copyWorkingDirectory(app.gpa)) |cwd| {
        defer app.gpa.free(cwd);
        const base = std.fs.path.basename(cwd);
        z = app.gpa.dupeZ(u8, if (base.len > 0) base else "Terminal") catch return;
    } else {
        z = app.gpa.dupeZ(u8, if (title.len > 0) title else "Terminal") catch return;
    }
    if (pane.title.len > 0) app.gpa.free(pane.title);
    pane.title = z;
    c.cadex_label_set(pane.header_label, z.ptr);
    c.cadex_label_set(pane.tab.title_label, z.ptr);
    c.cadex_notebook_set_title(pane.tab.space.notebook, pane.tab.container, z.ptr);
    if (app.focused == pane) updateTitle(app);
    updateStatus(app);
}

fn onBell(user: ?*anyopaque) callconv(.c) void {
    const pane: *Pane = @ptrCast(@alignCast(user.?));
    c.cadex_idle(paneBellIdle, pane);
}

fn paneBellIdle(user: ?*anyopaque) callconv(.c) void {
    const pane: *Pane = @ptrCast(@alignCast(user.?));
    if (pane.closed) return;
    c.cadex_beep(pane.area);
    if (c.cadex_window_is_active(pane.app.window) == 0) {
        c.cadex_notify("Cadex", pane.title.ptr);
    }
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
    updateChrome(app);
}

fn updateStatus(app: *App) void {
    updateChrome(app);
}

fn updateChrome(app: *App) void {
    if (app.closing or app.spaces.items.len == 0) return;
    const project = std.fs.path.basename(app.root);
    var title: []const u8 = project;
    if (app.page != .terminal) {
        title = pageName(app.page);
    } else if (app.active_doc) |doc| {
        title = doc.title;
    } else {
        title = "Terminal";
    }
    var title_z: [256]u8 = undefined;
    const title_text = std.fmt.bufPrintZ(&title_z, "{s}", .{title}) catch "Cadex";
    c.cadex_window_title(app.window, title_text.ptr);

    var folder_buf: [512]u8 = undefined;
    var folder: []const u8 = project;
    if (app.page == .terminal) {
        if (app.focused) |pane| {
            if (pane.term) |term| {
                if (term.copyWorkingDirectory(app.gpa)) |cwd| {
                    defer app.gpa.free(cwd);
                    if (std.mem.startsWith(u8, cwd, app.root)) {
                        const rel = std.mem.trim(u8, cwd[app.root.len..], "/");
                        folder = std.fmt.bufPrint(&folder_buf, "{s}{s}{s}", .{
                            project,
                            if (rel.len > 0) "/" else "",
                            rel,
                        }) catch project;
                    } else {
                        folder = std.fmt.bufPrint(&folder_buf, "{s}", .{cwd}) catch project;
                    }
                }
            }
        }
    }
    var project_z: [512]u8 = undefined;
    const project_text = std.fmt.bufPrintZ(&project_z, "{s}", .{folder}) catch "Cadex";
    c.cadex_label_set(app.cwd_label, project_text.ptr);
    if (app.branch_label) |label| {
        const branch = if (app.git_status_data) |status| status.branch else "";
        var branch_z: [256]u8 = undefined;
        const branch_text = std.fmt.bufPrintZ(&branch_z, "{s}", .{if (branch.len > 0) branch else "no branch"}) catch "no branch";
        c.cadex_label_set(label, branch_text.ptr);
    }
    if (app.page == .terminal) {
        const count = c.cadex_notebook_count(currentSpace(app).notebook);
        var tabs_z: [64]u8 = undefined;
        const tabs_text = std.fmt.bufPrintZ(&tabs_z, "{d} tab{s}", .{ count, if (count == 1) "" else "s" }) catch "1 tab";
        c.cadex_label_set(app.tabs_label, tabs_text.ptr);
        c.cadex_widget_visible(app.tabs_label, 1);
    } else {
        c.cadex_widget_visible(app.tabs_label, 0);
    }
}

fn updateHeaderTabs(app: *App, space: *Space) void {
    if (app.header_tabs) |bar| c.cadex_tab_bar_set_notebook(bar, space.notebook);
}

fn statusTimer(user: ?*anyopaque) callconv(.c) void {
    const app: *App = @ptrCast(@alignCast(user.?));
    updateTitle(app);
    updateStatus(app);
    updateStats(app);
    if (!app.closing) _ = c.cadex_timeout(1000, statusTimer, app);
}

fn readProc(app: *App, path: [*:0]const u8) ?[]u8 {
    var len: usize = 0;
    const raw = c.cadex_read_file(path, &len);
    if (raw == null) return null;
    defer c.cadex_gtk_free(@ptrCast(raw));
    return app.gpa.dupe(u8, raw[0..len]) catch null;
}

fn updateStats(app: *App) void {
    if (app.closing) return;
    var ram_pct: u32 = 0;
    if (readProc(app, "/proc/meminfo")) |meminfo| {
        defer app.gpa.free(meminfo);
        var total: u64 = 0;
        var available: u64 = 0;
        var lines = std.mem.splitScalar(u8, meminfo, '\n');
        while (lines.next()) |line| {
            if (std.mem.startsWith(u8, line, "MemTotal:")) total = firstNumber(line) orelse total;
            if (std.mem.startsWith(u8, line, "MemAvailable:")) available = firstNumber(line) orelse available;
        }
        if (total > 0 and available <= total) {
            ram_pct = @intCast((total - available) * 100 / total);
        }
    }
    var ports: u32 = 0;
    for ([_][*:0]const u8{ "/proc/net/tcp", "/proc/net/tcp6" }) |path| {
        if (readProc(app, path)) |table| {
            defer app.gpa.free(table);
            var lines = std.mem.splitScalar(u8, table, '\n');
            _ = lines.next();
            while (lines.next()) |line| {
                var fields = std.mem.tokenizeAny(u8, line, " \t");
                _ = fields.next();
                _ = fields.next();
                _ = fields.next();
                const state = fields.next() orelse continue;
                if (std.mem.eql(u8, state, "0A")) ports += 1;
            }
        }
    }
    var load: f64 = 0;
    if (readProc(app, "/proc/loadavg")) |loadavg| {
        defer app.gpa.free(loadavg);
        var tokens = std.mem.tokenizeAny(u8, loadavg, " \t");
        if (tokens.next()) |first| load = std.fmt.parseFloat(f64, first) catch 0;
    }
    if (app.stats_label) |label| {
        var buf: [128]u8 = undefined;
        const text = std.fmt.bufPrintZ(&buf, "RAM {d}%  ·  {d} ports  ·  load {d:.2}", .{ ram_pct, ports, load }) catch return;
        c.cadex_label_set(label, text.ptr);
    }
}

fn firstNumber(line: []const u8) ?u64 {
    var tokens = std.mem.tokenizeAny(u8, line, " \t");
    while (tokens.next()) |token| {
        if (std.fmt.parseInt(u64, token, 10)) |value| return value else |_| continue;
    }
    return null;
}

fn applyFont(app: *App) void {
    const z = std.fmt.bufPrintZ(&app.font, "Monospace {d}", .{app.settings.font_size}) catch return;
    c.cadex_text_set_font(z.ptr);
    updateMetrics(app);
    for (app.spaces.items) |space| {
        for (space.tabs.items) |tab| {
            for (tab.leaves.items) |pane| schedulePaneRedraw(pane);
        }
    }
    applyTheme(app);
}

fn updateMetrics(app: *App) void {
    for (app.spaces.items) |space| {
        for (space.tabs.items) |tab| {
            for (tab.leaves.items) |pane| {
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

fn applyTheme(app: *App) void {
    const theme = themes[app.theme_index];
    const ui = interfaceColors(theme);
    // The interface palette follows the theme (Caffeine by default), like the
    // macOS app, instead of only following the system accent.
    c.cadex_set_dark(@intFromBool(theme.dark));
    var css: std.ArrayList(u8) = .empty;
    defer css.deinit(app.gpa);
    appendFormatted(&css, app.gpa, ":root {{ --accent-color: #{x:0>6}; --accent-bg-color: #{x:0>6}; --accent-fg-color: #{x:0>6}; }}\n" ++
        "@define-color accent_bg_color #{x:0>6};\n" ++
        "@define-color accent_fg_color #{x:0>6};\n" ++
        "@define-color accent_color #{x:0>6};\n" ++
        "@define-color window_bg_color #{x:0>6};\n" ++
        "@define-color window_fg_color #{x:0>6};\n" ++
        "@define-color view_bg_color #{x:0>6};\n" ++
        "@define-color view_fg_color #{x:0>6};\n" ++
        "@define-color headerbar_bg_color #{x:0>6};\n" ++
        "@define-color headerbar_fg_color #{x:0>6};\n" ++
        "@define-color headerbar_border_color #{x:0>6};\n" ++
        "@define-color card_bg_color #{x:0>6};\n" ++
        "@define-color card_fg_color #{x:0>6};\n" ++
        "@define-color sidebar_bg_color #{x:0>6};\n" ++
        "@define-color sidebar_fg_color #{x:0>6};\n" ++
        "@define-color popover_bg_color #{x:0>6};\n" ++
        "@define-color popover_fg_color #{x:0>6};\n" ++
        "@define-color dialog_bg_color #{x:0>6};\n" ++
        "@define-color dialog_fg_color #{x:0>6};\n", .{
        ui.accent,       ui.accent, ui.chrome,
        ui.accent,       ui.chrome, ui.accent,
        ui.chrome,       ui.text,   ui.panel,
        ui.text,         ui.chrome, ui.text,
        ui.panel_border, ui.panel,  ui.text,
        ui.panel,        ui.text,   ui.field,
        ui.text,         ui.chrome, ui.text,
    });
    appendFormatted(&css, app.gpa, ".cadex-window {{ background-color: #{x:0>6}; color: #{x:0>6}; }}\n" ++
        ".cadex-titlebar {{ background-color: #{x:0>6}; color: #{x:0>6}; min-height: 38px; padding: 0 6px; border: none; box-shadow: none; }}\n" ++
        ".cadex-titlebar button {{ min-height: 26px; min-width: 26px; padding: 0 6px; border-radius: 6px; color: #{x:0>6}; }}\n" ++
        ".cadex-titlebar button:hover {{ background-color: #{x:0>6}; }}\n" ++
        ".cadex-tabbar {{ background: transparent; }}\n" ++
        ".cadex-tabbar .box {{ padding: 0; box-shadow: none; background: transparent; }}\n" ++
        ".cadex-tabbar tabbox {{ background: transparent; margin: 0 6px; padding: 0; min-height: 32px; }}\n" ++
        ".cadex-tabbar tab {{ background: transparent; color: #{x:0>6}; min-height: 24px; border-radius: 6px; padding: 2px 8px; }}\n" ++
        ".cadex-tabbar tab:hover {{ background-color: #{x:0>6}; color: #{x:0>6}; }}\n" ++
        ".cadex-tabbar tab:checked, .cadex-tabbar tab:selected {{ background-color: #{x:0>6}; color: #{x:0>6}; }}\n" ++
        ".cadex-tabbar expander {{ color: #{x:0>6}; }}\n" ++
        ".cadex-sidebar-panel {{ background-color: #{x:0>6}; border: 1px solid #{x:0>6}; border-radius: 10px; }}\n" ++
        ".cadex-content-panel {{ background-color: #{x:0>6}; border: 1px solid #{x:0>6}; border-radius: 10px; }}\n" ++
        ".cadex-status {{ background-color: #{x:0>6}; color: #{x:0>6}; min-height: 24px; padding: 1px 10px; border-top: 1px solid #{x:0>6}; }}\n" ++
        ".cadex-status label {{ font-size: 11px; color: #{x:0>6}; }}\n" ++
        ".cadex-status .cadex-status-strong {{ color: #{x:0>6}; }}\n" ++
        ".cadex-pane-header {{ background-color: #{x:0>6}; color: #{x:0>6}; padding: 2px 6px; border-bottom: 1px solid #{x:0>6}; }}\n", .{
        ui.chrome,         ui.text,
        ui.chrome,         ui.text,
        ui.text,           ui.field,
        ui.secondary_text, ui.field,
        ui.text,           ui.tab_active,
        ui.text,           ui.secondary_text,
        ui.panel,          ui.panel_border,
        ui.panel,          ui.panel_border,
        ui.chrome,         ui.secondary_text,
        ui.panel_border,   ui.secondary_text,
        ui.text,           ui.chrome,
        ui.secondary_text, ui.panel_border,
    });
    appendFormatted(&css, app.gpa, ".cadex-page {{ background: transparent; }}\n" ++
        ".cadex-page .heading, .cadex-page .title-4 {{ color: #{x:0>6}; }}\n" ++
        "entry, spinbutton, dropdown {{ background-color: #{x:0>6}; color: #{x:0>6}; }}\n" ++
        ".boxed-list {{ background-color: #{x:0>6}; border: 1px solid #{x:0>6}; border-radius: 8px; }}\n" ++
        ".boxed-list > row {{ background-color: transparent; color: #{x:0>6}; }}\n" ++
        "list.boxed-list row:selected {{ background-color: #{x:0>6}; color: #{x:0>6}; }}\n" ++
        ".cadex-sidebar-panel list.navigation-sidebar row:hover {{ background-color: #{x:0>6}; }}\n" ++
        ".cadex-sidebar-panel list.navigation-sidebar > row:selected {{ background-color: #{x:0>6}; color: #{x:0>6}; }}\n" ++
        "label.dim-label, .dim-label {{ color: #{x:0>6}; }}\n" ++
        "textview, textview text {{ font-family: monospace; font-size: {d}px; }}\n", .{
        ui.text,
        ui.field,
        ui.text,
        ui.panel,
        ui.panel_border,
        ui.text,
        ui.tab_active,
        ui.text,
        ui.field,
        ui.tab_active,
        ui.text,
        ui.secondary_text,
        app.settings.font_size,
    });
    const css_z = app.gpa.dupeZ(u8, css.items) catch return;
    defer app.gpa.free(css_z);
    c.cadex_css_apply(css_z.ptr);
    for (app.spaces.items) |space| {
        for (space.tabs.items) |tab| {
            for (tab.leaves.items) |pane| {
                if (pane.term) |term| {
                    var colors = themeColors(theme);
                    term.setColors(&colors);
                    term.setCursor(CURSOR_BLOCK, app.settings.cursor_blink);
                }
                schedulePaneRedraw(pane);
            }
        }
    }
    reapplyDocs(app);
}

fn reapplyDocs(app: *App) void {
    for (app.spaces.items) |space| {
        for (space.tabs.items) |tab| {
            const doc = tab.doc orelse continue;
            if (!doc.alive or doc.media) continue;
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
    if (app.split_view) |split| {
        c.cadex_adw_split_set_show_sidebar(split, @intFromBool(app.settings.sidebar));
    }
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
        'p', 'P' => if (alt) "power.toggle" else "sidebar.search",
        'g', 'G' => "sidebar.git",
        'h', 'H' => "sidebar.history",
        's', 'S' => "document.save",
        'm', 'M' => if (alt) "markdown.notes" else "document.preview",
        'u', 'U' => if (alt) "preview.url" else null,
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

fn nodeWidget(node: *Node) *anyopaque {
    return switch (node.kind) {
        .leaf => node.pane.?.container,
        .split => node.split.?.widget,
    };
}

fn firstLeaf(node: *Node) *Pane {
    var current = node;
    while (current.kind == .split) current = current.split.?.first;
    return current.pane.?;
}

fn freeTree(gpa: std.mem.Allocator, node: *Node) void {
    if (node.kind == .split) {
        if (node.split) |split| {
            freeTree(gpa, split.first);
            freeTree(gpa, split.second);
            gpa.destroy(split);
        }
    }
    gpa.destroy(node);
}

fn detachPane(app: *App, tab: *Tab, pane: *Pane) void {
    const node = pane.node;
    const parent = node.parent orelse {
        closeTab(tab);
        return;
    };
    const sibling = if (parent.first == node) parent.second else parent.first;
    const sibling_widget = nodeWidget(sibling);
    const parent_node = parent.node;
    const grand = parent_node.parent;

    for (tab.leaves.items, 0..) |item, i| {
        if (item == pane) {
            _ = tab.leaves.orderedRemove(i);
            break;
        }
    }

    // Take the surviving child out before the old GtkPaned is dropped.
    c.cadex_widget_ref(sibling_widget);
    if (parent.first == sibling) {
        c.cadex_paned_set_start(parent.widget, null);
    } else {
        c.cadex_paned_set_end(parent.widget, null);
    }
    c.cadex_widget_unparent(parent.widget);

    if (grand) |g| {
        const was_first = g.first == parent_node;
        if (was_first) {
            g.first = sibling;
        } else {
            g.second = sibling;
        }
        sibling.parent = g;
        if (was_first) {
            c.cadex_paned_set_start(g.widget, sibling_widget);
        } else {
            c.cadex_paned_set_end(g.widget, sibling_widget);
        }
    } else {
        sibling.parent = null;
        tab.root = sibling;
        c.cadex_box_append(tab.container, sibling_widget);
        tab.content = sibling_widget;
    }
    c.cadex_widget_unref(sibling_widget);

    app.gpa.destroy(parent);
    app.gpa.destroy(parent_node);
    app.gpa.destroy(node);

    if (tab.leaves.items.len == 1) c.cadex_widget_visible(tab.leaves.items[0].header_box, 0);
    const next = firstLeaf(sibling);
    app.focused = next;
    c.cadex_widget_focus(next.area);
    updateTitle(app);
    updateStatus(app);
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
    if (tab.leaves.items.len <= 1) {
        closeTab(tab);
        return;
    }
    detachPane(app, tab, pane);
}

fn closeTab(tab: *Tab) void {
    closeTabInternal(tab, true);
}

fn closeTabFromBar(tab: *Tab) void {
    closeTabInternal(tab, false);
}

fn closeTabInternal(tab: *Tab, remove_page: bool) void {
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
    for (tab.leaves.items) |pane| {
        pane.closed = true;
        if (pane.term) |term| {
            term.close(app.gpa);
            pane.term = null;
        }
    }
    tab.leaves.deinit(app.gpa);
    if (tab.root) |root| {
        freeTree(app.gpa, root);
        tab.root = null;
    }
    if (remove_page) {
        const index = c.cadex_notebook_page_num(tab.space.notebook, tab.container);
        if (index >= 0) c.cadex_notebook_remove(tab.space.notebook, index);
    }
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
    saveSpaces(app);
}

fn splitPane(pane: *Pane, orientation: c_int) void {
    const tab = pane.tab;
    if (tab.closed or pane.closed) return;
    const app = pane.app;
    const new = createPane(app, tab) catch {
        c.cadex_beep(pane.area);
        return;
    };
    const paned = c.cadex_paned_new(orientation) orelse return;
    const split = app.gpa.create(Split) catch return;
    const split_node = app.gpa.create(Node) catch return;
    const node = pane.node;
    split.* = .{
        .orientation = orientation,
        .widget = paned,
        .first = node,
        .second = new.node,
        .node = split_node,
    };
    split_node.* = .{ .parent = node.parent, .kind = .split, .split = split };
    new.node.parent = split;
    node.parent = split;

    const grand = split_node.parent;
    c.cadex_widget_ref(pane.container);
    c.cadex_widget_visible(pane.header_box, 1);
    c.cadex_widget_visible(new.header_box, 1);
    if (grand) |g| {
        const was_first = g.first == node;
        if (was_first) {
            c.cadex_paned_set_start(g.widget, null);
        } else {
            c.cadex_paned_set_end(g.widget, null);
        }
        c.cadex_paned_set_start(paned, pane.container);
        c.cadex_paned_set_end(paned, new.container);
        if (was_first) {
            g.first = split_node;
            c.cadex_paned_set_start(g.widget, paned);
        } else {
            g.second = split_node;
            c.cadex_paned_set_end(g.widget, paned);
        }
    } else {
        c.cadex_widget_unparent(pane.container);
        c.cadex_paned_set_start(paned, pane.container);
        c.cadex_paned_set_end(paned, new.container);
        c.cadex_box_append(tab.container, paned);
        tab.root = split_node;
    }
    c.cadex_widget_unref(pane.container);
    tab.content = nodeWidget(tab.root.?);
    tab.leaves.append(app.gpa, new) catch {};
    app.focused = new;
    c.cadex_widget_focus(new.area);
    updateTitle(app);
    updateStatus(app);
}

fn onTabBarClose(child: ?*anyopaque, user: ?*anyopaque) callconv(.c) void {
    const space: *Space = @ptrCast(@alignCast(user orelse return));
    const container = child orelse return;
    for (space.tabs.items) |tab| {
        if (tab.container == container) {
            closeTabFromBar(tab);
            return;
        }
    }
}

fn tabCloseClicked(user: ?*anyopaque) callconv(.c) void {
    const tab: *Tab = @ptrCast(@alignCast(user.?));
    closeTab(tab);
}

fn paneCloseClicked(user: ?*anyopaque) callconv(.c) void {
    const pane: *Pane = @ptrCast(@alignCast(user.?));
    closePane(pane);
}

fn cmdExplorerOpen(app: *App) void {
    const index = app.files_selected orelse return;
    if (index >= app.files_entries.items.len) return;
    const entry = app.files_entries.items[index];
    if (entry.path.len == 0) return;
    if (entry.directory) {
        setFilesPath(app, entry.path);
        c.cadex_listbox_focus_first(app.files_list);
    } else {
        openDocument(app, entry.path, 0);
    }
}

fn cmdExplorerCopyPath(app: *App) void {
    const index = app.files_selected orelse return;
    if (index >= app.files_entries.items.len) return;
    const entry = app.files_entries.items[index];
    if (entry.path.len == 0) return;
    c.cadex_clipboard_set(app.window, entry.path.ptr);
    showMessage(app, "Path copied");
}

fn cmdTextCut(app: *App) void {
    if (app.active_doc) |doc| {
        c.cadex_text_view_cut(doc.view);
    }
}

fn cmdTextUndo(app: *App) void {
    if (app.active_doc) |doc| {
        c.cadex_text_view_undo(doc.view);
    }
}

fn cmdTextRedo(app: *App) void {
    if (app.active_doc) |doc| {
        c.cadex_text_view_redo(doc.view);
    }
}

fn cmdAppHide(app: *App) void {
    c.cadex_window_minimize(app.window);
}

fn cmdExplorerCopyRelative(app: *App) void {
    const index = app.files_selected orelse return;
    if (index >= app.files_entries.items.len) return;
    const entry = app.files_entries.items[index];
    const relative = if (std.mem.startsWith(u8, entry.path, app.root)) entry.path[app.root.len..] else entry.path;
    const z = app.gpa.dupeZ(u8, if (relative.len > 0 and relative[0] == '/') relative[1..] else relative) catch return;
    defer app.gpa.free(z);
    c.cadex_clipboard_set(app.window, z.ptr);
    showMessage(app, "Relative path copied");
}

fn cmdExplorerOpenTerminal(app: *App) void {
    const index = app.files_selected orelse {
        showMessage(app, "Select a folder first");
        return;
    };
    if (index >= app.files_entries.items.len) return;
    const entry = app.files_entries.items[index];
    const dir = if (entry.directory) entry.path else (std.fs.path.dirname(entry.path) orelse app.files_path);
    newTab(app, currentSpace(app)) catch return;
    const pane = app.focused orelse return;
    const term = pane.term orelse return;
    const command = std.fmt.allocPrint(app.gpa, "cd '{s}'\n", .{dir}) catch return;
    defer app.gpa.free(command);
    term.write(command);
    showMessage(app, "Terminal opened in the folder");
}

fn cmdGitReveal(app: *App) void {
    const index = app.git_selected orelse return;
    const status = app.git_status_data orelse return;
    if (index >= status.files.len) return;
    const full = std.fs.path.join(app.gpa, &.{ app.root, status.files[index].path }) catch return;
    defer app.gpa.free(full);
    const dir = std.fs.path.dirname(full) orelse app.root;
    const dir_z = app.gpa.dupeZ(u8, dir) catch return;
    defer app.gpa.free(dir_z);
    _ = c.cadex_open_path(dir_z.ptr);
}

fn cmdExplorerReveal(app: *App) void {
    const index = app.files_selected orelse {
        const dir_z = app.gpa.dupeZ(u8, app.files_path) catch return;
        defer app.gpa.free(dir_z);
        _ = c.cadex_open_path(dir_z.ptr);
        return;
    };
    if (index >= app.files_entries.items.len) return;
    const entry = app.files_entries.items[index];
    const dir = if (entry.directory) entry.path else (std.fs.path.dirname(entry.path) orelse app.files_path);
    const dir_z = app.gpa.dupeZ(u8, dir) catch return;
    defer app.gpa.free(dir_z);
    _ = c.cadex_open_path(dir_z.ptr);
}

fn cmdGitStage(app: *App) void {
    gitStageClicked(@ptrCast(app));
}

fn cmdGitUnstage(app: *App) void {
    gitUnstageClicked(@ptrCast(app));
}

fn cmdGitDiscard(app: *App) void {
    gitDiscardClicked(@ptrCast(app));
}

fn cmdGitPush(app: *App) void {
    gitPushClicked(@ptrCast(app));
}

fn cmdGitPull(app: *App) void {
    gitPullClicked(@ptrCast(app));
}

fn cmdGitFetch(app: *App) void {
    gitFetchClicked(@ptrCast(app));
}

fn cmdGitOpenDiff(app: *App) void {
    if (app.git_selected) |index| openGitDiff(app, index);
}

fn cmdGitStageAll(app: *App) void {
    const repo = app.git_repo orelse return;
    const status = app.git_status_data orelse return;
    var zs: std.ArrayList([:0]u8) = .empty;
    defer {
        for (zs.items) |z| app.gpa.free(z);
        zs.deinit(app.gpa);
    }
    var ptrs: std.ArrayList([*c]const u8) = .empty;
    defer ptrs.deinit(app.gpa);
    for (status.files) |file| addGitPath(app, file.path, &zs, &ptrs);
    if (ptrs.items.len == 0) return;
    var message: ?[*]u8 = null;
    var len: usize = 0;
    const rc = core.cadex_git_stage(repo.ptr, @ptrCast(ptrs.items.ptr), ptrs.items.len, &message, &len);
    finishGit(app, rc, message, len, "Staged all");
}

fn cmdGitUnstageAll(app: *App) void {
    const repo = app.git_repo orelse return;
    const status = app.git_status_data orelse return;
    var zs: std.ArrayList([:0]u8) = .empty;
    defer {
        for (zs.items) |z| app.gpa.free(z);
        zs.deinit(app.gpa);
    }
    var ptrs: std.ArrayList([*c]const u8) = .empty;
    defer ptrs.deinit(app.gpa);
    for (status.files) |file| addGitPath(app, file.path, &zs, &ptrs);
    if (ptrs.items.len == 0) return;
    var message: ?[*]u8 = null;
    var len: usize = 0;
    const rc = core.cadex_git_unstage(repo.ptr, @ptrCast(ptrs.items.ptr), ptrs.items.len, &message, &len);
    finishGit(app, rc, message, len, "Unstaged all");
}

fn cmdGitOpenFile(app: *App) void {
    const index = app.git_selected orelse return;
    const status = app.git_status_data orelse return;
    if (index >= status.files.len) return;
    const full = std.fs.path.join(app.gpa, &.{ app.root, status.files[index].path }) catch return;
    defer app.gpa.free(full);
    const z = app.gpa.dupeZ(u8, full) catch return;
    defer app.gpa.free(z);
    openDocument(app, z, 0);
}

fn cyclePane(app: *App, direction: isize) void {
    if (app.active_doc != null) return;
    const pane = app.focused orelse return;
    const leaves = pane.tab.leaves.items;
    if (leaves.len == 0) return;
    var at: isize = 0;
    for (leaves, 0..) |leaf, index| {
        if (leaf == pane) at = @intCast(index);
    }
    const count: isize = @intCast(leaves.len);
    at = @mod(at + direction, count);
    const next = leaves[@intCast(at)];
    app.focused = next;
    c.cadex_widget_focus(next.area);
    updateTitle(app);
    updateStatus(app);
}

fn cmdPaneNext(app: *App) void {
    cyclePane(app, 1);
}

fn cmdPanePrev(app: *App) void {
    cyclePane(app, -1);
}

fn cmdPowerKeepAwake(app: *App) void {
    if (app.power_pid == 0) cmdTogglePower(app);
}

fn cmdPowerAllowSleep(app: *App) void {
    if (app.power_pid > 0) cmdTogglePower(app);
}

fn webPreviewDoc(app: *App) ?*Doc {
    const doc = app.active_doc orelse return null;
    if (std.mem.eql(u8, doc.language, "Web") or std.mem.eql(u8, doc.language, "PDF")) return doc;
    return null;
}

fn cmdPreviewBack(app: *App) void {
    if (webPreviewDoc(app)) |doc| c.cadex_webview_back(doc.view);
}

fn cmdPreviewForward(app: *App) void {
    if (webPreviewDoc(app)) |doc| c.cadex_webview_forward(doc.view);
}

fn cmdPreviewReload(app: *App) void {
    if (webPreviewDoc(app)) |doc| c.cadex_webview_reload(doc.view);
}

fn cmdSearchFiles(app: *App) void {
    openSidebarPage(app, "search");
    app.search_mode = .files;
    const raw = c.cadex_entry_text(app.search_entry);
    if (raw != null) runFileSearch(app, std.mem.span(@as([*:0]const u8, @ptrCast(raw))));
}

fn cmdSearchContent(app: *App) void {
    openSidebarPage(app, "search");
    app.search_mode = .content;
    runContentSearch(app);
}

fn cmdThemeNext(app: *App) void {
    app.theme_index = (app.theme_index + 1) % themes.len;
    applyTheme(app);
    saveSettings(app);
}

fn cmdThemeDark(app: *App) void {
    for (themes, 0..) |theme, index| {
        if (!theme.dark) continue;
        app.theme_index = index;
        applyTheme(app);
        saveSettings(app);
        return;
    }
}

fn cmdThemeLight(app: *App) void {
    for (themes, 0..) |theme, index| {
        if (theme.dark) continue;
        app.theme_index = index;
        applyTheme(app);
        saveSettings(app);
        return;
    }
}

fn cmdWindowNew(app: *App) void {
    newSpace(app) catch {};
}

fn cmdTerminalScrollTop(app: *App) void {
    const pane = app.focused orelse return;
    if (pane.term) |term| {
        term.scrollTop();
        schedulePaneRedraw(pane);
    }
}

fn cmdTerminalScrollBottom(app: *App) void {
    const pane = app.focused orelse return;
    if (pane.term) |term| {
        term.scrollBottom();
        schedulePaneRedraw(pane);
    }
}

fn cmdTerminalClear(app: *App) void {
    const pane = app.focused orelse return;
    if (pane.term) |term| term.write("\x0c");
}

fn cmdHistoryCopySha(app: *App) void {
    const index = app.history_selected orelse return;
    if (index >= app.history_commits.items.len) return;
    const sha = app.history_commits.items[index].sha;
    const z = app.gpa.dupeZ(u8, sha) catch return;
    defer app.gpa.free(z);
    c.cadex_clipboard_set(app.window, z.ptr);
    showMessage(app, "Commit SHA copied");
}

fn cmdHistoryOpenRemote(app: *App) void {
    const index = app.history_selected orelse return;
    if (index >= app.history_commits.items.len) return;
    const repo = app.git_repo orelse return;
    const sha = app.history_commits.items[index].sha;
    const sha_z = app.gpa.dupeZ(u8, sha) catch return;
    defer app.gpa.free(sha_z);
    var out: ?[*]u8 = null;
    var len: usize = 0;
    if (core.cadex_history_remote_url(repo.ptr, sha_z.ptr, &out, &len) != core.CADEX_OK or out == null) {
        showMessage(app, "No remote URL for this commit");
        return;
    }
    defer core.cadex_free(@ptrCast(out.?));
    const z = app.gpa.dupeZ(u8, out.?[0..len]) catch return;
    defer app.gpa.free(z);
    _ = c.cadex_open_uri(z.ptr);
}

fn cmdSearchToggleCase(app: *App) void {
    app.search_case = !app.search_case;
    showMessage(app, if (app.search_case) "Search: case sensitive" else "Search: ignore case");
    if (app.search_mode == .content) runContentSearch(app);
}

fn cmdSearchToggleRegex(app: *App) void {
    app.search_regex = !app.search_regex;
    showMessage(app, if (app.search_regex) "Search: regex" else "Search: plain text");
    if (app.search_mode == .content) runContentSearch(app);
}

fn cmdHistoryCurrentBranch(app: *App) void {
    if (app.git_status_data) |status| {
        showMessage(app, if (status.branch.len > 0) status.branch else "(detached)");
    } else {
        showMessage(app, "No git repository");
    }
}

fn cmdNewTab(app: *App) void {
    if (app.page != .terminal) openPage(app, .terminal);
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
    if (app.page != .terminal) openPage(app, .terminal);
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

fn cmdSidebarAgents(app: *App) void {
    openSidebarPage(app, "agents");
}

fn cmdSidebarSsh(app: *App) void {
    openSidebarPage(app, "ssh");
}

fn cmdTogglePower(app: *App) void {
    if (app.power_pid > 0) {
        c.cadex_inhibit_stop(app.power_pid);
        app.power_pid = 0;
        if (app.power_button) |button| c.cadex_button_set_text(button, "Keep Awake");
        showMessage(app, "Sleep is allowed again");
        return;
    }
    app.power_pid = c.cadex_inhibit_start("Cadex is keeping the machine awake");
    if (app.power_pid > 0) {
        if (app.power_button) |button| c.cadex_button_set_text(button, "Awake");
        showMessage(app, "Keeping the machine awake");
    } else {
        showMessage(app, "Could not inhibit sleep (systemd-inhibit missing)");
    }
}

fn cmdTestNotification(app: *App) void {
    c.cadex_notify("Cadex", "Notifications are working");
    showMessage(app, "Notification sent");
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

fn cmdMarkdownNotes(app: *App) void {
    if (app.active_doc) |doc| notesOpen(doc);
}

fn cmdOpenUrl(app: *App) void {
    promptOpen(app, .url);
}

fn cmdTestPick(app: *App) void {
    const doc = app.active_doc orelse return;
    if (!std.mem.eql(u8, doc.language, "Web") and !std.mem.eql(u8, doc.language, "PDF")) return;
    c.cadex_webview_test_pick(doc.view);
}

fn cmdNewFile(app: *App) void {
    promptOpen(app, .file);
}

fn cmdNewFolder(app: *App) void {
    promptOpen(app, .folder);
}

fn cmdRenameFile(app: *App) void {
    filesRenameClicked(app);
}

fn cmdDeleteFile(app: *App) void {
    filesDeleteClicked(app);
}

fn cmdRefreshExplorer(app: *App) void {
    refreshFiles(app);
}

fn cmdGitCommitMessage(app: *App) void {
    openSidebarPage(app, "git");
    c.cadex_widget_focus(app.git_commit_entry);
    showMessage(app, "Type a commit message and press Enter");
}

fn cmdGitBranches(app: *App) void {
    branchOpen(app);
}

fn cmdGitSideDiff(app: *App) void {
    if (app.git_selected) |index| openSideDiff(app, index);
}

fn cmdGitInit(app: *App) void {
    gitInit(app);
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

fn sidebarAgentsClicked(user: ?*anyopaque) callconv(.c) void {
    const app: *App = @ptrCast(@alignCast(user.?));
    cmdSidebarAgents(app);
}

fn sidebarSshClicked(user: ?*anyopaque) callconv(.c) void {
    const app: *App = @ptrCast(@alignCast(user.?));
    cmdSidebarSsh(app);
}

fn powerClicked(user: ?*anyopaque) callconv(.c) void {
    const app: *App = @ptrCast(@alignCast(user.?));
    cmdTogglePower(app);
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
    for (command_aliases) |command| {
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
    const window = c.cadex_window_new_dialog(app.window, "Command Palette", 640, 460) orelse return;
    c.cadex_window_hide_on_close(window);
    c.cadex_widget_on_escape(window, paletteHide, app);
    const box = c.cadex_box_new() orelse return;
    c.cadex_widget_set_margins(box, 12, 12, 12, 12);
    const entry = c.cadex_entry_new() orelse return;
    c.cadex_widget_visible(entry, 1);
    c.cadex_entry_set_placeholder(entry, "Search commands");
    c.cadex_entry_changed(entry, paletteChanged, app);
    c.cadex_entry_activate(entry, paletteActivate, app);
    c.cadex_entry_escape(entry, paletteHide, app);
    c.cadex_widget_set_margins(entry, 0, 0, 0, 8);
    c.cadex_box_append(box, entry);
    const list = c.cadex_listbox_new() orelse return;
    c.cadex_widget_add_class(list, "boxed-list");
    c.cadex_listbox_on_activated(list, paletteRow, app);
    const scrolled = c.cadex_scrolled_new(list) orelse return;
    c.cadex_widget_expand(scrolled);
    c.cadex_box_append(box, scrolled);
    c.cadex_window_child(window, box);
    app.palette_window = window;
    app.palette_entry = entry;
    app.palette_list = list;
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

fn paletteFilter(app: *App) void {
    const entry = app.palette_entry orelse return;
    const list = app.palette_list orelse return;
    const raw = c.cadex_entry_text(entry);
    const query = if (raw == null) "" else std.mem.span(@as([*:0]const u8, @ptrCast(raw)));
    c.cadex_listbox_clear(list);
    app.palette_filtered.clearRetainingCapacity();
    const groups = [_][]const Command{ &commands, &command_aliases };
    for (groups) |group| {
        for (group) |*command| {
            if (query.len > 0 and !containsIgnoreCase(command.title, query) and !containsIgnoreCase(command.keywords, query)) continue;
            var duplicate = false;
            for (app.palette_filtered.items) |existing| {
                if (std.mem.eql(u8, existing.title, command.title)) {
                    duplicate = true;
                    break;
                }
            }
            if (duplicate) continue;
            app.palette_filtered.append(app.gpa, command) catch return;
            const title = app.gpa.dupeZ(u8, command.title) catch continue;
            defer app.gpa.free(title);
            const shortcut = app.gpa.dupeZ(u8, command.shortcut) catch continue;
            defer app.gpa.free(shortcut);
            c.cadex_listbox_append_action(list, "go-next-symbolic", title.ptr, if (command.shortcut.len > 0) shortcut.ptr else null);
        }
    }
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
    if (app.settings_blink) |sw| c.cadex_switch_set_active(sw, @intFromBool(app.settings.cursor_blink));
    if (app.settings_sidebar) |sw| c.cadex_switch_set_active(sw, @intFromBool(app.settings.sidebar));
    c.cadex_window_present(window, 0);
}

fn settingsCreate(app: *App) void {
    const window = c.cadex_adw_preferences_window_new(app.window, "Settings") orelse return;
    c.cadex_window_hide_on_close(window);
    c.cadex_widget_on_escape(window, settingsClose, app);
    const page = c.cadex_adw_preferences_page_new() orelse return;
    const appearance = c.cadex_adw_preferences_group_new("Appearance") orelse return;

    const dd = c.cadex_dropdown_new(@ptrCast(&theme_names), @intCast(theme_names.len)) orelse return;
    c.cadex_dropdown_set_selected(dd, @intCast(app.theme_index));
    c.cadex_dropdown_on_changed(dd, settingsThemeChanged, app);
    const theme_row = c.cadex_adw_action_row_new("Terminal theme", "Colors for the terminal and editor") orelse return;
    c.cadex_adw_action_row_add_suffix(theme_row, dd);
    c.cadex_adw_preferences_group_add(appearance, theme_row);

    const spin = c.cadex_spin_new(8, 24, 1) orelse return;
    c.cadex_spin_set_value(spin, app.settings.font_size);
    c.cadex_spin_on_changed(spin, settingsFontChanged, app);
    const font_row = c.cadex_adw_action_row_new("Font size", "Terminal and editor text") orelse return;
    c.cadex_adw_action_row_add_suffix(font_row, spin);
    c.cadex_adw_preferences_group_add(appearance, font_row);

    const blink = c.cadex_switch_new(@intFromBool(app.settings.cursor_blink)) orelse return;
    c.cadex_switch_on_changed(blink, settingsBlinkChanged, app);
    const blink_row = c.cadex_adw_action_row_new("Cursor blink", "Blink the terminal cursor") orelse return;
    c.cadex_adw_action_row_add_suffix(blink_row, blink);
    c.cadex_adw_preferences_group_add(appearance, blink_row);

    const sidebar = c.cadex_switch_new(@intFromBool(app.settings.sidebar)) orelse return;
    c.cadex_switch_on_changed(sidebar, settingsSidebarChanged, app);
    const sidebar_row = c.cadex_adw_action_row_new("Sidebar", "Show the navigation sidebar") orelse return;
    c.cadex_adw_action_row_add_suffix(sidebar_row, sidebar);
    c.cadex_adw_preferences_group_add(appearance, sidebar_row);

    c.cadex_adw_preferences_page_add(page, appearance);
    const about_group = c.cadex_adw_preferences_group_new("About") orelse return;
    const about = c.cadex_adw_action_row_new("Cadex — Linux preview", "GTK4 + libadwaita on Wayland") orelse return;
    c.cadex_adw_preferences_group_add(about_group, about);
    c.cadex_adw_preferences_page_add(page, about_group);
    c.cadex_adw_preferences_window_add(window, page);
    app.settings_window = window;
    app.settings_theme = dd;
    app.settings_font = spin;
    app.settings_blink = blink;
    app.settings_sidebar = sidebar;
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

fn settingsBlinkChanged(user: ?*anyopaque) callconv(.c) void {
    const app: *App = @ptrCast(@alignCast(user.?));
    const sw = app.settings_blink orelse return;
    app.settings.cursor_blink = c.cadex_switch_active(sw) != 0;
    for (app.spaces.items) |space| {
        for (space.tabs.items) |tab| {
            for (tab.leaves.items) |pane| {
                if (pane.term) |term| term.setCursor(CURSOR_BLOCK, app.settings.cursor_blink);
            }
        }
    }
    saveSettings(app);
}

fn settingsSidebarChanged(user: ?*anyopaque) callconv(.c) void {
    const app: *App = @ptrCast(@alignCast(user.?));
    const sw = app.settings_sidebar orelse return;
    app.settings.sidebar = c.cadex_switch_active(sw) != 0;
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

const SavedSpace = struct {
    terminals: usize = 1,
};

const SavedSpaces = struct {
    current: usize = 0,
    spaces: []SavedSpace = &.{},
};

fn configPath(app: *App, name: []const u8) ![:0]u8 {
    if (std.c.getenv("XDG_CONFIG_HOME")) |base_z| {
        const base = std.mem.span(base_z);
        const dir = try std.fmt.allocPrintSentinel(app.gpa, "{s}/cadex", .{base}, 0);
        defer app.gpa.free(dir);
        _ = c.cadex_make_dir(dir.ptr);
        return std.fmt.allocPrintSentinel(app.gpa, "{s}/{s}", .{ dir, name }, 0);
    }
    const home_z = std.c.getenv("HOME") orelse return error.NoHome;
    const home = std.mem.span(home_z);
    const dir = try std.fmt.allocPrintSentinel(app.gpa, "{s}/.config/cadex", .{home}, 0);
    defer app.gpa.free(dir);
    _ = c.cadex_make_dir(dir.ptr);
    return std.fmt.allocPrintSentinel(app.gpa, "{s}/{s}", .{ dir, name }, 0);
}

fn restoreSpaces(app: *App) !void {
    app.restoring_spaces = true;
    defer app.restoring_spaces = false;
    const path = configPath(app, "spaces.json") catch {
        try newSpace(app);
        return;
    };
    defer app.gpa.free(path);
    var len: usize = 0;
    const raw = c.cadex_read_file(path.ptr, &len);
    var parsed: ?std.json.Parsed(SavedSpaces) = null;
    if (raw != null) {
        defer c.cadex_gtk_free(@ptrCast(raw));
        parsed = std.json.parseFromSlice(SavedSpaces, app.gpa, raw[0..len], .{ .ignore_unknown_fields = true }) catch null;
    }
    if (parsed) |*state| {
        defer state.deinit();
        if (state.value.spaces.len > 0) {
            for (state.value.spaces) |saved| {
                try newSpace(app);
                const space = app.spaces.items[app.spaces.items.len - 1];
                var extra: usize = 1;
                while (extra < saved.terminals) : (extra += 1) newTab(app, space) catch break;
            }
            const current = @min(state.value.current, app.spaces.items.len - 1);
            switchSpace(app, current);
            return;
        }
    }
    try newSpace(app);
}

fn saveSpaces(app: *App) void {
    if (app.closing or app.restoring_spaces) return;
    const path = configPath(app, "spaces.json") catch return;
    defer app.gpa.free(path);
    var out: std.ArrayList(u8) = .empty;
    defer out.deinit(app.gpa);
    appendFormatted(&out, app.gpa, "{{\"current\":{d},\"spaces\":[", .{app.space_index});
    for (app.spaces.items, 0..) |space, index| {
        var terminals: usize = 0;
        for (space.tabs.items) |tab| {
            if (tab.kind == .terminal) terminals += 1;
        }
        if (terminals == 0) terminals = 1;
        appendFormatted(&out, app.gpa, "{s}{{\"terminals\":{d}}}", .{
            if (index == 0) "" else ",",
            terminals,
        });
    }
    appendFormatted(&out, app.gpa, "]}}", .{});
    const z = app.gpa.dupeZ(u8, out.items) catch return;
    defer app.gpa.free(z);
    _ = c.cadex_write_file(path.ptr, z.ptr, z.len);
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
