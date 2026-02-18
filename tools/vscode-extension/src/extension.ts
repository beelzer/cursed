import * as vscode from 'vscode';
import * as cp from 'child_process';

interface CodeSpellCheckerExtension {
    registerConfig(path: string): Promise<void>;
}

// ── Diagnostics ──────────────────────────────────────────────────────

let diagnosticCollection: vscode.DiagnosticCollection;
let diagnosticDebounce: ReturnType<typeof setTimeout> | undefined;
let outputChannel: vscode.LogOutputChannel;

function runDiagnostics(document: vscode.TextDocument) {
    if (document.languageId !== 'cursed') return;

    const config = vscode.workspace.getConfiguration('cursed');
    const compilerPath = config.get('compiler.path', 'cursed-compiler');
    const filePath = document.fileName;

    const delay = config.get('diagnostics.delay', 500);
    const trace = config.get('trace.compiler', false);

    if (diagnosticDebounce) clearTimeout(diagnosticDebounce);
    diagnosticDebounce = setTimeout(() => {
        const args = ['check', '--json-errors', '--color', 'never', filePath];
        if (trace) {
            outputChannel.info(`Running: ${compilerPath} ${args.join(' ')}`);
        }
        cp.execFile(compilerPath, args, {
            maxBuffer: 1024 * 1024,
            timeout: 10000,
        }, (_error: Error | null, stdout: string, stderr: string) => {
            if (trace) {
                if (stdout.trim()) outputChannel.debug(`stdout: ${stdout.trim()}`);
                if (stderr.trim()) outputChannel.debug(`stderr: ${stderr.trim()}`);
            }
            const diagnostics: vscode.Diagnostic[] = [];
            const output = (stdout + '\n' + stderr).trim();

            // Try JSON format first: {"type":"error","code":"E0001","message":"...","file":"...","line":N,"column":N}
            for (const line of output.split('\n')) {
                const trimmed = line.trim();
                if (!trimmed.startsWith('{')) continue;
                try {
                    const json = JSON.parse(trimmed);
                    if (json.line != null && json.message) {
                        const lineNum = Math.max(0, (json.line || 1) - 1);
                        const colNum = Math.max(0, (json.column || 1) - 1);
                        const range = new vscode.Range(lineNum, colNum, lineNum, colNum + 1);
                        const severity = json.type === 'warning'
                            ? vscode.DiagnosticSeverity.Warning
                            : vscode.DiagnosticSeverity.Error;
                        const diag = new vscode.Diagnostic(range, json.message, severity);
                        if (json.code) diag.code = json.code;
                        diag.source = 'cursed';
                        diagnostics.push(diag);
                    }
                } catch { /* not JSON, try next line */ }
            }

            // Fallback: parse "  --> file:line:col" format
            if (diagnostics.length === 0) {
                let pendingMessage = '';
                let pendingSeverity = vscode.DiagnosticSeverity.Error;
                for (const line of output.split('\n')) {
                    // Capture error/warning message line
                    const msgMatch = line.match(/^(error|warning)(?:\[[^\]]*\])?:\s*(.+)/);
                    if (msgMatch) {
                        pendingMessage = msgMatch[2].trim();
                        pendingSeverity = msgMatch[1] === 'warning'
                            ? vscode.DiagnosticSeverity.Warning
                            : vscode.DiagnosticSeverity.Error;
                        continue;
                    }
                    // Capture location line
                    const locMatch = line.match(/^\s*-->\s+.+?:(\d+):(\d+)/);
                    if (locMatch && pendingMessage) {
                        const lineNum = Math.max(0, parseInt(locMatch[1]) - 1);
                        const colNum = Math.max(0, parseInt(locMatch[2]) - 1);
                        const range = new vscode.Range(lineNum, colNum, lineNum, colNum + 1);
                        const diag = new vscode.Diagnostic(range, pendingMessage, pendingSeverity);
                        diag.source = 'cursed';
                        diagnostics.push(diag);
                        pendingMessage = '';
                    }
                }
            }

            diagnosticCollection.set(document.uri, diagnostics);
            if (trace) {
                outputChannel.info(`Diagnostics: ${diagnostics.length} issue(s) for ${filePath}`);
            }
        });
    }, delay);
}

// ── Document Symbols (Outline) ───────────────────────────────────────

class CursedDocumentSymbolProvider implements vscode.DocumentSymbolProvider {
    provideDocumentSymbols(document: vscode.TextDocument): vscode.DocumentSymbol[] {
        const symbols: vscode.DocumentSymbol[] = [];
        const text = document.getText();
        const lines = text.split('\n');

        for (let i = 0; i < lines.length; i++) {
            const line = lines[i];

            // slay name(...) or slay (receiver Type) name(...)
            const funcMatch = line.match(/^\s*slay\s+(?:\([^)]+\)\s+)?(\w+)\s*[(<]/);
            if (funcMatch) {
                const name = funcMatch[1];
                const range = this.getBlockRange(lines, i);
                const selRange = new vscode.Range(i, line.indexOf(name), i, line.indexOf(name) + name.length);
                const kind = name.startsWith('test_') ? vscode.SymbolKind.Method : vscode.SymbolKind.Function;
                symbols.push(new vscode.DocumentSymbol(name, 'slay', kind, range, selRange));
                continue;
            }

            // be_like Name squad { ... }
            const structMatch = line.match(/^\s*be_like\s+(\w+)\s+squad\b/);
            if (structMatch) {
                const name = structMatch[1];
                const range = this.getBlockRange(lines, i);
                const selRange = new vscode.Range(i, line.indexOf(name), i, line.indexOf(name) + name.length);
                symbols.push(new vscode.DocumentSymbol(name, 'squad', vscode.SymbolKind.Struct, range, selRange));
                continue;
            }

            // be_like Name collab { ... }
            const ifaceMatch = line.match(/^\s*be_like\s+(\w+)\s+collab\b/);
            if (ifaceMatch) {
                const name = ifaceMatch[1];
                const range = this.getBlockRange(lines, i);
                const selRange = new vscode.Range(i, line.indexOf(name), i, line.indexOf(name) + name.length);
                symbols.push(new vscode.DocumentSymbol(name, 'collab', vscode.SymbolKind.Interface, range, selRange));
                continue;
            }

            // impl Interface for Type { ... }
            const implMatch = line.match(/^\s*impl\s+(\w+)\s+for\s+(\w+)/);
            if (implMatch) {
                const name = `${implMatch[1]} for ${implMatch[2]}`;
                const range = this.getBlockRange(lines, i);
                const selRange = new vscode.Range(i, line.indexOf('impl'), i, line.indexOf('impl') + 4);
                symbols.push(new vscode.DocumentSymbol(name, 'impl', vscode.SymbolKind.Class, range, selRange));
                continue;
            }

            // be_like Name type (type alias, no struct/collab)
            const typeMatch = line.match(/^\s*be_like\s+(\w+)\s+(?!squad\b|collab\b)(\w+)/);
            if (typeMatch) {
                const name = typeMatch[1];
                const range = new vscode.Range(i, 0, i, line.length);
                const selRange = new vscode.Range(i, line.indexOf(name), i, line.indexOf(name) + name.length);
                symbols.push(new vscode.DocumentSymbol(name, 'be_like', vscode.SymbolKind.TypeParameter, range, selRange));
                continue;
            }

            // Top-level facts NAME = ...
            const constMatch = line.match(/^\s*facts\s+(\w+)/);
            if (constMatch) {
                const name = constMatch[1];
                const range = new vscode.Range(i, 0, i, line.length);
                const selRange = new vscode.Range(i, line.indexOf(name), i, line.indexOf(name) + name.length);
                symbols.push(new vscode.DocumentSymbol(name, 'facts', vscode.SymbolKind.Constant, range, selRange));
                continue;
            }
        }

        return symbols;
    }

    private getBlockRange(lines: string[], startLine: number): vscode.Range {
        let depth = 0;
        let foundOpen = false;
        for (let i = startLine; i < lines.length; i++) {
            for (const ch of lines[i]) {
                if (ch === '{') { depth++; foundOpen = true; }
                if (ch === '}') { depth--; }
            }
            if (foundOpen && depth <= 0) {
                return new vscode.Range(startLine, 0, i, lines[i].length);
            }
        }
        return new vscode.Range(startLine, 0, startLine, lines[startLine].length);
    }
}

// ── CodeLens ─────────────────────────────────────────────────────────

class CursedCodeLensProvider implements vscode.CodeLensProvider {
    provideCodeLenses(document: vscode.TextDocument): vscode.CodeLens[] {
        if (!vscode.workspace.getConfiguration('cursed').get('codeLens.enabled', true)) {
            return [];
        }
        const lenses: vscode.CodeLens[] = [];
        const text = document.getText();
        const lines = text.split('\n');

        for (let i = 0; i < lines.length; i++) {
            const line = lines[i];

            // main_character() or main()
            if (line.match(/^\s*slay\s+main(?:_character)?\s*\(/)) {
                const range = new vscode.Range(i, 0, i, line.length);
                lenses.push(new vscode.CodeLens(range, {
                    title: '$(play) Run',
                    command: 'cursed.run',
                }));
            }

            // test_* functions
            const testMatch = line.match(/^\s*slay\s+(test_\w+)\s*\(/);
            if (testMatch) {
                const range = new vscode.Range(i, 0, i, line.length);
                lenses.push(new vscode.CodeLens(range, {
                    title: '$(beaker) Run Test',
                    command: 'cursed.runTest',
                    arguments: [document.fileName, testMatch[1]],
                }));
            }
        }

        return lenses;
    }
}

// ── Keyword Completions ──────────────────────────────────────────────

class CursedCompletionProvider implements vscode.CompletionItemProvider {
    private keywords: { label: string; detail: string; kind: vscode.CompletionItemKind }[] = [
        // Declarations
        { label: 'sus', detail: 'Variable declaration', kind: vscode.CompletionItemKind.Keyword },
        { label: 'facts', detail: 'Constant declaration', kind: vscode.CompletionItemKind.Keyword },
        { label: 'slay', detail: 'Function definition', kind: vscode.CompletionItemKind.Keyword },
        { label: 'vibe', detail: 'Package declaration', kind: vscode.CompletionItemKind.Keyword },
        { label: 'yeet', detail: 'Import', kind: vscode.CompletionItemKind.Keyword },
        { label: 'be_like', detail: 'Type alias/definition', kind: vscode.CompletionItemKind.Keyword },
        { label: 'squad', detail: 'Struct definition', kind: vscode.CompletionItemKind.Keyword },
        { label: 'collab', detail: 'Interface definition', kind: vscode.CompletionItemKind.Keyword },
        { label: 'impl', detail: 'Implementation block', kind: vscode.CompletionItemKind.Keyword },
        // Control flow
        { label: 'lowkey', detail: 'If statement', kind: vscode.CompletionItemKind.Keyword },
        { label: 'highkey', detail: 'Else clause', kind: vscode.CompletionItemKind.Keyword },
        { label: 'bestie', detail: 'For loop', kind: vscode.CompletionItemKind.Keyword },
        { label: 'periodt', detail: 'While loop', kind: vscode.CompletionItemKind.Keyword },
        { label: 'flex', detail: 'Range (in for loops)', kind: vscode.CompletionItemKind.Keyword },
        { label: 'vibe_check', detail: 'Switch statement', kind: vscode.CompletionItemKind.Keyword },
        { label: 'mood', detail: 'Case clause', kind: vscode.CompletionItemKind.Keyword },
        { label: 'basic', detail: 'Default case', kind: vscode.CompletionItemKind.Keyword },
        { label: 'match', detail: 'Pattern matching', kind: vscode.CompletionItemKind.Keyword },
        { label: 'select', detail: 'Channel select', kind: vscode.CompletionItemKind.Keyword },
        { label: 'damn', detail: 'Return', kind: vscode.CompletionItemKind.Keyword },
        { label: 'yolo', detail: 'Return (alt)', kind: vscode.CompletionItemKind.Keyword },
        { label: 'ghosted', detail: 'Break', kind: vscode.CompletionItemKind.Keyword },
        { label: 'simp', detail: 'Continue', kind: vscode.CompletionItemKind.Keyword },
        { label: 'later', detail: 'Defer', kind: vscode.CompletionItemKind.Keyword },
        // Concurrency
        { label: 'stan', detail: 'Spawn goroutine', kind: vscode.CompletionItemKind.Keyword },
        // Error handling
        { label: 'yikes', detail: 'Error type / throw', kind: vscode.CompletionItemKind.Keyword },
        { label: 'fam', detail: 'Try block', kind: vscode.CompletionItemKind.Keyword },
        { label: 'shook', detail: 'Catch/handle error', kind: vscode.CompletionItemKind.Keyword },
        // Constants
        { label: 'based', detail: 'true', kind: vscode.CompletionItemKind.Constant },
        { label: 'cringe', detail: 'false', kind: vscode.CompletionItemKind.Constant },
        { label: 'nah', detail: 'null', kind: vscode.CompletionItemKind.Constant },
        // Types
        { label: 'normie', detail: 'i64', kind: vscode.CompletionItemKind.TypeParameter },
        { label: 'smol', detail: 'i8', kind: vscode.CompletionItemKind.TypeParameter },
        { label: 'mid', detail: 'i32', kind: vscode.CompletionItemKind.TypeParameter },
        { label: 'thicc', detail: 'i128', kind: vscode.CompletionItemKind.TypeParameter },
        { label: 'drip', detail: 'signed int', kind: vscode.CompletionItemKind.TypeParameter },
        { label: 'snack', detail: 'f32', kind: vscode.CompletionItemKind.TypeParameter },
        { label: 'meal', detail: 'f64', kind: vscode.CompletionItemKind.TypeParameter },
        { label: 'tea', detail: 'string', kind: vscode.CompletionItemKind.TypeParameter },
        { label: 'lit', detail: 'bool', kind: vscode.CompletionItemKind.TypeParameter },
        { label: 'sip', detail: 'char (u8)', kind: vscode.CompletionItemKind.TypeParameter },
        { label: 'byte', detail: 'u8', kind: vscode.CompletionItemKind.TypeParameter },
        { label: 'rune', detail: 'u32', kind: vscode.CompletionItemKind.TypeParameter },
        // Stdlib modules
        { label: 'vibez', detail: 'Core I/O module', kind: vscode.CompletionItemKind.Module },
        { label: 'mathz', detail: 'Math operations', kind: vscode.CompletionItemKind.Module },
        { label: 'stringz', detail: 'String manipulation', kind: vscode.CompletionItemKind.Module },
        { label: 'arrayz', detail: 'Array operations', kind: vscode.CompletionItemKind.Module },
        { label: 'testz', detail: 'Testing framework', kind: vscode.CompletionItemKind.Module },
        { label: 'cryptz', detail: 'Cryptographic functions', kind: vscode.CompletionItemKind.Module },
        { label: 'filez', detail: 'File I/O', kind: vscode.CompletionItemKind.Module },
        { label: 'httpz', detail: 'HTTP client/server', kind: vscode.CompletionItemKind.Module },
        { label: 'timez', detail: 'Time and date', kind: vscode.CompletionItemKind.Module },
        { label: 'jsonz', detail: 'JSON parsing', kind: vscode.CompletionItemKind.Module },
        { label: 'concurrenz', detail: 'Concurrency primitives', kind: vscode.CompletionItemKind.Module },
    ];

    provideCompletionItems(): vscode.CompletionItem[] {
        return this.keywords.map(kw => {
            const item = new vscode.CompletionItem(kw.label, kw.kind);
            item.detail = kw.detail;
            return item;
        });
    }
}

// ── Go-to-Definition ─────────────────────────────────────────────────

class CursedDefinitionProvider implements vscode.DefinitionProvider {
    async provideDefinition(
        document: vscode.TextDocument,
        position: vscode.Position,
    ): Promise<vscode.Location[]> {
        const wordRange = document.getWordRangeAtPosition(position);
        if (!wordRange) return [];
        const word = document.getText(wordRange);

        const locations: vscode.Location[] = [];

        // Search for definitions in all .💀 and .cursed files
        const files = await vscode.workspace.findFiles('**/*.{💀,cursed}', '**/node_modules/**', 200);

        const patterns = [
            new RegExp(`^\\s*slay\\s+(?:\\([^)]+\\)\\s+)?${this.escapeRegex(word)}\\s*[(<]`), // function
            new RegExp(`^\\s*be_like\\s+${this.escapeRegex(word)}\\s+`),                       // type/struct/interface
            new RegExp(`^\\s*impl\\s+${this.escapeRegex(word)}\\s+`),                           // impl
        ];

        for (const fileUri of files) {
            const doc = await vscode.workspace.openTextDocument(fileUri);
            const text = doc.getText().split('\n');
            for (let i = 0; i < text.length; i++) {
                for (const pattern of patterns) {
                    if (pattern.test(text[i])) {
                        const col = text[i].indexOf(word);
                        if (col >= 0) {
                            locations.push(new vscode.Location(
                                fileUri,
                                new vscode.Position(i, col),
                            ));
                        }
                    }
                }
            }
        }

        return locations;
    }

    private escapeRegex(s: string): string {
        return s.replace(/[.*+?^${}()|[\]\\]/g, '\\$&');
    }
}

// ── Signature Help ───────────────────────────────────────────────────

class CursedSignatureHelpProvider implements vscode.SignatureHelpProvider {
    provideSignatureHelp(
        document: vscode.TextDocument,
        position: vscode.Position,
    ): vscode.SignatureHelp | null {
        // Walk backwards from cursor to find the function name and opening paren
        const lineText = document.lineAt(position.line).text.substring(0, position.character);
        const callMatch = lineText.match(/(\w+)\s*\(([^)]*)$/);
        if (!callMatch) return null;

        const funcName = callMatch[1];
        const argsText = callMatch[2];
        const activeParam = argsText.split(',').length - 1;

        // Search current document for the function definition
        const text = document.getText();
        const defPattern = new RegExp(`slay\\s+(?:\\([^)]+\\)\\s+)?${funcName}\\s*\\(([^)]*)\\)`, 'm');
        const defMatch = text.match(defPattern);
        if (!defMatch) return null;

        const params = defMatch[1].split(',').map(p => p.trim()).filter(p => p);
        const sig = new vscode.SignatureInformation(
            `slay ${funcName}(${defMatch[1].trim()})`,
            `Function ${funcName}`,
        );
        sig.parameters = params.map(p => new vscode.ParameterInformation(p));

        const help = new vscode.SignatureHelp();
        help.signatures = [sig];
        help.activeSignature = 0;
        help.activeParameter = Math.min(activeParam, params.length - 1);
        return help;
    }
}

// ── Task Provider (Problem Matcher) ──────────────────────────────────

class CursedTaskProvider implements vscode.TaskProvider {
    provideTasks(): vscode.Task[] {
        const tasks: vscode.Task[] = [];
        const config = vscode.workspace.getConfiguration('cursed');
        const compilerPath = config.get('compiler.path', 'cursed-compiler');

        // Check task
        const checkDef: vscode.TaskDefinition = { type: 'cursed', task: 'check' };
        const checkExec = new vscode.ShellExecution(`${compilerPath} check --color never "\${file}"`);
        const checkTask = new vscode.Task(checkDef, vscode.TaskScope.Workspace, 'Check', 'cursed', checkExec, '$cursed');
        checkTask.group = vscode.TaskGroup.Build;
        tasks.push(checkTask);

        // Build task
        const buildDef: vscode.TaskDefinition = { type: 'cursed', task: 'build' };
        const buildExec = new vscode.ShellExecution(`${compilerPath} --compile --color never "\${file}"`);
        const buildTask = new vscode.Task(buildDef, vscode.TaskScope.Workspace, 'Build', 'cursed', buildExec, '$cursed');
        buildTask.group = vscode.TaskGroup.Build;
        tasks.push(buildTask);

        // Run task
        const runDef: vscode.TaskDefinition = { type: 'cursed', task: 'run' };
        const runExec = new vscode.ShellExecution(`${compilerPath} "\${file}"`);
        const runTask = new vscode.Task(runDef, vscode.TaskScope.Workspace, 'Run', 'cursed', runExec);
        runTask.group = vscode.TaskGroup.Test;
        tasks.push(runTask);

        return tasks;
    }

    resolveTask(task: vscode.Task): vscode.Task {
        return task;
    }
}

// ── Activate ─────────────────────────────────────────────────────────

export async function activate(context: vscode.ExtensionContext) {
    // ── Output Channel ──────────────────────────────────────────
    outputChannel = vscode.window.createOutputChannel('CURSED', { log: true });
    context.subscriptions.push(outputChannel);

    // Register cSpell dictionary for CURSED keywords
    const cspellExt = vscode.extensions.getExtension<CodeSpellCheckerExtension>(
        'streetsidesoftware.code-spell-checker'
    );
    if (cspellExt) {
        const ext = await cspellExt.activate();
        ext?.registerConfig?.(context.asAbsolutePath('./cspell-ext.json'));
    }

    // ── Diagnostics ──────────────────────────────────────────────
    diagnosticCollection = vscode.languages.createDiagnosticCollection('cursed');
    context.subscriptions.push(diagnosticCollection);

    const diagnosticsEnabled = () =>
        vscode.workspace.getConfiguration('cursed').get('diagnostics.enabled', true);

    if (diagnosticsEnabled()) {
        // Run on active editor
        if (vscode.window.activeTextEditor) {
            runDiagnostics(vscode.window.activeTextEditor.document);
        }
        // Run on save
        context.subscriptions.push(
            vscode.workspace.onDidSaveTextDocument(doc => {
                if (diagnosticsEnabled()) runDiagnostics(doc);
            })
        );
        // Clear when file is closed
        context.subscriptions.push(
            vscode.workspace.onDidCloseTextDocument(doc => {
                diagnosticCollection.delete(doc.uri);
            })
        );
    }

    // ── Commands ─────────────────────────────────────────────────

    // Show Output
    context.subscriptions.push(
        vscode.commands.registerCommand('cursed.showOutput', () => {
            outputChannel.show();
        })
    );

    // Run CURSED Program
    context.subscriptions.push(
        vscode.commands.registerCommand('cursed.run', async () => {
            const editor = vscode.window.activeTextEditor;
            if (!editor || editor.document.languageId !== 'cursed') {
                vscode.window.showErrorMessage('No CURSED file is currently open');
                return;
            }
            const config = vscode.workspace.getConfiguration('cursed');
            const compilerPath = config.get('compiler.path', 'cursed-compiler');
            const clearTerminal = config.get('run.clearTerminal', false);
            const filePath = editor.document.fileName;
            const terminal = vscode.window.createTerminal('CURSED');
            if (clearTerminal) terminal.sendText('clear');
            terminal.sendText(`${compilerPath} "${filePath}"`);
            terminal.show();
        })
    );

    // Build CURSED Program
    context.subscriptions.push(
        vscode.commands.registerCommand('cursed.build', async () => {
            const editor = vscode.window.activeTextEditor;
            if (!editor || editor.document.languageId !== 'cursed') {
                vscode.window.showErrorMessage('No CURSED file is currently open');
                return;
            }
            const config = vscode.workspace.getConfiguration('cursed');
            const compilerPath = config.get('compiler.path', 'cursed-compiler');
            const filePath = editor.document.fileName;
            const terminal = vscode.window.createTerminal('CURSED Build');
            terminal.sendText(`${compilerPath} --compile "${filePath}"`);
            terminal.show();
        })
    );

    // Run specific test
    context.subscriptions.push(
        vscode.commands.registerCommand('cursed.runTest', async (filePath: string, testName: string) => {
            const config = vscode.workspace.getConfiguration('cursed');
            const compilerPath = config.get('compiler.path', 'cursed-compiler');
            const terminal = vscode.window.createTerminal('CURSED Test');
            terminal.sendText(`${compilerPath} "${filePath}" --test ${testName}`);
            terminal.show();
        })
    );

    // ── Status Bar ───────────────────────────────────────────────

    const statusBarItem = vscode.window.createStatusBarItem(vscode.StatusBarAlignment.Left, 100);
    statusBarItem.text = '$(play) CURSED';
    statusBarItem.command = 'cursed.run';
    statusBarItem.tooltip = 'Run CURSED Program (Ctrl+F5)';

    const updateStatusBar = () => {
        const editor = vscode.window.activeTextEditor;
        if (editor && editor.document.languageId === 'cursed') {
            statusBarItem.show();
        } else {
            statusBarItem.hide();
        }
    };

    updateStatusBar();
    context.subscriptions.push(
        vscode.window.onDidChangeActiveTextEditor(updateStatusBar),
        statusBarItem
    );

    // ── Hover Documentation ──────────────────────────────────────

    context.subscriptions.push(
        vscode.languages.registerHoverProvider('cursed', {
            provideHover(document, position) {
                const range = document.getWordRangeAtPosition(position);
                if (!range) return null;
                const word = document.getText(range);

                const docs: Record<string, string> = {
                    // Declaration keywords
                    'sus': '**sus** — Variable declaration\n\n```cursed\nsus name = "value"\nsus count normie = 42\n```',
                    'facts': '**facts** — Constant declaration\n\n```cursed\nfacts PI = 3.14159\nfacts MAX_SIZE = 100\n```',
                    'slay': '**slay** — Function definition\n\n```cursed\nslay greet(name tea) tea {\n    damn "Hello, " + name\n}\n```',
                    'squad': '**squad** — Struct definition\n\n```cursed\nbe_like Person squad {\n    sus name tea\n    sus age normie\n}\n```',
                    'collab': '**collab** — Interface definition\n\n```cursed\nbe_like Greeter collab {\n    greet() tea\n}\n```',
                    'yeet': '**yeet** — Import module\n\n```cursed\nyeet "vibez"\nyeet "stdlib::math"\n```',
                    'vibe': '**vibe** — Package declaration\n\n```cursed\nvibe main\n```',
                    'be_like': '**be_like** — Type alias/definition\n\n```cursed\nbe_like Age normie\n```',

                    // Control flow
                    'lowkey': '**lowkey** — If statement\n\n```cursed\nlowkey condition {\n    fr fr do something\n}\n```',
                    'highkey': '**highkey** — Else clause\n\n```cursed\nlowkey condition {\n    fr fr if branch\n} highkey {\n    fr fr else branch\n}\n```',
                    'bestie': '**bestie** — For loop\n\n```cursed\nbestie i := 0; i < 10; i++ {\n    println(i)\n}\n```',
                    'periodt': '**periodt** — While loop\n\n```cursed\nperiodt condition {\n    fr fr loop body\n}\n```',
                    'vibe_check': '**vibe_check** — Switch statement\n\n```cursed\nvibe_check value {\n    mood 1: println("one")\n    mood 2: println("two")\n    basic: println("other")\n}\n```',
                    'mood': '**mood** — Case in vibe_check (switch)',
                    'basic': '**basic** — Default case in vibe_check (switch)',
                    'flex': '**flex** — Range iteration\n\n```cursed\nbestie idx, val := flex collection {\n    println(val)\n}\n```',
                    'select': '**select** — Select statement (channel multiplexing)\n\n```cursed\nvibe_check {\n    mood msg := <-ch:\n        println(msg)\n}\n```',
                    'match': '**match** — Pattern matching\n\n```cursed\nmatch value {\n    when 1 -> println("one")\n    when _ -> println("other")\n}\n```',

                    // Flow control
                    'damn': '**damn** — Return value from function\n\n```cursed\nslay add(a, b) {\n    damn a + b\n}\n```',
                    'yolo': '**yolo** — Return (alt syntax)',
                    'ghosted': '**ghosted** — Break out of loop',
                    'simp': '**simp** — Continue to next iteration',
                    'later': '**later** — Defer (run on scope exit)\n\n```cursed\nlater cleanup()\n```',

                    // Concurrency
                    'stan': '**stan** — Spawn goroutine\n\n```cursed\nstan { doWork() }\n```',

                    'impl': '**impl** — Implementation block\n\n```cursed\nimpl Greeter for Person {\n    slay greet() tea {\n        damn "Hello"\n    }\n}\n```',

                    // Error handling
                    'yikes': '**yikes** — Error type / throw error\n\n```cursed\nslay divide(a, b normie) yikes<normie> {\n    lowkey b == 0 {\n        yikes "division by zero"\n    }\n    damn a / b\n}\n```',
                    'fam': '**fam** — Error handling block (try-catch)',
                    'shook': '**shook** — Catch/handle error',

                    // Constants
                    'based': '**based** — Boolean `true`',
                    'cringe': '**cringe** — Boolean `false`',
                    'nah': '**nah** — Null value',

                    // Types
                    'normie': '**normie** — Integer type (i64)',
                    'smol': '**smol** — Small integer (i8)',
                    'mid': '**mid** — Medium integer (i32)',
                    'thicc': '**thicc** — Large integer (i128)',
                    'drip': '**drip** — Signed integer / numeric type',
                    'snack': '**snack** — Float (f32)',
                    'meal': '**meal** — Float (f64)',
                    'tea': '**tea** — String type',
                    'lit': '**lit** — Boolean type',
                    'sip': '**sip** — Character type (u8)',
                    'byte': '**byte** — Byte type (u8)',
                    'rune': '**rune** — Unicode codepoint (u32)',
                    'extra': '**extra** — Extended numeric type',

                    // Stdlib modules
                    'vibez': '**vibez** — Core I/O module\n\n```cursed\nvibez.spill("Hello!")\n```',
                    'mathz': '**mathz** — Math operations module',
                    'stringz': '**stringz** — String manipulation module',
                    'arrayz': '**arrayz** — Array operations module',
                    'testz': '**testz** — Testing framework module',
                    'cryptz': '**cryptz** — Cryptographic functions module',
                    'filez': '**filez** — File I/O module',
                    'httpz': '**httpz** — HTTP client/server module',
                    'timez': '**timez** — Time and date module',
                    'jsonz': '**jsonz** — JSON parsing module',
                    'concurrenz': '**concurrenz** — Concurrency primitives module',
                };

                const doc = docs[word];
                if (doc) {
                    return new vscode.Hover(new vscode.MarkdownString(doc));
                }
                return null;
            }
        })
    );

    // ── Document Symbols (Outline) ───────────────────────────────

    context.subscriptions.push(
        vscode.languages.registerDocumentSymbolProvider('cursed', new CursedDocumentSymbolProvider())
    );

    // ── CodeLens ─────────────────────────────────────────────────

    context.subscriptions.push(
        vscode.languages.registerCodeLensProvider('cursed', new CursedCodeLensProvider())
    );

    // ── Keyword Completions ──────────────────────────────────────

    context.subscriptions.push(
        vscode.languages.registerCompletionItemProvider('cursed', new CursedCompletionProvider())
    );

    // ── Go-to-Definition ─────────────────────────────────────────

    context.subscriptions.push(
        vscode.languages.registerDefinitionProvider('cursed', new CursedDefinitionProvider())
    );

    // ── Signature Help ───────────────────────────────────────────

    context.subscriptions.push(
        vscode.languages.registerSignatureHelpProvider('cursed',
            new CursedSignatureHelpProvider(),
            '(', ','
        )
    );

    // ── Task Provider ────────────────────────────────────────────

    context.subscriptions.push(
        vscode.tasks.registerTaskProvider('cursed', new CursedTaskProvider())
    );
}

export function deactivate() {
    if (diagnosticDebounce) clearTimeout(diagnosticDebounce);
}
