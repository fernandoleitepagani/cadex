//! Markdown HTML body -> Pango markup, for the interim preview on Linux.
//! WebKitGTK is the real renderer (Run 5); this keeps the notes readable
//! without a new dependency and is replaced when the preview page exists.

const std = @import("std");

const void_tags = [_][]const u8{ "br", "hr", "img", "meta", "link", "input" };

pub fn toPango(allocator: std.mem.Allocator, html: []const u8) ![]u8 {
    var out: std.ArrayList(u8) = .empty;
    errdefer out.deinit(allocator);
    var stack: std.ArrayList([]const u8) = .empty;
    defer stack.deinit(allocator);

    var i: usize = 0;
    var in_pre = false;
    var space_pending = false;
    var wrote_block = false;

    while (i < html.len) {
        if (html[i] == '<') {
            const end = std.mem.indexOfScalarPos(u8, html, i, '>') orelse break;
            const tag = html[i + 1 .. end];
            i = end + 1;
            if (std.mem.startsWith(u8, tag, "!--")) continue;
            const closing = tag.len > 0 and tag[0] == '/';
            const name_start: usize = if (closing) 1 else 0;
            var name_end = name_start;
            while (name_end < tag.len and !std.ascii.isWhitespace(tag[name_end]) and tag[name_end] != '/') name_end += 1;
            const name = tag[name_start..name_end];
            if (name.len == 0) continue;
            if (!closing and isVoid(name)) {
                try voidTag(allocator, &out, &space_pending, name);
                continue;
            }
            if (std.ascii.eqlIgnoreCase(name, "pre")) in_pre = !closing;
            if (closing) {
                try closeTag(allocator, &out, &stack, name);
            } else {
                try openTag(allocator, &out, &stack, &wrote_block, &space_pending, name, tag);
            }
            continue;
        }

        var run_end = i;
        while (run_end < html.len and html[run_end] != '<') run_end += 1;
        try appendText(allocator, &out, html[i..run_end], in_pre, &space_pending);
        i = run_end;
    }

    while (stack.pop()) |closer| try out.appendSlice(allocator, closer);
    return out.toOwnedSlice(allocator);
}

fn isVoid(name: []const u8) bool {
    for (void_tags) |void_tag| if (std.ascii.eqlIgnoreCase(name, void_tag)) return true;
    return false;
}

fn voidTag(allocator: std.mem.Allocator, out: *std.ArrayList(u8), space_pending: *bool, name: []const u8) !void {
    space_pending.* = false;
    if (std.ascii.eqlIgnoreCase(name, "br")) {
        try out.append(allocator, '\n');
    } else if (std.ascii.eqlIgnoreCase(name, "hr")) {
        try out.appendSlice(allocator, "\n────────\n");
    } else if (std.ascii.eqlIgnoreCase(name, "img")) {
        try out.appendSlice(allocator, "[image]");
    }
}

fn openTag(
    allocator: std.mem.Allocator,
    out: *std.ArrayList(u8),
    stack: *std.ArrayList([]const u8),
    wrote_block: *bool,
    space_pending: *bool,
    name: []const u8,
    full: []const u8,
) !void {
    if (headingLevel(name)) |level| {
        if (wrote_block.*) try out.appendSlice(allocator, "\n\n") else wrote_block.* = true;
        space_pending.* = false;
        const size = switch (level) {
            1 => "xx-large",
            2 => "x-large",
            3 => "large",
            4 => "medium",
            else => "small",
        };
        var buf: [96]u8 = undefined;
        const markup = try std.fmt.bufPrint(&buf, "<span size=\"{s}\" weight=\"bold\">", .{size});
        try out.appendSlice(allocator, markup);
        try stack.append(allocator, "</span>");
        return;
    }
    if (std.ascii.eqlIgnoreCase(name, "p") or std.ascii.eqlIgnoreCase(name, "div") or
        std.ascii.eqlIgnoreCase(name, "section") or std.ascii.eqlIgnoreCase(name, "article"))
    {
        if (wrote_block.*) try out.appendSlice(allocator, "\n\n") else wrote_block.* = true;
        space_pending.* = false;
        return;
    }
    if (std.ascii.eqlIgnoreCase(name, "ul") or std.ascii.eqlIgnoreCase(name, "ol") or
        std.ascii.eqlIgnoreCase(name, "blockquote") or std.ascii.eqlIgnoreCase(name, "table") or
        std.ascii.eqlIgnoreCase(name, "tr"))
    {
        try out.append(allocator, '\n');
        space_pending.* = false;
        return;
    }
    if (std.ascii.eqlIgnoreCase(name, "li")) {
        try out.appendSlice(allocator, "\n• ");
        space_pending.* = false;
        return;
    }
    if (std.ascii.eqlIgnoreCase(name, "td") or std.ascii.eqlIgnoreCase(name, "th")) {
        try out.appendSlice(allocator, " | ");
        space_pending.* = false;
        return;
    }
    if (std.ascii.eqlIgnoreCase(name, "pre")) {
        if (wrote_block.*) try out.appendSlice(allocator, "\n\n") else wrote_block.* = true;
        try out.appendSlice(allocator, "<tt>");
        try stack.append(allocator, "</tt>");
        space_pending.* = false;
        return;
    }
    if (std.ascii.eqlIgnoreCase(name, "code")) {
        try out.appendSlice(allocator, "<tt>");
        try stack.append(allocator, "</tt>");
        return;
    }
    if (std.ascii.eqlIgnoreCase(name, "strong") or std.ascii.eqlIgnoreCase(name, "b")) {
        try out.appendSlice(allocator, "<b>");
        try stack.append(allocator, "</b>");
        return;
    }
    if (std.ascii.eqlIgnoreCase(name, "em") or std.ascii.eqlIgnoreCase(name, "i")) {
        try out.appendSlice(allocator, "<i>");
        try stack.append(allocator, "</i>");
        return;
    }
    if (std.ascii.eqlIgnoreCase(name, "del") or std.ascii.eqlIgnoreCase(name, "s")) {
        try out.appendSlice(allocator, "<s>");
        try stack.append(allocator, "</s>");
        return;
    }
    if (std.ascii.eqlIgnoreCase(name, "a")) {
        // The interim preview shows links as links; opening them arrives with
        // the WebKit page (Run 5).
        _ = full;
        try out.appendSlice(allocator, "<u><span foreground=\"#4fc1ff\">");
        try stack.append(allocator, "</span></u>");
        return;
    }
}

fn closeTag(allocator: std.mem.Allocator, out: *std.ArrayList(u8), stack: *std.ArrayList([]const u8), name: []const u8) !void {
    const wanted = if (headingLevel(name) != null)
        "</span>"
    else if (std.ascii.eqlIgnoreCase(name, "p") or std.ascii.eqlIgnoreCase(name, "div") or
        std.ascii.eqlIgnoreCase(name, "section") or std.ascii.eqlIgnoreCase(name, "article"))
        "\n"
    else if (std.ascii.eqlIgnoreCase(name, "pre"))
        "</tt>"
    else if (std.ascii.eqlIgnoreCase(name, "code"))
        "</tt>"
    else if (std.ascii.eqlIgnoreCase(name, "strong") or std.ascii.eqlIgnoreCase(name, "b"))
        "</b>"
    else if (std.ascii.eqlIgnoreCase(name, "em") or std.ascii.eqlIgnoreCase(name, "i"))
        "</i>"
    else if (std.ascii.eqlIgnoreCase(name, "del") or std.ascii.eqlIgnoreCase(name, "s"))
        "</s>"
    else if (std.ascii.eqlIgnoreCase(name, "a"))
        "</span></u>"
    else
        "";
    if (wanted.len == 0) {
        if (std.ascii.eqlIgnoreCase(name, "ul") or std.ascii.eqlIgnoreCase(name, "ol") or
            std.ascii.eqlIgnoreCase(name, "blockquote") or std.ascii.eqlIgnoreCase(name, "table"))
        {
            try out.append(allocator, '\n');
        }
        if (std.ascii.eqlIgnoreCase(name, "li")) try out.append(allocator, '\n');
        return;
    }
    // Pop until the matching closer; malformed HTML still yields valid markup.
    var index: ?usize = null;
    var at = stack.items.len;
    while (at > 0) {
        at -= 1;
        if (std.mem.eql(u8, stack.items[at], wanted)) {
            index = at;
            break;
        }
    }
    if (index) |found| {
        while (stack.items.len > found) {
            const closer = stack.pop().?;
            try out.appendSlice(allocator, closer);
        }
    }
    if (std.ascii.eqlIgnoreCase(name, "pre")) try out.appendSlice(allocator, "\n\n");
}

fn headingLevel(name: []const u8) ?u8 {
    if (name.len != 2 or !std.ascii.eqlIgnoreCase(name[0..1], "h")) return null;
    if (name[1] < '1' or name[1] > '6') return null;
    return name[1] - '0';
}

fn appendText(allocator: std.mem.Allocator, out: *std.ArrayList(u8), text: []const u8, in_pre: bool, space_pending: *bool) !void {
    var i: usize = 0;
    while (i < text.len) {
        if (text[i] == '&') {
            if (entity(text[i..])) |decoded| {
                if (!in_pre and decoded <= 0x7f and std.ascii.isWhitespace(@intCast(decoded))) {
                    space_pending.* = true;
                } else {
                    if (space_pending.*) try emitSpace(allocator, out, space_pending);
                    var utf8: [4]u8 = undefined;
                    const size = std.unicode.utf8Encode(decoded, &utf8) catch 0;
                    if (size > 0) try appendEscaped(allocator, out, utf8[0..size]);
                }
                i += entityLen(text[i..]);
                continue;
            }
            if (space_pending.*) try emitSpace(allocator, out, space_pending);
            try appendEscaped(allocator, out, "&");
            i += 1;
            continue;
        }
        if (!in_pre and std.ascii.isWhitespace(text[i])) {
            space_pending.* = true;
            i += 1;
            continue;
        }
        if (space_pending.*) try emitSpace(allocator, out, space_pending);
        try appendEscaped(allocator, out, text[i .. i + 1]);
        i += 1;
    }
}

fn emitSpace(allocator: std.mem.Allocator, out: *std.ArrayList(u8), space_pending: *bool) !void {
    space_pending.* = false;
    if (out.items.len == 0) return;
    const last = out.items[out.items.len - 1];
    if (last == '\n' or last == ' ') return;
    try out.append(allocator, ' ');
}

fn appendEscaped(allocator: std.mem.Allocator, out: *std.ArrayList(u8), text: []const u8) !void {
    for (text) |byte| switch (byte) {
        '&' => try out.appendSlice(allocator, "&amp;"),
        '<' => try out.appendSlice(allocator, "&lt;"),
        '>' => try out.appendSlice(allocator, "&gt;"),
        else => try out.append(allocator, byte),
    };
}

fn entity(text: []const u8) ?u21 {
    if (text.len < 4 or text[0] != '&') return null;
    const end = std.mem.indexOfScalar(u8, text[0..@min(text.len, 12)], ';') orelse return null;
    const body = text[1..end];
    if (std.mem.eql(u8, body, "amp")) return '&';
    if (std.mem.eql(u8, body, "lt")) return '<';
    if (std.mem.eql(u8, body, "gt")) return '>';
    if (std.mem.eql(u8, body, "quot")) return '"';
    if (std.mem.eql(u8, body, "apos")) return '\'';
    if (std.mem.eql(u8, body, "nbsp")) return ' ';
    if (body.len > 1 and body[0] == '#') {
        const code = if (body.len > 2 and (body[1] == 'x' or body[1] == 'X'))
            std.fmt.parseInt(u21, body[2..], 16) catch return null
        else
            std.fmt.parseInt(u21, body[1..], 10) catch return null;
        return if (code == 0) null else code;
    }
    return null;
}

fn entityLen(text: []const u8) usize {
    const end = std.mem.indexOfScalar(u8, text[0..@min(text.len, 12)], ';') orelse return 1;
    return end + 1;
}

test "headings, emphasis, entities and code" {
    const html = "<h1>Title</h1><p>Hello <strong>world</strong> &amp; <code>x</code></p>";
    const markup = try toPango(std.testing.allocator, html);
    defer std.testing.allocator.free(markup);
    try std.testing.expect(std.mem.indexOf(u8, markup, "weight=\"bold\"") != null);
    try std.testing.expect(std.mem.indexOf(u8, markup, "<b>world</b>") != null);
    try std.testing.expect(std.mem.indexOf(u8, markup, "&amp;") != null);
    try std.testing.expect(std.mem.indexOf(u8, markup, "<tt>x</tt>") != null);
    try std.testing.expect(std.mem.indexOf(u8, markup, "<h1>") == null);
}

test "lists and pre keep their shape" {
    const html = "<ul><li>one</li><li>two</li></ul><pre>a\n  b</pre>";
    const markup = try toPango(std.testing.allocator, html);
    defer std.testing.allocator.free(markup);
    try std.testing.expect(std.mem.indexOf(u8, markup, "• one") != null);
    try std.testing.expect(std.mem.indexOf(u8, markup, "• two") != null);
    try std.testing.expect(std.mem.indexOf(u8, markup, "a\n  b") != null);
}

test "unclosed tags are closed" {
    const markup = try toPango(std.testing.allocator, "<p><b>bold");
    defer std.testing.allocator.free(markup);
    try std.testing.expect(std.mem.indexOf(u8, markup, "</b>") != null);
}
