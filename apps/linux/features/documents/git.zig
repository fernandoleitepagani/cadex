//! Parsers for the core's source-control and git-history listings. The core
//! already did the work; the app only needs these tab-separated lines.

const std = @import("std");

pub const File = struct {
    kind: u8,
    x: u8,
    y: u8,
    path: []u8,
    orig: []u8,
};

pub const Status = struct {
    branch: []u8,
    oid: []u8,
    upstream: []u8,
    ahead: i32,
    behind: i32,
    files: []File,

    pub fn deinit(self: Status, allocator: std.mem.Allocator) void {
        allocator.free(self.branch);
        allocator.free(self.oid);
        allocator.free(self.upstream);
        for (self.files) |file| {
            allocator.free(file.path);
            allocator.free(file.orig);
        }
        allocator.free(self.files);
    }

    pub fn staged(self: Status, index: usize) bool {
        const file = self.files[index];
        if (file.kind == 3) return false;
        return file.x != ' ' and file.x != '.' and file.x != '?';
    }

    pub fn hasChanges(self: Status) bool {
        return self.files.len > 0;
    }
};

pub fn parseStatus(allocator: std.mem.Allocator, bytes: []const u8) !Status {
    var lines = std.mem.splitScalar(u8, bytes, '\n');
    const head = lines.next() orelse return error.EmptyStatus;
    var fields = std.mem.splitScalar(u8, head, '\t');
    const branch = try allocator.dupe(u8, fields.next() orelse "");
    errdefer allocator.free(branch);
    const oid = try allocator.dupe(u8, fields.next() orelse "");
    errdefer allocator.free(oid);
    const upstream = try allocator.dupe(u8, fields.next() orelse "");
    errdefer allocator.free(upstream);
    const ahead = std.fmt.parseInt(i32, fields.next() orelse "0", 10) catch 0;
    const behind = std.fmt.parseInt(i32, fields.next() orelse "0", 10) catch 0;

    var files: std.ArrayList(File) = .empty;
    errdefer {
        for (files.items) |file| {
            allocator.free(file.path);
            allocator.free(file.orig);
        }
        files.deinit(allocator);
    }
    while (lines.next()) |line| {
        if (line.len == 0) continue;
        var at = std.mem.splitScalar(u8, line, '\t');
        const kind_text = at.next() orelse continue;
        const kind = std.fmt.parseInt(u8, kind_text, 10) catch continue;
        const x_text = at.next() orelse "";
        const y_text = at.next() orelse "";
        const path = try allocator.dupe(u8, at.next() orelse "");
        errdefer allocator.free(path);
        const orig = try allocator.dupe(u8, at.next() orelse "");
        files.append(allocator, .{
            .kind = kind,
            .x = if (x_text.len > 0) x_text[0] else ' ',
            .y = if (y_text.len > 0) y_text[0] else ' ',
            .path = path,
            .orig = orig,
        }) catch |err| {
            allocator.free(path);
            allocator.free(orig);
            return err;
        };
    }
    return .{
        .branch = branch,
        .oid = oid,
        .upstream = upstream,
        .ahead = ahead,
        .behind = behind,
        .files = try files.toOwnedSlice(allocator),
    };
}

pub const Commit = struct {
    sha: []u8,
    parents: []u8,
    author: []u8,
    email: []u8,
    time: i64,
    refs: []u8,
    subject: []u8,
    column: i32,
};

pub fn parseLog(allocator: std.mem.Allocator, bytes: []const u8) ![]Commit {
    var commits: std.ArrayList(Commit) = .empty;
    errdefer {
        for (commits.items) |commit| {
            allocator.free(commit.sha);
            allocator.free(commit.parents);
            allocator.free(commit.author);
            allocator.free(commit.email);
            allocator.free(commit.refs);
            allocator.free(commit.subject);
        }
        commits.deinit(allocator);
    }
    var lines = std.mem.splitScalar(u8, bytes, '\n');
    while (lines.next()) |line| {
        if (line.len == 0) continue;
        var fields = std.mem.splitScalar(u8, line, '\t');
        const sha = fields.next() orelse continue;
        const parents = fields.next() orelse "";
        const author = fields.next() orelse "";
        const email = fields.next() orelse "";
        const time_text = fields.next() orelse "0";
        const refs = fields.next() orelse "";
        const subject = fields.next() orelse "";
        const column_text = fields.next() orelse "-1";
        var commit = Commit{
            .sha = try allocator.dupe(u8, sha),
            .parents = undefined,
            .author = undefined,
            .email = undefined,
            .time = std.fmt.parseInt(i64, time_text, 10) catch 0,
            .refs = undefined,
            .subject = undefined,
            .column = std.fmt.parseInt(i32, column_text, 10) catch -1,
        };
        errdefer allocator.free(commit.sha);
        commit.parents = try allocator.dupe(u8, parents);
        errdefer allocator.free(commit.parents);
        commit.author = try allocator.dupe(u8, author);
        errdefer allocator.free(commit.author);
        commit.email = try allocator.dupe(u8, email);
        errdefer allocator.free(commit.email);
        commit.refs = try allocator.dupe(u8, refs);
        errdefer allocator.free(commit.refs);
        commit.subject = try allocator.dupe(u8, subject);
        errdefer allocator.free(commit.subject);
        try commits.append(allocator, commit);
    }
    return commits.toOwnedSlice(allocator);
}

pub fn freeCommit(allocator: std.mem.Allocator, commit: Commit) void {
    allocator.free(commit.sha);
    allocator.free(commit.parents);
    allocator.free(commit.author);
    allocator.free(commit.email);
    allocator.free(commit.refs);
    allocator.free(commit.subject);
}

pub fn freeLog(allocator: std.mem.Allocator, commits: []Commit) void {
    for (commits) |commit| freeCommit(allocator, commit);
    allocator.free(commits);
}

pub const Change = struct {
    letter: []u8,
    added: []u8,
    removed: []u8,
    path: []u8,
    old_path: []u8,
};

pub const Details = struct {
    parents: []u8,
    message: []u8,
    changes: []Change,

    pub fn deinit(self: Details, allocator: std.mem.Allocator) void {
        allocator.free(self.parents);
        allocator.free(self.message);
        for (self.changes) |change| {
            allocator.free(change.letter);
            allocator.free(change.added);
            allocator.free(change.removed);
            allocator.free(change.path);
            allocator.free(change.old_path);
        }
        allocator.free(self.changes);
    }
};

pub fn parseDetails(allocator: std.mem.Allocator, bytes: []const u8) !Details {
    const first = std.mem.indexOfScalar(u8, bytes, 0x1e) orelse return error.BadDetails;
    const rest = bytes[first + 1 ..];
    const second_rel = std.mem.indexOfScalar(u8, rest, 0x1e) orelse return error.BadDetails;
    const parents = try allocator.dupe(u8, bytes[0..first]);
    errdefer allocator.free(parents);
    const message = try allocator.dupe(u8, rest[0..second_rel]);
    errdefer allocator.free(message);

    var changes: std.ArrayList(Change) = .empty;
    errdefer {
        for (changes.items) |change| {
            allocator.free(change.letter);
            allocator.free(change.added);
            allocator.free(change.removed);
            allocator.free(change.path);
            allocator.free(change.old_path);
        }
        changes.deinit(allocator);
    }
    var lines = std.mem.splitScalar(u8, rest[second_rel + 1 ..], '\n');
    while (lines.next()) |line| {
        if (line.len == 0) continue;
        var fields = std.mem.splitScalar(u8, line, '\t');
        const letter = fields.next() orelse continue;
        const added = fields.next() orelse "";
        const removed = fields.next() orelse "";
        const path = fields.next() orelse "";
        const old_path = fields.next() orelse "";
        changes.append(allocator, .{
            .letter = try allocator.dupe(u8, letter),
            .added = try allocator.dupe(u8, added),
            .removed = try allocator.dupe(u8, removed),
            .path = try allocator.dupe(u8, path),
            .old_path = try allocator.dupe(u8, old_path),
        }) catch |err| {
            const last = changes.items[changes.items.len - 1];
            allocator.free(last.letter);
            allocator.free(last.added);
            allocator.free(last.removed);
            allocator.free(last.path);
            allocator.free(last.old_path);
            changes.items.len -= 1;
            return err;
        };
    }
    return .{
        .parents = parents,
        .message = message,
        .changes = try changes.toOwnedSlice(allocator),
    };
}

const sample_status =
    "main\tabc1234\torigin/main\t2\t1\n" ++
    "0\t \tM\tsrc/main.zig\t\n" ++
    "3\t?\t?\tnotes.md\t\n" ++
    "1\tR\t \tdocs/new.md\tdocs/old.md\n";

test "status parses branch, ahead/behind and paths" {
    var status = try parseStatus(std.testing.allocator, sample_status);
    defer status.deinit(std.testing.allocator);
    try std.testing.expectEqualStrings("main", status.branch);
    try std.testing.expectEqualStrings("origin/main", status.upstream);
    try std.testing.expectEqual(@as(i32, 2), status.ahead);
    try std.testing.expectEqual(@as(i32, 1), status.behind);
    try std.testing.expectEqual(@as(usize, 3), status.files.len);
    try std.testing.expectEqualStrings("src/main.zig", status.files[0].path);
    try std.testing.expect(!status.staged(0));
    try std.testing.expectEqualStrings("docs/old.md", status.files[2].orig);
}

test "log parses a page" {
    const sample =
        "abc123\tdef456\tAna\tana@example.com\t1700000000\tHEAD -> main, origin/main\tAdd parser\t0\t1\t\t\n";
    const commits = try parseLog(std.testing.allocator, sample);
    defer freeLog(std.testing.allocator, commits);
    try std.testing.expectEqual(@as(usize, 1), commits.len);
    try std.testing.expectEqualStrings("abc123", commits[0].sha);
    try std.testing.expectEqualStrings("Add parser", commits[0].subject);
    try std.testing.expectEqual(@as(i64, 1700000000), commits[0].time);
}

test "details parse message and changes" {
    const sample = "def456\x1eSubject\n\nBody\x1eM\t3\t1\tsrc/main.zig\t\nA\t5\t-\tnew.zig\t\n";
    var details = try parseDetails(std.testing.allocator, sample);
    defer details.deinit(std.testing.allocator);
    try std.testing.expectEqualStrings("def456", details.parents);
    try std.testing.expectEqualStrings("Subject\n\nBody", details.message);
    try std.testing.expectEqual(@as(usize, 2), details.changes.len);
    var buf: [64]u8 = undefined;
    const counts = try std.fmt.bufPrint(&buf, "+{s} -{s}", .{ details.changes[0].added, details.changes[0].removed });
    try std.testing.expectEqualStrings("+3 -1", counts);
}
