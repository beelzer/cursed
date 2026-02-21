const std = @import("std");
const ArrayList = std.ArrayList;
const Allocator = std.mem.Allocator;
const lexer = @import("lexer.zig");

/// Configuration for the CURSED code formatter.
///
/// Controls indentation style, line length limits, brace placement, and
/// CURSED-specific options like Gen Z keyword alignment. All fields have
/// sensible defaults that match the standard CURSED style guide.
pub const FormatterConfig = struct {
    indent_size: u32 = 4,
    max_line_length: u32 = 100,
    use_spaces: bool = true,
    /// When true, opening braces go on their own line (Allman style).
    /// When false (default), braces follow the preceding statement (K&R style).
    newline_before_brace: bool = false,
    space_around_operators: bool = true,
    align_struct_fields: bool = true,
    sort_imports: bool = true,

    // CURSED-specific
    align_gen_z_keywords: bool = true,
    prefer_short_form_syntax: bool = true,
    /// Maximum number of chained method calls before the formatter
    /// should consider breaking them across lines.
    max_chained_calls: u32 = 3,
};

/// Mutable state tracked while walking the token stream. Tracks the current
/// indentation depth, whether we're inside function parameters (which affects
/// comma formatting), and the current line length for line-break decisions.
const FormattingContext = struct {
    config: FormatterConfig,
    current_indent: u32 = 0,
    in_function_params: bool = false,
    in_struct_definition: bool = false,
    in_interface_definition: bool = false,
    line_length: u32 = 0,

    /// Returns an allocated indentation string (spaces or tabs) for the
    /// current nesting depth. Caller must free.
    fn getIndent(self: *const FormattingContext, allocator: Allocator) ![]const u8 {
        const indent_size = if (self.config.use_spaces) self.config.indent_size else 1;
        const total_indent = self.current_indent * indent_size;

        const indent = try allocator.alloc(u8, total_indent);
        if (self.config.use_spaces) {
            for (indent) |*char| {
                char.* = ' ';
            }
        } else {
            for (indent) |*char| {
                char.* = '\t';
            }
        }
        return indent;
    }
};

/// Token-based code formatter for CURSED `.💀` source files.
///
/// Operates directly on the lexer's token stream rather than the parsed AST.
/// This design choice has two advantages:
///   1. It can format files that contain parse errors (via error recovery).
///   2. It preserves comments, which tokenize() strips but nextToken() retains.
///
/// The formatter walks the token list sequentially, emitting formatted output
/// into an internal ArrayList(u8) buffer. Each token kind has a dedicated
/// formatting method that handles spacing, indentation, and line breaks.
///
/// Usage:
///   var fmt = Formatter.init(allocator, config);
///   defer fmt.deinit();
///   const result = try fmt.format(source);
///   defer allocator.free(result);
pub const Formatter = struct {
    allocator: Allocator,
    config: FormatterConfig,
    output: ArrayList(u8),

    pub fn init(allocator: Allocator, config: FormatterConfig) Formatter {
        return Formatter{
            .allocator = allocator,
            .config = config,
            .output = ArrayList(u8){},
        };
    }

    pub fn deinit(self: *Formatter) void {
        self.output.deinit(self.allocator);
    }

    /// Formats the given CURSED source string and returns a newly allocated
    /// formatted version. The caller owns the returned slice.
    ///
    /// Uses nextToken() in a loop (rather than tokenize()) so that
    /// `.LineComment` and `.BlockComment` tokens are preserved in the stream —
    /// tokenize() strips them, which would make the formatter eat all comments.
    ///
    /// If the lexer encounters an error (unterminated string, unexpected char,
    /// etc.), falls back to `formatWithErrorRecovery` which does best-effort
    /// line-by-line formatting and annotates problem lines with `fr fr` comments.
    pub fn format(self: *Formatter, source: []const u8) ![]const u8 {
        self.output.clearRetainingCapacity();

        var token_lexer = lexer.Lexer.init(self.allocator, source);

        var tokens = ArrayList(lexer.Token){};
        defer tokens.deinit(self.allocator);

        while (true) {
            const token = token_lexer.nextToken() catch |err| {
                switch (err) {
                    error.UnexpectedCharacter,
                    error.UnterminatedString,
                    error.UnterminatedBlockComment => {
                        return self.formatWithErrorRecovery(source, err);
                    },
                    else => return err,
                }
            };
            try tokens.append(self.allocator, token);
            if (token.kind == .Eof) break;
        }

        var context = FormattingContext{ .config = self.config };
        try self.formatTokens(tokens.items, &context);

        return try self.output.toOwnedSlice(self.allocator);
    }

    /// Main formatting loop. Walks every token and dispatches to the
    /// appropriate format* method. Tracks `at_line_start` to know when
    /// to emit indentation before the next non-whitespace token.
    fn formatTokens(self: *Formatter, tokens: []const lexer.Token, context: *FormattingContext) !void {
        var i: usize = 0;
        var at_line_start = true;

        while (i < tokens.len) {
            const token = tokens[i];

            if (at_line_start and token.kind != .Newline and token.kind != .Eof) {
                const indent = try context.getIndent(self.allocator);
                defer self.allocator.free(indent);
                try self.output.appendSlice(self.allocator, indent);
                context.line_length = @as(u32, @intCast(indent.len));
                at_line_start = false;
            }

            switch (token.kind) {
                .Slay, .Sus, .Facts, .Lowkey, .Highkey, .Periodt, .Stan, .Bestie, .Squad, .Collab, .Yeet, .Later, .Normie, .Drip, .Tea, .Lit, .Smol, .Thicc, .Meal, .Damn, .Yolo, .Fam, .Shook => {
                    try self.formatKeyword(token, context);
                    at_line_start = false;
                },
                .Identifier => {
                    try self.formatIdentifier(token, context);
                    at_line_start = false;
                },
                .LeftBrace => {
                    try self.formatLeftBrace(token, context);
                    at_line_start = true;
                },
                .RightBrace => {
                    try self.formatRightBrace(token, context);
                    at_line_start = true;
                },
                .LeftParen => {
                    try self.formatLeftParen(token, context);
                    at_line_start = false;
                },
                .RightParen => {
                    try self.formatRightParen(token, context);
                    at_line_start = false;
                },
                .Semicolon => {
                    try self.formatSemicolon(token, context);
                    at_line_start = true;
                },
                .Comma => {
                    try self.formatComma(token, context);
                    at_line_start = !context.in_function_params;
                },
                .Equal, .Plus, .Minus, .Star, .Slash, .Percent, .Dot, .BeLike => {
                    try self.formatOperator(token, context);
                    at_line_start = false;
                },
                .StringLiteral => {
                    try self.formatString(token, context);
                    at_line_start = false;
                },
                .Number => {
                    try self.formatNumber(token, context);
                    at_line_start = false;
                },
                .LineComment, .BlockComment => {
                    try self.formatComment(token, context);
                    at_line_start = true;
                },
                .Newline => {
                    // Skip source newlines — the formatter inserts its own
                    at_line_start = true;
                },
                .Eof => break,
                else => {
                    try self.formatDefault(token, context);
                    at_line_start = false;
                },
            }

            i += 1;
        }

        // Guarantee a trailing newline
        if (self.output.items.len > 0 and self.output.items[self.output.items.len - 1] != '\n') {
            try self.output.append(self.allocator, '\n');
        }
    }

    /// Formats a CURSED keyword token. Most keywords get a trailing space so
    /// the next token (identifier, paren, etc.) is separated. Some keywords
    /// also update context flags — e.g., `squad` sets `in_struct_definition`
    /// so that field formatting can be adjusted.
    fn formatKeyword(self: *Formatter, token: lexer.Token, context: *FormattingContext) !void {
        const keyword = token.lexeme;

        if (std.mem.eql(u8, keyword, "slay")) {
            try self.output.appendSlice(self.allocator, "slay ");
            context.line_length += 5;
        } else if (std.mem.eql(u8, keyword, "sus")) {
            try self.output.appendSlice(self.allocator, "sus ");
            context.line_length += 4;
        } else if (std.mem.eql(u8, keyword, "damn") or std.mem.eql(u8, keyword, "yolo")) {
            try self.output.appendSlice(self.allocator, keyword);
            try self.output.append(self.allocator, ' ');
            context.line_length += @as(u32, @intCast(keyword.len + 1));
        } else if (std.mem.eql(u8, keyword, "bestie")) {
            try self.output.appendSlice(self.allocator, "bestie ");
            context.line_length += 7;
        } else if (std.mem.eql(u8, keyword, "lowkey")) {
            try self.output.appendSlice(self.allocator, "lowkey ");
            context.line_length += 7;
        } else if (std.mem.eql(u8, keyword, "stan")) {
            try self.output.appendSlice(self.allocator, "stan ");
            context.line_length += 5;
        } else if (std.mem.eql(u8, keyword, "collab")) {
            try self.output.appendSlice(self.allocator, "collab ");
            context.line_length += 7;
            context.in_interface_definition = true;
        } else if (std.mem.eql(u8, keyword, "squad")) {
            try self.output.appendSlice(self.allocator, "squad ");
            context.line_length += 6;
            context.in_struct_definition = true;
        } else if (std.mem.eql(u8, keyword, "flex")) {
            try self.output.appendSlice(self.allocator, "flex ");
            context.line_length += 5;
        } else {
            try self.output.appendSlice(self.allocator, keyword);
            try self.output.append(self.allocator, ' ');
            context.line_length += @as(u32, @intCast(keyword.len + 1));
        }
    }

    /// Emits an identifier with a leading space if the previous character isn't
    /// already whitespace or an opening delimiter. This prevents tokens from
    /// running together (e.g., `susx` instead of `sus x`).
    fn formatIdentifier(self: *Formatter, token: lexer.Token, context: *FormattingContext) !void {
        if (self.output.items.len > 0) {
            const last_char = self.output.items[self.output.items.len - 1];
            if (last_char != ' ' and last_char != '\n' and last_char != '(' and last_char != '{') {
                try self.output.append(self.allocator, ' ');
                context.line_length += 1;
            }
        }

        try self.output.appendSlice(self.allocator, token.lexeme);
        context.line_length += @as(u32, @intCast(token.lexeme.len));
    }

    /// Emits `{` and increases the indent level. Respects the
    /// `newline_before_brace` config for Allman vs K&R style.
    /// Always emits a newline after the brace.
    fn formatLeftBrace(self: *Formatter, token: lexer.Token, context: *FormattingContext) !void {
        _ = token;
        if (context.config.newline_before_brace) {
            try self.output.appendSlice(self.allocator, "\n");
            const indent = try context.getIndent(self.allocator);
            defer self.allocator.free(indent);
            try self.output.appendSlice(self.allocator, indent);
            context.line_length = @as(u32, @intCast(indent.len));
        } else {
            if (context.line_length > 0 and self.output.items[self.output.items.len - 1] != ' ') {
                try self.output.append(self.allocator, ' ');
                context.line_length += 1;
            }
        }

        try self.output.append(self.allocator, '{');
        context.line_length += 1;
        context.current_indent += 1;

        try self.output.append(self.allocator, '\n');
        context.line_length = 0;
    }

    /// Emits `}` at the decreased indent level. Resets struct/interface
    /// context flags since the block has ended.
    fn formatRightBrace(self: *Formatter, token: lexer.Token, context: *FormattingContext) !void {
        _ = token;
        if (context.current_indent > 0) {
            context.current_indent -= 1;
        }

        if (context.line_length > 0) {
            try self.output.append(self.allocator, '\n');
        }

        const indent = try context.getIndent(self.allocator);
        defer self.allocator.free(indent);
        try self.output.appendSlice(self.allocator, indent);
        try self.output.append(self.allocator, '}');

        context.line_length = @as(u32, @intCast(indent.len + 1));
        context.in_struct_definition = false;
        context.in_interface_definition = false;
    }

    fn formatLeftParen(self: *Formatter, token: lexer.Token, context: *FormattingContext) !void {
        _ = token;
        try self.output.append(self.allocator, '(');
        context.line_length += 1;
        context.in_function_params = true;
    }

    fn formatRightParen(self: *Formatter, token: lexer.Token, context: *FormattingContext) !void {
        _ = token;
        try self.output.append(self.allocator, ')');
        context.line_length += 1;
        context.in_function_params = false;
    }

    /// CURSED uses automatic semicolon insertion, so explicit semicolons are
    /// uncommon. When one appears, we replace it with a newline to normalize
    /// the output rather than preserving a style the language discourages.
    fn formatSemicolon(self: *Formatter, token: lexer.Token, context: *FormattingContext) !void {
        _ = token;
        try self.output.append(self.allocator, '\n');
        context.line_length = 0;
    }

    /// Commas inside function parameter lists get `", "` (inline).
    /// Commas elsewhere (e.g., array literals) get a newline + indent,
    /// putting each element on its own line.
    fn formatComma(self: *Formatter, token: lexer.Token, context: *FormattingContext) !void {
        _ = token;
        try self.output.append(self.allocator, ',');

        if (context.in_function_params) {
            try self.output.append(self.allocator, ' ');
            context.line_length += 2;
        } else {
            try self.output.append(self.allocator, '\n');
            const indent = try context.getIndent(self.allocator);
            defer self.allocator.free(indent);
            try self.output.appendSlice(self.allocator, indent);
            context.line_length = @as(u32, @intCast(indent.len));
        }
    }

    /// Emits an operator with surrounding spaces when `space_around_operators`
    /// is enabled (default). Handles all binary operators including `.Dot`
    /// (member access) and `.BeLike` (`:=` short declaration).
    fn formatOperator(self: *Formatter, token: lexer.Token, context: *FormattingContext) !void {
        const operator = token.lexeme;

        if (context.config.space_around_operators) {
            if (self.output.items.len > 0 and self.output.items[self.output.items.len - 1] != ' ') {
                try self.output.append(self.allocator, ' ');
                context.line_length += 1;
            }

            try self.output.appendSlice(self.allocator, operator);
            try self.output.append(self.allocator, ' ');
            context.line_length += @as(u32, @intCast(operator.len + 1));
        } else {
            try self.output.appendSlice(self.allocator, operator);
            context.line_length += @as(u32, @intCast(operator.len));
        }
    }

    fn formatString(self: *Formatter, token: lexer.Token, context: *FormattingContext) !void {
        try self.output.appendSlice(self.allocator, token.lexeme);
        context.line_length += @as(u32, @intCast(token.lexeme.len));
    }

    fn formatNumber(self: *Formatter, token: lexer.Token, context: *FormattingContext) !void {
        try self.output.appendSlice(self.allocator, token.lexeme);
        context.line_length += @as(u32, @intCast(token.lexeme.len));
    }

    /// Emits a comment followed by a newline. Both `fr fr` line comments and
    /// `no cap ... on god` block comments are preserved verbatim.
    fn formatComment(self: *Formatter, token: lexer.Token, context: *FormattingContext) !void {
        try self.output.appendSlice(self.allocator, token.lexeme);
        try self.output.append(self.allocator, '\n');
        context.line_length = 0;
    }

    /// Catch-all for token kinds without special formatting (e.g., `[`, `]`,
    /// `:`, comparison operators). Emits the lexeme as-is.
    fn formatDefault(self: *Formatter, token: lexer.Token, context: *FormattingContext) !void {
        try self.output.appendSlice(self.allocator, token.lexeme);
        context.line_length += @as(u32, @intCast(token.lexeme.len));
    }

    /// Error recovery fallback when the lexer fails mid-file.
    ///
    /// Instead of failing outright, this produces a best-effort formatted
    /// output where each line is individually assessed. Lines that start with
    /// recognizable CURSED keywords get basic formatting; lines that can't be
    /// safely formatted are passed through verbatim with a `fr fr` annotation.
    ///
    /// The output is bookended with `fr fr` comments explaining the partial
    /// formatting, so the user knows to fix syntax errors and re-run.
    fn formatWithErrorRecovery(self: *Formatter, source: []const u8, original_error: anyerror) ![]const u8 {
        self.output.clearRetainingCapacity();

        try self.output.appendSlice(self.allocator, "fr fr CURSED Formatter: Partial formatting due to syntax errors\n");
        try self.output.appendSlice(self.allocator, "fr fr Original error: ");
        try self.output.appendSlice(self.allocator, @errorName(original_error));
        try self.output.appendSlice(self.allocator, "\n\n");

        var lines = std.mem.splitScalar(u8, source, '\n');
        var line_num: usize = 0;

        while (lines.next()) |line| {
            line_num += 1;
            const trimmed = std.mem.trim(u8, line, " \t\r");

            if (trimmed.len == 0) {
                try self.output.append(self.allocator, '\n');
                continue;
            }

            if (self.isLineFormattable(trimmed)) {
                try self.formatSingleLine(trimmed);
            } else {
                try self.output.appendSlice(self.allocator, "fr fr Line ");
                const line_str = try std.fmt.allocPrint(self.allocator, "{d}", .{line_num});
                defer self.allocator.free(line_str);
                try self.output.appendSlice(self.allocator, line_str);
                try self.output.appendSlice(self.allocator, " - formatting skipped due to syntax error\n");
                try self.output.appendSlice(self.allocator, line);
            }
            try self.output.append(self.allocator, '\n');
        }

        try self.output.appendSlice(self.allocator, "\nfr fr End of partial formatting\n");
        try self.output.appendSlice(self.allocator, "fr fr Please fix syntax errors and re-run formatter\n");

        return try self.output.toOwnedSlice(self.allocator);
    }

    /// Heuristic check for whether a single line can be safely formatted.
    /// Rejects lines with unmatched quotes (would confuse the lexer) and
    /// only accepts lines that start with known CURSED keywords.
    fn isLineFormattable(self: *Formatter, line: []const u8) bool {
        _ = self;

        if (std.mem.indexOf(u8, line, "\"") != null and std.mem.count(u8, line, "\"") % 2 != 0) {
            return false;
        }

        if (std.mem.indexOf(u8, line, "'") != null and std.mem.count(u8, line, "'") % 2 != 0) {
            return false;
        }

        return std.mem.startsWith(u8, line, "fr fr") or
               std.mem.startsWith(u8, line, "sus") or
               std.mem.startsWith(u8, line, "slay") or
               std.mem.startsWith(u8, line, "yeet") or
               std.mem.startsWith(u8, line, "squad") or
               std.mem.startsWith(u8, line, "collab");
    }

    /// Minimal single-line formatter used during error recovery.
    /// Trims whitespace and adds a basic indent for lines containing braces.
    fn formatSingleLine(self: *Formatter, line: []const u8) !void {
        const trimmed = std.mem.trim(u8, line, " \t");

        if (std.mem.indexOf(u8, trimmed, "{") != null) {
            try self.output.appendSlice(self.allocator, "    ");
        }

        try self.output.appendSlice(self.allocator, trimmed);
    }
};

/// Reads a `.💀` file from disk, formats it using the given config,
/// and writes the formatted result back to the same path (in-place).
pub fn formatFile(allocator: Allocator, file_path: []const u8, config: FormatterConfig) !void {
    const file = try std.fs.cwd().openFile(file_path, .{});
    defer file.close();

    const source = try file.readToEndAlloc(allocator, 1024 * 1024);
    defer allocator.free(source);

    var formatter = Formatter.init(allocator, config);
    defer formatter.deinit();

    const formatted = try formatter.format(source);
    defer allocator.free(formatted);

    const output_file = try std.fs.cwd().createFile(file_path, .{});
    defer output_file.close();
    try output_file.writeAll(formatted);

    std.log.info("Formatted: {s}", .{file_path});
}

/// Recursively walks a directory tree and formats every `.💀` file found.
/// Descends into subdirectories. Non-`.💀` files are ignored.
pub fn formatDirectory(allocator: Allocator, dir_path: []const u8, config: FormatterConfig) !void {
    var dir = try std.fs.cwd().openDir(dir_path, .{ .iterate = true });
    defer dir.close();

    var iterator = dir.iterate();
    while (try iterator.next()) |entry| {
        if (entry.kind == .file and std.mem.endsWith(u8, entry.name, ".💀")) {
            const full_path = try std.fs.path.join(allocator, &[_][]const u8{ dir_path, entry.name });
            defer allocator.free(full_path);

            try formatFile(allocator, full_path, config);
        } else if (entry.kind == .directory) {
            const sub_dir = try std.fs.path.join(allocator, &[_][]const u8{ dir_path, entry.name });
            defer allocator.free(sub_dir);

            try formatDirectory(allocator, sub_dir, config);
        }
    }
}

/// CLI entry point. Accepts a file path or directory as the first argument
/// and formats all `.💀` files found. Uses default `FormatterConfig`.
///
/// Usage: `cursed-fmt <file or directory>`
pub fn main() !void {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    const args = try std.process.argsAlloc(allocator);
    defer std.process.argsFree(allocator, args);

    if (args.len < 2) {
        std.log.err("Usage: cursed-fmt <file or directory>", .{});
        return;
    }

    const config = FormatterConfig{};
    const target = args[1];

    const stat = std.fs.cwd().statFile(target) catch |err| {
        std.log.err("Error accessing {s}: {}", .{ target, err });
        return;
    };

    if (stat.kind == .file) {
        try formatFile(allocator, target, config);
    } else if (stat.kind == .directory) {
        try formatDirectory(allocator, target, config);
    } else {
        std.log.err("{s} is not a file or directory", .{target});
    }
}
