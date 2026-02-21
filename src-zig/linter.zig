const std = @import("std");
const ArrayList = std.ArrayList;
const Allocator = std.mem.Allocator;
const lexer = @import("lexer.zig");
const parser = @import("parser.zig");
const ast = @import("ast.zig");

/// Issue severity levels, ordered from most to least critical.
/// Used by `LintIssue` and can be overridden per-rule in `LinterConfig`.
pub const Severity = enum {
    Error,
    Warning,
    Info,
    Hint,

    pub fn toString(self: Severity) []const u8 {
        return switch (self) {
            .Error => "error",
            .Warning => "warning",
            .Info => "info",
            .Hint => "hint",
        };
    }
};

/// Tracks a declared variable's location and usage status for the
/// unused-variable detection rule (currently a TODO stub).
const VariableInfo = struct {
    name: []const u8,
    line: u32,
    column: u32,
    used: bool = false,
    is_parameter: bool = false,
};

/// Broad categories that lint rules belong to. Each rule reports its
/// category so that output can be filtered or grouped by concern.
pub const RuleCategory = enum {
    Style,
    Performance,
    Security,
    Correctness,
    BestPractice,
    GenZSyntax,

    pub fn toString(self: RuleCategory) []const u8 {
        return switch (self) {
            .Style => "style",
            .Performance => "performance",
            .Security => "security",
            .Correctness => "correctness",
            .BestPractice => "best-practice",
            .GenZSyntax => "gen-z-syntax",
        };
    }
};

/// A single lint finding. Carries the rule ID (for filtering/overrides),
/// severity, category, a human-readable message, source location, and an
/// optional fix suggestion string.
pub const LintIssue = struct {
    rule_id: []const u8,
    severity: Severity,
    category: RuleCategory,
    message: []const u8,
    file: []const u8,
    line: u32,
    column: u32,
    suggestion: ?[]const u8 = null,
};

/// Per-run linter configuration. Allows individual rules to be toggled
/// on/off via `enabled_rules` and their severity to be overridden via
/// `severity_overrides`. Both maps are keyed by rule ID strings
/// (e.g., "line-too-long", "deprecated-keyword").
pub const LinterConfig = struct {
    allocator: Allocator,
    enabled_rules: std.StringHashMap(bool),
    severity_overrides: std.StringHashMap(Severity),
    max_line_length: u32 = 100,
    max_function_length: u32 = 50,
    /// When true, the linter checks for traditional keywords (e.g., `return`,
    /// `while`) and suggests their Gen Z equivalents (`damn`, `periodt`).
    enforce_gen_z_syntax: bool = true,

    pub fn init(allocator: Allocator) LinterConfig {
        return LinterConfig{
            .allocator = allocator,
            .enabled_rules = std.StringHashMap(bool).init(allocator),
            .severity_overrides = std.StringHashMap(Severity).init(allocator),
        };
    }

    pub fn deinit(self: *LinterConfig) void {
        self.enabled_rules.deinit();
        self.severity_overrides.deinit();
    }
};

/// Static analysis linter for CURSED `.💀` source files.
///
/// Runs the full lexer → parser → AST pipeline, then applies five
/// categories of lint rules against the resulting tokens and AST:
///
///   - **Style**: line length, indentation consistency, trailing whitespace,
///     naming conventions (snake_case for functions, PascalCase for structs).
///   - **Performance**: unused variables, string concatenation in loops (stubs).
///   - **Security**: hardcoded secrets/API keys/passwords, insecure hash functions,
///     unsafe memory operations, SQL injection patterns, buffer overflow risks,
///     weak encryption, missing defer cleanup, unhandled errors, channel deadlocks.
///   - **Correctness**: unreachable code, infinite loops (stub).
///   - **GenZSyntax**: flags traditional keywords that should use CURSED equivalents,
///     warns on mixed Gen Z / traditional style.
///
/// All issues are collected into an `ArrayList(LintIssue)` and can be
/// retrieved via `getIssues()` for display or programmatic consumption.
///
/// Usage:
///   var config = LinterConfig.init(allocator);
///   defer config.deinit();
///   var linter = Linter.init(allocator, config);
///   defer linter.deinit();
///   try linter.lintFile("path/to/file.💀");
///   const issues = linter.getIssues();
pub const Linter = struct {
    allocator: Allocator,
    config: LinterConfig,
    issues: ArrayList(LintIssue),

    pub fn init(allocator: Allocator, config: LinterConfig) Linter {
        return Linter{
            .allocator = allocator,
            .config = config,
            .issues = ArrayList(LintIssue){},
        };
    }

    pub fn deinit(self: *Linter) void {
        self.issues.deinit(self.allocator);
    }

    /// Reads a file from disk and lints it. Convenience wrapper around `lintSource`.
    pub fn lintFile(self: *Linter, file_path: []const u8) !void {
        const file = try std.fs.cwd().openFile(file_path, .{});
        defer file.close();

        const source = try file.readToEndAlloc(self.allocator, 1024 * 1024);
        defer self.allocator.free(source);

        try self.lintSource(file_path, source);
    }

    /// Lints CURSED source code provided as a string.
    ///
    /// Runs the lexer to get tokens, then the parser to get an AST. If
    /// parsing fails, a single "parse-error" issue is recorded and the
    /// method returns early (AST-dependent rules are skipped). Otherwise
    /// all five rule categories are applied.
    pub fn lintSource(self: *Linter, file_path: []const u8, source: []const u8) !void {
        var token_lexer = lexer.Lexer.init(self.allocator, source);

        const tokens = try token_lexer.tokenize();
        defer {
            var t = tokens;
            t.deinit(self.allocator);
        }

        var cursed_parser = parser.Parser.init(self.allocator, tokens.items);
        defer cursed_parser.deinit();

        const ast_tree = cursed_parser.parseProgram() catch {
            try self.addIssue(LintIssue{
                .rule_id = "parse-error",
                .severity = .Error,
                .category = .Correctness,
                .message = "Failed to parse CURSED code",
                .file = file_path,
                .line = 1,
                .column = 1,
            });
            return;
        };

        try self.runStyleRules(file_path, source, tokens.items);
        try self.runPerformanceRules(file_path, ast_tree);
        try self.runSecurityRules(file_path, ast_tree);
        try self.runCorrectnessRules(file_path, ast_tree);
        try self.runGenZSyntaxRules(file_path, tokens.items);
    }

    /// Returns all issues found so far. The slice is valid until the
    /// linter is deinitialized or new issues are appended (which may
    /// reallocate the backing buffer).
    pub fn getIssues(self: *const Linter) []const LintIssue {
        return self.issues.items;
    }

    /// Records an issue, respecting `enabled_rules` (skip if rule is disabled)
    /// and `severity_overrides` (replace severity if overridden).
    fn addIssue(self: *Linter, issue: LintIssue) !void {
        if (self.config.enabled_rules.get(issue.rule_id)) |enabled| {
            if (!enabled) return;
        }

        var final_issue = issue;
        if (self.config.severity_overrides.get(issue.rule_id)) |severity| {
            final_issue.severity = severity;
        }

        try self.issues.append(self.allocator, final_issue);
    }

    // ── Style rules ─────────────────────────────────────────────────────

    fn runStyleRules(self: *Linter, file_path: []const u8, source: []const u8, tokens: []const lexer.Token) !void {
        try self.checkLineLength(file_path, source);
        try self.checkIndentation(file_path, source);
        try self.checkTrailingWhitespace(file_path, source);
        try self.checkNamingConventions(file_path, tokens);
    }

    /// Flags lines exceeding `config.max_line_length`.
    fn checkLineLength(self: *Linter, file_path: []const u8, source: []const u8) !void {
        var line_number: u32 = 1;
        var line_start: usize = 0;

        for (source, 0..) |char, i| {
            if (char == '\n') {
                const line_length = i - line_start;
                if (line_length > self.config.max_line_length) {
                    try self.addIssue(LintIssue{
                        .rule_id = "line-too-long",
                        .severity = .Warning,
                        .category = .Style,
                        .message = try std.fmt.allocPrint(self.allocator, "Line too long ({} > {})", .{ line_length, self.config.max_line_length }),
                        .file = file_path,
                        .line = line_number,
                        .column = @as(u32, @intCast(line_length + 1)),
                        .suggestion = "Consider breaking this line into multiple lines",
                    });
                }
                line_number += 1;
                line_start = i + 1;
            }
        }
    }

    /// Warns on mixed tabs/spaces and indentation that isn't a multiple of 4 spaces.
    fn checkIndentation(self: *Linter, file_path: []const u8, source: []const u8) !void {
        var line_number: u32 = 1;

        for (source, 0..) |char, i| {
            if (char == '\n') {
                if (i + 1 < source.len) {
                    var spaces: u32 = 0;
                    var tabs: u32 = 0;
                    var j = i + 1;

                    while (j < source.len and (source[j] == ' ' or source[j] == '\t')) {
                        if (source[j] == ' ') spaces += 1;
                        if (source[j] == '\t') tabs += 1;
                        j += 1;
                    }

                    if (spaces > 0 and tabs > 0) {
                        try self.addIssue(LintIssue{
                            .rule_id = "mixed-indentation",
                            .severity = .Warning,
                            .category = .Style,
                            .message = "Mixed spaces and tabs for indentation",
                            .file = file_path,
                            .line = line_number + 1,
                            .column = 1,
                            .suggestion = "Use either spaces or tabs consistently",
                        });
                    }

                    if (spaces > 0 and spaces % 4 != 0) {
                        try self.addIssue(LintIssue{
                            .rule_id = "inconsistent-indentation",
                            .severity = .Info,
                            .category = .Style,
                            .message = "Indentation should be multiples of 4 spaces",
                            .file = file_path,
                            .line = line_number + 1,
                            .column = 1,
                            .suggestion = "Use 4-space indentation",
                        });
                    }
                }

                line_number += 1;
            }
        }
    }

    fn checkTrailingWhitespace(self: *Linter, file_path: []const u8, source: []const u8) !void {
        var line_number: u32 = 1;
        var line_start: usize = 0;

        for (source, 0..) |char, i| {
            if (char == '\n') {
                if (i > line_start and (source[i - 1] == ' ' or source[i - 1] == '\t')) {
                    try self.addIssue(LintIssue{
                        .rule_id = "trailing-whitespace",
                        .severity = .Info,
                        .category = .Style,
                        .message = "Trailing whitespace",
                        .file = file_path,
                        .line = line_number,
                        .column = @as(u32, @intCast(i - line_start)),
                        .suggestion = "Remove trailing whitespace",
                    });
                }
                line_number += 1;
                line_start = i + 1;
            }
        }
    }

    /// Checks naming conventions by looking at identifiers that immediately
    /// follow `slay` (function names → snake_case) or `squad` (struct names
    /// → PascalCase). Uses a simple token-position heuristic rather than AST
    /// because the token stream is sufficient here.
    fn checkNamingConventions(self: *Linter, file_path: []const u8, tokens: []const lexer.Token) !void {
        for (tokens) |token| {
            if (token.kind == .Identifier) {
                const name = token.lexeme;

                if (self.isAfterKeyword(tokens, token, "slay")) {
                    if (!self.isSnakeCase(name)) {
                        try self.addIssue(LintIssue{
                            .rule_id = "function-naming",
                            .severity = .Warning,
                            .category = .Style,
                            .message = "Function names should use snake_case",
                            .file = file_path,
                            .line = @intCast(token.line),
                            .column = @intCast(token.column),
                            .suggestion = try self.toSnakeCase(name),
                        });
                    }
                }

                if (self.isAfterKeyword(tokens, token, "squad")) {
                    if (!self.isPascalCase(name)) {
                        try self.addIssue(LintIssue{
                            .rule_id = "struct-naming",
                            .severity = .Warning,
                            .category = .Style,
                            .message = "Struct names should use PascalCase",
                            .file = file_path,
                            .line = @intCast(token.line),
                            .column = @intCast(token.column),
                            .suggestion = try self.toPascalCase(name),
                        });
                    }
                }
            }
        }
    }

    // ── Performance rules ───────────────────────────────────────────────

    fn runPerformanceRules(self: *Linter, file_path: []const u8, ast_tree: ast.Program) !void {
        try self.checkUnusedVariables(file_path, ast_tree);
        try self.checkStringConcatenation(file_path, ast_tree);
    }

    fn checkUnusedVariables(self: *Linter, file_path: []const u8, ast_tree: ast.Program) !void {
        _ = self;
        _ = ast_tree;
        _ = file_path;
        // TODO: Walk AST Let/ShortDeclaration nodes, collect declared names,
        // then scan Identifier expressions to mark them used. Report unused.
    }

    fn checkStringConcatenation(self: *Linter, file_path: []const u8, ast_tree: ast.Program) !void {
        _ = self;
        _ = file_path;
        _ = ast_tree;
        // TODO: Detect string concatenation inside loops and suggest
        // using stringz.join or a builder pattern instead.
    }

    // ── Security rules ──────────────────────────────────────────────────
    //
    // These rules walk the AST looking for patterns that indicate security
    // issues: hardcoded credentials, insecure function calls, missing error
    // handling, etc. Each rule has a "visit" function that recursively
    // descends into function bodies and statement blocks.
    //
    // Note: The `.Expression` variant in ast.Statement is a value type (not
    // a pointer), so we use `var expr_copy = expr_val; &expr_copy` to get
    // a pointer for the check functions.

    fn runSecurityRules(self: *Linter, file_path: []const u8, ast_tree: ast.Program) !void {
        try self.checkHardcodedSecrets(file_path, ast_tree);
        try self.checkUnsafeOperations(file_path, ast_tree);
        try self.checkBufferOverflows(file_path, ast_tree);
        try self.checkInsecureCrypto(file_path, ast_tree);
        try self.checkMemorySafety(file_path, ast_tree);
        try self.checkErrorHandling(file_path, ast_tree);
        try self.checkChannelSafety(file_path, ast_tree);
    }

    /// Walks the AST looking for string literals assigned to variables or
    /// passed to functions that look like API keys, passwords, private keys,
    /// or database connection strings.
    fn checkHardcodedSecrets(self: *Linter, file_path: []const u8, ast_tree: ast.Program) !void {
        for (ast_tree.statements.items) |stmt_ptr| {
            try self.visitForSecrets(stmt_ptr, file_path);
        }
    }

    fn visitForSecrets(self: *Linter, stmt_ptr: *ast.Statement, file_path: []const u8) !void {
        switch (stmt_ptr.*) {
            .Let => |let_stmt| {
                if (let_stmt.initializer) |init_ptr| {
                    const init_expr: *ast.Expression = @ptrCast(@alignCast(init_ptr));
                    try self.checkExpressionForSecrets(init_expr, file_path, let_stmt.name);
                }
            },
            .Assignment => |assign_stmt| {
                const val_expr: *ast.Expression = @ptrCast(@alignCast(assign_stmt.value));
                try self.checkExpressionForSecrets(val_expr, file_path, "assignment");
            },
            .Function => |func_stmt| {
                for (func_stmt.body.items) |body_stmt| {
                    try self.visitForSecrets(body_stmt, file_path);
                }
            },
            .ShortDeclaration => |short_decl| {
                for (short_decl.values.items) |value| {
                    const val_expr: *ast.Expression = @ptrCast(@alignCast(value));
                    try self.checkExpressionForSecrets(val_expr, file_path, "variable");
                }
            },
            else => {},
        }
    }

    /// Inspects an expression for secret-like strings. Also flags insecure
    /// hash functions (md5, sha1) and dangerous system calls (system, exec)
    /// when found in call expressions, and recurses into call arguments.
    fn checkExpressionForSecrets(self: *Linter, expr: *ast.Expression, file_path: []const u8, context: []const u8) !void {
        switch (expr.*) {
            .String => |string_val| {
                try self.analyzeStringForSecrets(string_val, file_path, context);
            },
            .Call => |call| {
                const func_expr: *ast.Expression = @ptrCast(@alignCast(call.function));
                if (func_expr.* == .Identifier) {
                    const func_name = func_expr.Identifier;

                    if (std.mem.eql(u8, func_name, "md5") or std.mem.eql(u8, func_name, "sha1")) {
                        try self.addIssue(LintIssue{
                            .rule_id = "insecure-hash",
                            .severity = .Error,
                            .category = .Security,
                            .message = try std.fmt.allocPrint(self.allocator, "Insecure hash function '{s}' should not be used", .{func_name}),
                            .file = file_path,
                            .line = 1,
                            .column = 1,
                            .suggestion = "Use sha256 or stronger hash functions",
                        });
                    }

                    if (std.mem.eql(u8, func_name, "system") or std.mem.eql(u8, func_name, "exec")) {
                        try self.addIssue(LintIssue{
                            .rule_id = "dangerous-system-call",
                            .severity = .Error,
                            .category = .Security,
                            .message = try std.fmt.allocPrint(self.allocator, "Dangerous system call '{s}' detected", .{func_name}),
                            .file = file_path,
                            .line = 1,
                            .column = 1,
                            .suggestion = "Validate input and use safer alternatives",
                        });
                    }
                }

                for (call.arguments.items) |arg| {
                    const arg_expr: *ast.Expression = @ptrCast(@alignCast(arg));
                    try self.checkExpressionForSecrets(arg_expr, file_path, "function_argument");
                }
            },
            else => {},
        }
    }

    /// Heuristic analysis of a string literal for secret-like content.
    /// Checks for common API key prefixes (AWS, GitHub, generic `sk_`/`api_`),
    /// password-like patterns, PEM private keys, and database connection URIs.
    fn analyzeStringForSecrets(self: *Linter, value: []const u8, file_path: []const u8, context: []const u8) !void {
        if (self.looksLikeApiKey(value)) {
            try self.addIssue(LintIssue{
                .rule_id = "hardcoded-api-key",
                .severity = .Error,
                .category = .Security,
                .message = try std.fmt.allocPrint(self.allocator, "Potential hardcoded API key in {s}", .{context}),
                .file = file_path,
                .line = 1,
                .column = 1,
                .suggestion = "Use environment variables or secure configuration",
            });
        }

        if (self.looksLikePassword(value)) {
            try self.addIssue(LintIssue{
                .rule_id = "hardcoded-password",
                .severity = .Error,
                .category = .Security,
                .message = try std.fmt.allocPrint(self.allocator, "Potential hardcoded password in {s}", .{context}),
                .file = file_path,
                .line = 1,
                .column = 1,
                .suggestion = "Use secure credential storage",
            });
        }

        if (self.looksLikePrivateKey(value)) {
            try self.addIssue(LintIssue{
                .rule_id = "hardcoded-private-key",
                .severity = .Error,
                .category = .Security,
                .message = "Private key detected in source code",
                .file = file_path,
                .line = 1,
                .column = 1,
                .suggestion = "Move private keys to secure key management",
            });
        }

        if (std.mem.indexOf(u8, value, "://") != null and
           (std.mem.indexOf(u8, value, "mysql") != null or
            std.mem.indexOf(u8, value, "postgres") != null or
            std.mem.indexOf(u8, value, "mongodb") != null)) {
            try self.addIssue(LintIssue{
                .rule_id = "hardcoded-db-connection",
                .severity = .Warning,
                .category = .Security,
                .message = "Database connection string may contain credentials",
                .file = file_path,
                .line = 1,
                .column = 1,
                .suggestion = "Use environment variables for database configuration",
            });
        }
    }

    /// Flags unsafe C-style memory operations (malloc, free, memcpy) and
    /// potential SQL injection via string concatenation in query/execute calls.
    fn checkUnsafeOperations(self: *Linter, file_path: []const u8, ast_tree: ast.Program) !void {
        for (ast_tree.statements.items) |stmt_ptr| {
            try self.visitForUnsafeOps(stmt_ptr, file_path);
        }
    }

    fn visitForUnsafeOps(self: *Linter, stmt_ptr: *ast.Statement, file_path: []const u8) !void {
        switch (stmt_ptr.*) {
            .Function => |func_stmt| {
                for (func_stmt.body.items) |body_stmt| {
                    try self.visitForUnsafeOps(body_stmt, file_path);
                }
            },
            .Expression => |expr_val| {
                var expr_copy = expr_val;
                try self.checkUnsafeExpression(&expr_copy, file_path);
            },
            else => {},
        }
    }

    fn checkUnsafeExpression(self: *Linter, expr: *ast.Expression, file_path: []const u8) !void {
        switch (expr.*) {
            .Call => |call| {
                const func_expr: *ast.Expression = @ptrCast(@alignCast(call.function));
                if (func_expr.* == .Identifier) {
                    const func_name = func_expr.Identifier;

                    if (std.mem.eql(u8, func_name, "malloc") or
                       std.mem.eql(u8, func_name, "free") or
                       std.mem.eql(u8, func_name, "memcpy")) {
                        try self.addIssue(LintIssue{
                            .rule_id = "unsafe-memory-operation",
                            .severity = .Warning,
                            .category = .Security,
                            .message = try std.fmt.allocPrint(self.allocator, "Unsafe memory operation '{s}' - use CURSED's memory management", .{func_name}),
                            .file = file_path,
                            .line = 1,
                            .column = 1,
                            .suggestion = "Use CURSED's built-in memory safety features",
                        });
                    }

                    if (std.mem.eql(u8, func_name, "query") or std.mem.eql(u8, func_name, "execute")) {
                        for (call.arguments.items) |arg| {
                            const arg_expr: *ast.Expression = @ptrCast(@alignCast(arg));
                            if (self.containsStringConcatenationExpr(arg_expr)) {
                                try self.addIssue(LintIssue{
                                    .rule_id = "sql-injection-risk",
                                    .severity = .Error,
                                    .category = .Security,
                                    .message = "Potential SQL injection - avoid string concatenation in queries",
                                    .file = file_path,
                                    .line = 1,
                                    .column = 1,
                                    .suggestion = "Use parameterized queries",
                                });
                            }
                        }
                    }
                }
            },
            else => {},
        }
    }

    /// Flags unchecked array accesses and C-style buffer-unsafe functions
    /// (strcpy, strcat, sprintf).
    fn checkBufferOverflows(self: *Linter, file_path: []const u8, ast_tree: ast.Program) !void {
        for (ast_tree.statements.items) |stmt_ptr| {
            try self.visitForBufferOverflows(stmt_ptr, file_path);
        }
    }

    fn visitForBufferOverflows(self: *Linter, stmt_ptr: *ast.Statement, file_path: []const u8) !void {
        switch (stmt_ptr.*) {
            .Function => |func_stmt| {
                for (func_stmt.body.items) |body_stmt| {
                    try self.visitForBufferOverflows(body_stmt, file_path);
                }
            },
            .Expression => |expr_val| {
                var expr_copy = expr_val;
                try self.checkBufferOverflowExpression(&expr_copy, file_path);
            },
            else => {},
        }
    }

    fn checkBufferOverflowExpression(self: *Linter, expr: *ast.Expression, file_path: []const u8) !void {
        switch (expr.*) {
            .ArrayAccess => {
                try self.addIssue(LintIssue{
                    .rule_id = "unchecked-array-access",
                    .severity = .Warning,
                    .category = .Security,
                    .message = "Array access should include bounds checking",
                    .file = file_path,
                    .line = 1,
                    .column = 1,
                    .suggestion = "Add bounds check: lowkey (index < len(array))",
                });
            },
            .Call => |call| {
                const func_expr: *ast.Expression = @ptrCast(@alignCast(call.function));
                if (func_expr.* == .Identifier) {
                    const func_name = func_expr.Identifier;

                    if (std.mem.eql(u8, func_name, "strcpy") or
                       std.mem.eql(u8, func_name, "strcat") or
                       std.mem.eql(u8, func_name, "sprintf")) {
                        try self.addIssue(LintIssue{
                            .rule_id = "buffer-overflow-risk",
                            .severity = .Error,
                            .category = .Security,
                            .message = try std.fmt.allocPrint(self.allocator, "Function '{s}' is prone to buffer overflows", .{func_name}),
                            .file = file_path,
                            .line = 1,
                            .column = 1,
                            .suggestion = "Use safe string functions with bounds checking",
                        });
                    }
                }
            },
            else => {},
        }
    }

    /// Flags weak encryption algorithms (DES, RC4), non-cryptographic RNG
    /// (rand/srand), and hardcoded encryption keys or IVs passed as string
    /// literals to encrypt functions.
    fn checkInsecureCrypto(self: *Linter, file_path: []const u8, ast_tree: ast.Program) !void {
        for (ast_tree.statements.items) |stmt_ptr| {
            try self.visitForInsecureCrypto(stmt_ptr, file_path);
        }
    }

    fn visitForInsecureCrypto(self: *Linter, stmt_ptr: *ast.Statement, file_path: []const u8) !void {
        switch (stmt_ptr.*) {
            .Function => |func_stmt| {
                for (func_stmt.body.items) |body_stmt| {
                    try self.visitForInsecureCrypto(body_stmt, file_path);
                }
            },
            .Expression => |expr_val| {
                var expr_copy = expr_val;
                try self.checkCryptoExpression(&expr_copy, file_path);
            },
            else => {},
        }
    }

    fn checkCryptoExpression(self: *Linter, expr: *ast.Expression, file_path: []const u8) !void {
        switch (expr.*) {
            .Call => |call| {
                const func_expr: *ast.Expression = @ptrCast(@alignCast(call.function));
                if (func_expr.* == .Identifier) {
                    const func_name = func_expr.Identifier;

                    if (std.mem.eql(u8, func_name, "des_encrypt") or
                       std.mem.eql(u8, func_name, "rc4_encrypt")) {
                        try self.addIssue(LintIssue{
                            .rule_id = "weak-encryption",
                            .severity = .Error,
                            .category = .Security,
                            .message = try std.fmt.allocPrint(self.allocator, "Weak encryption algorithm '{s}' should not be used", .{func_name}),
                            .file = file_path,
                            .line = 1,
                            .column = 1,
                            .suggestion = "Use AES-GCM or ChaCha20-Poly1305",
                        });
                    }

                    if (std.mem.eql(u8, func_name, "rand") or std.mem.eql(u8, func_name, "srand")) {
                        try self.addIssue(LintIssue{
                            .rule_id = "weak-random",
                            .severity = .Warning,
                            .category = .Security,
                            .message = "Standard random functions are not cryptographically secure",
                            .file = file_path,
                            .line = 1,
                            .column = 1,
                            .suggestion = "Use cryptographically secure random from stdlib/cryptz",
                        });
                    }

                    if (std.mem.eql(u8, func_name, "aes_encrypt") or std.mem.eql(u8, func_name, "encrypt")) {
                        for (call.arguments.items) |arg| {
                            const arg_expr: *ast.Expression = @ptrCast(@alignCast(arg));
                            if (arg_expr.* == .String) {
                                try self.addIssue(LintIssue{
                                    .rule_id = "hardcoded-crypto-key",
                                    .severity = .Error,
                                    .category = .Security,
                                    .message = "Encryption key/IV should not be hardcoded",
                                    .file = file_path,
                                    .line = 1,
                                    .column = 1,
                                    .suggestion = "Generate random IV and store keys securely",
                                });
                            }
                        }
                    }
                }
            },
            else => {},
        }
    }

    /// Checks that functions which allocate resources (file_open, malloc,
    /// connect, allocate) have at least one `defer` statement for cleanup.
    /// Missing defer suggests a potential resource leak.
    fn checkMemorySafety(self: *Linter, file_path: []const u8, ast_tree: ast.Program) !void {
        for (ast_tree.statements.items) |stmt_ptr| {
            try self.visitForMemorySafety(stmt_ptr, file_path);
        }
    }

    fn visitForMemorySafety(self: *Linter, stmt_ptr: *ast.Statement, file_path: []const u8) !void {
        switch (stmt_ptr.*) {
            .Function => |func_stmt| {
                var has_resource_allocation = false;
                var has_defer = false;

                for (func_stmt.body.items) |body_stmt| {
                    switch (body_stmt.*) {
                        .Expression => |expr_val| {
                            var expr_copy = expr_val;
                            if (self.allocatesResources(&expr_copy)) {
                                has_resource_allocation = true;
                            }
                        },
                        .Defer => {
                            has_defer = true;
                        },
                        else => {},
                    }
                    try self.visitForMemorySafety(body_stmt, file_path);
                }

                if (has_resource_allocation and !has_defer) {
                    try self.addIssue(LintIssue{
                        .rule_id = "missing-defer-cleanup",
                        .severity = .Warning,
                        .category = .Security,
                        .message = "Function allocates resources but lacks defer cleanup",
                        .file = file_path,
                        .line = 1,
                        .column = 1,
                        .suggestion = "Add defer statements for resource cleanup",
                    });
                }
            },
            else => {},
        }
    }

    /// Flags calls to functions that commonly fail (file_open, network_connect,
    /// parse_json) when they appear outside a `fam/shook` (try/catch) block.
    /// Currently uses a simple heuristic — it flags any bare call to these
    /// functions without checking the enclosing statement context.
    fn checkErrorHandling(self: *Linter, file_path: []const u8, ast_tree: ast.Program) !void {
        for (ast_tree.statements.items) |stmt_ptr| {
            try self.visitForErrorHandling(stmt_ptr, file_path);
        }
    }

    fn visitForErrorHandling(self: *Linter, stmt_ptr: *ast.Statement, file_path: []const u8) !void {
        switch (stmt_ptr.*) {
            .Function => |func_stmt| {
                for (func_stmt.body.items) |body_stmt| {
                    try self.visitForErrorHandling(body_stmt, file_path);
                }
            },
            .Expression => |expr_val| {
                var expr_copy = expr_val;
                try self.checkErrorHandlingExpression(&expr_copy, file_path);
            },
            else => {},
        }
    }

    fn checkErrorHandlingExpression(self: *Linter, expr: *ast.Expression, file_path: []const u8) !void {
        switch (expr.*) {
            .Call => |call| {
                const func_expr: *ast.Expression = @ptrCast(@alignCast(call.function));
                if (func_expr.* == .Identifier) {
                    const func_name = func_expr.Identifier;

                    if (std.mem.eql(u8, func_name, "file_open") or
                       std.mem.eql(u8, func_name, "network_connect") or
                       std.mem.eql(u8, func_name, "parse_json")) {
                        try self.addIssue(LintIssue{
                            .rule_id = "unhandled-error",
                            .severity = .Warning,
                            .category = .Security,
                            .message = try std.fmt.allocPrint(self.allocator, "Function '{s}' can fail but error handling not visible", .{func_name}),
                            .file = file_path,
                            .line = 1,
                            .column = 1,
                            .suggestion = "Check error return values or use fam/shook",
                        });
                    }
                }
            },
            else => {},
        }
    }

    /// Warns about channel send/receive operations that could block
    /// indefinitely, suggesting buffered channels or timeouts.
    fn checkChannelSafety(self: *Linter, file_path: []const u8, ast_tree: ast.Program) !void {
        for (ast_tree.statements.items) |stmt_ptr| {
            try self.visitForChannelSafety(stmt_ptr, file_path);
        }
    }

    fn visitForChannelSafety(self: *Linter, stmt_ptr: *ast.Statement, file_path: []const u8) !void {
        switch (stmt_ptr.*) {
            .Function => |func_stmt| {
                for (func_stmt.body.items) |body_stmt| {
                    try self.visitForChannelSafety(body_stmt, file_path);
                }
            },
            .Expression => |expr_val| {
                var expr_copy = expr_val;
                try self.checkChannelSafetyExpression(&expr_copy, file_path);
            },
            else => {},
        }
    }

    fn checkChannelSafetyExpression(self: *Linter, expr: *ast.Expression, file_path: []const u8) !void {
        switch (expr.*) {
            .ChannelSend => {
                try self.addIssue(LintIssue{
                    .rule_id = "channel-deadlock-risk",
                    .severity = .Info,
                    .category = .Security,
                    .message = "Channel send operation could block indefinitely",
                    .file = file_path,
                    .line = 1,
                    .column = 1,
                    .suggestion = "Consider using buffered channels or timeouts",
                });
            },
            .ChannelReceive => {
                try self.addIssue(LintIssue{
                    .rule_id = "channel-deadlock-risk",
                    .severity = .Info,
                    .category = .Security,
                    .message = "Channel receive operation could block indefinitely",
                    .file = file_path,
                    .line = 1,
                    .column = 1,
                    .suggestion = "Consider using select statements with timeouts",
                });
            },
            else => {},
        }
    }

    // ── Security helper functions ───────────────────────────────────────

    /// Simplified check: any Binary expression in a query argument is treated
    /// as potential string concatenation. A more precise version would check
    /// whether the operator is `+` on string operands.
    fn containsStringConcatenationExpr(self: *Linter, expr: *const ast.Expression) bool {
        _ = self;
        switch (expr.*) {
            .Binary => {
                return true;
            },
            else => return false,
        }
    }

    /// Returns true if a call expression invokes a function known to allocate
    /// resources that need cleanup (file handles, memory, network connections).
    fn allocatesResources(self: *Linter, expr: *ast.Expression) bool {
        _ = self;
        switch (expr.*) {
            .Call => |call| {
                const func_expr: *ast.Expression = @ptrCast(@alignCast(call.function));
                if (func_expr.* == .Identifier) {
                    const func_name = func_expr.Identifier;
                    return std.mem.eql(u8, func_name, "file_open") or
                           std.mem.eql(u8, func_name, "malloc") or
                           std.mem.eql(u8, func_name, "connect") or
                           std.mem.eql(u8, func_name, "allocate");
                }
            },
            else => {},
        }
        return false;
    }

    // ── Correctness rules ───────────────────────────────────────────────

    fn runCorrectnessRules(self: *Linter, file_path: []const u8, ast_tree: ast.Program) !void {
        _ = self;
        _ = file_path;
        _ = ast_tree;
        // TODO: Detect unreachable code after `damn` (return) statements,
        // and infinite `periodt` (while) loops with no break.
    }

    // ── Gen Z syntax rules ──────────────────────────────────────────────

    fn runGenZSyntaxRules(self: *Linter, file_path: []const u8, tokens: []const lexer.Token) !void {
        if (!self.config.enforce_gen_z_syntax) return;

        try self.checkDeprecatedKeywords(file_path, tokens);
        try self.checkGenZConsistency(file_path, tokens);
    }

    /// Flags traditional programming keywords and suggests their CURSED
    /// Gen Z equivalents. Mappings: function→slay, var→sus, return→damn,
    /// if→lowkey, while→periodt, struct→squad, interface→collab.
    fn checkDeprecatedKeywords(self: *Linter, file_path: []const u8, tokens: []const lexer.Token) !void {
        const deprecated_mappings = [_]struct { old: []const u8, new: []const u8 }{
            .{ .old = "function", .new = "slay" },
            .{ .old = "var", .new = "sus" },
            .{ .old = "return", .new = "damn" },
            .{ .old = "if", .new = "lowkey" },
            .{ .old = "while", .new = "periodt" },
            .{ .old = "struct", .new = "squad" },
            .{ .old = "interface", .new = "collab" },
        };

        for (tokens) |token| {
            for (deprecated_mappings) |mapping| {
                if (std.mem.eql(u8, token.lexeme, mapping.old)) {
                    try self.addIssue(LintIssue{
                        .rule_id = "deprecated-keyword",
                        .severity = .Warning,
                        .category = .GenZSyntax,
                        .message = try std.fmt.allocPrint(self.allocator, "Use '{s}' instead of '{s}'", .{ mapping.new, mapping.old }),
                        .file = file_path,
                        .line = @intCast(token.line),
                        .column = @intCast(token.column),
                        .suggestion = mapping.new,
                    });
                }
            }
        }
    }

    /// Warns when a file mixes Gen Z keywords (sus, slay, damn, ...) with
    /// traditional keywords (var, function, return, ...). Inconsistent style
    /// makes code harder to read.
    fn checkGenZConsistency(self: *Linter, file_path: []const u8, tokens: []const lexer.Token) !void {
        var has_gen_z: bool = false;
        var has_traditional: bool = false;

        const gen_z_keywords = [_][]const u8{ "sus", "slay", "damn", "lowkey", "highkey", "periodt", "bestie", "based", "cringe", "yeet", "stan", "squad", "collab" };
        const traditional_keywords = [_][]const u8{ "var", "function", "return", "if", "else", "while", "true", "false", "struct", "interface" };

        for (tokens) |token| {
            for (gen_z_keywords) |keyword| {
                if (std.mem.eql(u8, token.lexeme, keyword)) {
                    has_gen_z = true;
                    break;
                }
            }

            for (traditional_keywords) |keyword| {
                if (std.mem.eql(u8, token.lexeme, keyword)) {
                    has_traditional = true;
                    break;
                }
            }
        }

        if (has_gen_z and has_traditional) {
            try self.addIssue(LintIssue{
                .rule_id = "mixed-syntax-style",
                .severity = .Info,
                .category = .GenZSyntax,
                .message = "Mixed Gen Z and traditional syntax",
                .file = file_path,
                .line = 1,
                .column = 1,
                .suggestion = "Use consistent Gen Z syntax throughout",
            });
        }
    }

    // ── Naming / token helper functions ─────────────────────────────────

    /// Returns true if `current` immediately follows a token whose lexeme
    /// matches `keyword`. Used to detect patterns like `slay myFunc` or
    /// `squad MyStruct` without needing the AST.
    fn isAfterKeyword(self: *Linter, tokens: []const lexer.Token, current: lexer.Token, keyword: []const u8) bool {
        _ = self;
        for (tokens, 0..) |token, i| {
            if (std.mem.eql(u8, token.lexeme, current.lexeme) and token.line == current.line and token.column == current.column) {
                if (i > 0 and std.mem.eql(u8, tokens[i - 1].lexeme, keyword)) {
                    return true;
                }
                break;
            }
        }
        return false;
    }

    fn isSnakeCase(self: *Linter, name: []const u8) bool {
        _ = self;
        for (name) |char| {
            if (char >= 'A' and char <= 'Z') return false;
        }
        return true;
    }

    fn isPascalCase(self: *Linter, name: []const u8) bool {
        _ = self;
        if (name.len == 0) return false;
        return name[0] >= 'A' and name[0] <= 'Z';
    }

    /// Converts a camelCase or PascalCase name to snake_case.
    /// E.g., "myFunction" → "my_function".
    fn toSnakeCase(self: *Linter, name: []const u8) ![]const u8 {
        var result = ArrayList(u8){};
        errdefer result.deinit(self.allocator);

        for (name, 0..) |char, i| {
            if (char >= 'A' and char <= 'Z') {
                if (i > 0) try result.append(self.allocator, '_');
                try result.append(self.allocator, char + 32);
            } else {
                try result.append(self.allocator, char);
            }
        }

        return try result.toOwnedSlice(self.allocator);
    }

    /// Converts a snake_case name to PascalCase.
    /// E.g., "my_struct" → "MyStruct".
    fn toPascalCase(self: *Linter, name: []const u8) ![]const u8 {
        var result = ArrayList(u8){};
        errdefer result.deinit(self.allocator);

        var capitalize_next = true;
        for (name) |char| {
            if (char == '_') {
                capitalize_next = true;
            } else if (capitalize_next and char >= 'a' and char <= 'z') {
                try result.append(self.allocator, char - 32);
                capitalize_next = false;
            } else {
                try result.append(self.allocator, char);
                capitalize_next = false;
            }
        }

        return try result.toOwnedSlice(self.allocator);
    }

    // ── Secret detection heuristics ─────────────────────────────────────
    //
    // These functions use pattern matching to identify strings that look
    // like credentials. They check for well-known prefixes (AWS AKIA/ASIA,
    // GitHub ghp_/gho_, generic sk_/api_/token_), length-based heuristics
    // for alphanumeric and hex-encoded keys, and keyword-based detection
    // for passwords and PEM private keys.

    fn looksLikeApiKey(self: *Linter, value: []const u8) bool {
        if (value.len < 16) return false;

        const api_prefixes = [_][]const u8{
            "sk_", "pk_", "ak_", "key_", "api_", "token_", "bearer_", "auth_",
            "secret_", "access_", "client_", "app_", "dev_", "prod_", "test_"
        };
        for (api_prefixes) |prefix| {
            if (std.mem.startsWith(u8, value, prefix)) {
                return true;
            }
        }

        // AWS access key IDs start with AKIA (permanent) or ASIA (temporary)
        if ((std.mem.startsWith(u8, value, "AKIA") or std.mem.startsWith(u8, value, "ASIA")) and value.len >= 20) {
            return true;
        }

        // GitHub personal/OAuth/user/app tokens
        if (std.mem.startsWith(u8, value, "ghp_") or std.mem.startsWith(u8, value, "gho_") or
            std.mem.startsWith(u8, value, "ghu_") or std.mem.startsWith(u8, value, "ghs_")) {
            return true;
        }

        // Long alphanumeric strings are likely API keys
        if (value.len > 20 and value.len < 200 and self.isAlphanumeric(value)) {
            return true;
        }

        // 32-128 char hex strings are likely hashed keys or tokens
        if (value.len >= 32 and value.len <= 128 and self.isHexString(value)) {
            return true;
        }

        return false;
    }

    fn looksLikePassword(self: *Linter, value: []const u8) bool {
        if (value.len < 4) return false;

        const password_patterns = [_][]const u8{
            "password", "passwd", "pwd", "secret", "pass", "auth", "credential",
            "login", "user", "admin", "root", "key", "token", "hash", "salt"
        };
        const lower_value = std.ascii.allocLowerString(self.allocator, value) catch return false;
        defer self.allocator.free(lower_value);

        for (password_patterns) |pattern| {
            if (std.mem.indexOf(u8, lower_value, pattern) != null) {
                if (value.len >= 8 and (self.containsDigits(value) or self.containsSpecialChars(value))) {
                    return true;
                }
                if (std.mem.eql(u8, lower_value, pattern) or
                    std.mem.startsWith(u8, lower_value, pattern)) {
                    return true;
                }
            }
        }
        return false;
    }

    fn looksLikePrivateKey(_: *Linter, value: []const u8) bool {
        // PEM-encoded private keys (RSA, EC, generic, OpenSSH)
        if ((std.mem.indexOf(u8, value, "-----BEGIN") != null and
             std.mem.indexOf(u8, value, "PRIVATE KEY") != null) or
            (std.mem.indexOf(u8, value, "-----BEGIN") != null and
             std.mem.indexOf(u8, value, "RSA PRIVATE KEY") != null) or
            (std.mem.indexOf(u8, value, "-----BEGIN") != null and
             std.mem.indexOf(u8, value, "EC PRIVATE KEY") != null)) {
            return true;
        }

        if (std.mem.indexOf(u8, value, "-----BEGIN OPENSSH PRIVATE KEY-----") != null) {
            return true;
        }

        return false;
    }

    fn isAlphanumeric(_: *Linter, value: []const u8) bool {
        for (value) |char| {
            if (!std.ascii.isAlphanumeric(char) and char != '_' and char != '-') {
                return false;
            }
        }
        return true;
    }

    fn isHexString(_: *Linter, value: []const u8) bool {
        for (value) |char| {
            if (!std.ascii.isHex(char)) {
                return false;
            }
        }
        return true;
    }

    fn containsDigits(_: *Linter, value: []const u8) bool {
        for (value) |char| {
            if (std.ascii.isDigit(char)) {
                return true;
            }
        }
        return false;
    }

    fn containsSpecialChars(_: *Linter, value: []const u8) bool {
        const special_chars = "!@#$%^&*()_+-=[]{}|;:,.<>?";
        for (value) |char| {
            for (special_chars) |special| {
                if (char == special) {
                    return true;
                }
            }
        }
        return false;
    }
};

// ── Output formatting ───────────────────────────────────────────────────

/// Prints lint issues to stderr in the requested format.
/// Supported formats: "human" (default, one line per issue with optional
/// suggestion) and "json" (machine-readable array of issue objects).
pub fn printIssues(allocator: Allocator, issues: []const LintIssue, format: []const u8) !void {
    if (std.mem.eql(u8, format, "json")) {
        try printIssuesJSON(allocator, issues);
    } else {
        try printIssuesHuman(allocator, issues);
    }
}

/// Prints issues in a compiler-style `file:line:col: severity: message [rule]`
/// format, similar to `gcc` or `rustc` output. Each issue optionally includes
/// an indented suggestion line.
fn printIssuesHuman(allocator: Allocator, issues: []const LintIssue) !void {
    _ = allocator;
    const print = std.debug.print;

    for (issues) |issue| {
        print("{s}:{}:{}: {s}: {s} [{s}]\n", .{
            issue.file,
            issue.line,
            issue.column,
            issue.severity.toString(),
            issue.message,
            issue.rule_id,
        });

        if (issue.suggestion) |suggestion| {
            print("  suggestion: {s}\n", .{suggestion});
        }
    }

    print("\nFound {} issues\n", .{issues.len});
}

/// Prints issues as a JSON object with an `issues` array and a `total` count.
/// Each issue includes rule_id, severity, category, message, file, line,
/// column, and optionally suggestion.
fn printIssuesJSON(allocator: Allocator, issues: []const LintIssue) !void {
    _ = allocator;
    const print = std.debug.print;

    print("{{\n  \"issues\": [\n", .{});

    for (issues, 0..) |issue, i| {
        print("    {{\n", .{});
        print("      \"rule_id\": \"{s}\",\n", .{issue.rule_id});
        print("      \"severity\": \"{s}\",\n", .{issue.severity.toString()});
        print("      \"category\": \"{s}\",\n", .{issue.category.toString()});
        print("      \"message\": \"{s}\",\n", .{issue.message});
        print("      \"file\": \"{s}\",\n", .{issue.file});
        print("      \"line\": {},\n", .{issue.line});
        print("      \"column\": {}", .{issue.column});

        if (issue.suggestion) |suggestion| {
            print(",\n      \"suggestion\": \"{s}\"", .{suggestion});
        }

        print("\n    }}", .{});
        if (i < issues.len - 1) print(",", .{});
        print("\n", .{});
    }

    print("  ],\n", .{});
    print("  \"total\": {}\n", .{issues.len});
    print("}}\n", .{});
}

/// CLI entry point. Accepts a file path and an optional `--format json` flag.
///
/// Usage:
///   cursed-lint <file>                  (human-readable output)
///   cursed-lint <file> --format json    (JSON output)
pub fn main() !void {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    const args = try std.process.argsAlloc(allocator);
    defer std.process.argsFree(allocator, args);

    if (args.len < 2) {
        std.log.err("Usage: cursed-lint <file> [--format json]", .{});
        return;
    }

    var config = LinterConfig.init(allocator);
    defer config.deinit();

    var linter_inst = Linter.init(allocator, config);
    defer linter_inst.deinit();

    const file_path = args[1];
    const format = if (args.len > 2 and std.mem.eql(u8, args[2], "--format") and args.len > 3) args[3] else "human";

    try linter_inst.lintFile(file_path);
    const issues = linter_inst.getIssues();

    try printIssues(allocator, issues, format);
}
