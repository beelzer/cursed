import * as vscode from 'vscode';

export function activate(context: vscode.ExtensionContext) {
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
            const filePath = editor.document.fileName;

            const terminal = vscode.window.createTerminal('CURSED');
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

    // Status bar run button
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

    // Keyword hover documentation
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
                    'squad': '**squad** — Struct definition\n\n```cursed\nsquad Person {\n    sus name\n    sus age\n}\n```',
                    'collab': '**collab** — Interface definition\n\n```cursed\nbe_like Greeter collab {\n    greet() tea\n}\n```',
                    'yeet': '**yeet** — Import module\n\n```cursed\nyeet "vibez"\nyeet "stdlib::math"\n```',
                    'vibe': '**vibe** — Package declaration\n\n```cursed\nvibe main\n```',
                    'be_like': '**be_like** — Type alias/definition\n\n```cursed\nbe_like Age normie\n```',

                    // Control flow
                    'lowkey': '**lowkey** — If statement\n\n```cursed\nlowkey condition {\n    fr fr do something\n}\n```',
                    'highkey': '**highkey** — Else clause\n\n```cursed\nlowkey condition {\n    fr fr if branch\n} highkey {\n    fr fr else branch\n}\n```',
                    'ready': '**ready** — If statement (alt syntax)\n\n```cursed\nready (condition) {\n    fr fr do something\n}\n```',
                    'otherwise': '**otherwise** — Else clause (alt syntax)\n\n```cursed\nready (x > 0) {\n    fr fr positive\n} otherwise {\n    fr fr non-positive\n}\n```',
                    'bestie': '**bestie** — For loop\n\n```cursed\nbestie i := 0; i < 10; i++ {\n    println(i)\n}\n```',
                    'periodt': '**periodt** — While loop\n\n```cursed\nperiodt condition {\n    fr fr loop body\n}\n```',
                    'vibe_check': '**vibe_check** — Switch statement\n\n```cursed\nvibe_check value {\n    mood 1: println("one")\n    mood 2: println("two")\n    basic: println("other")\n}\n```',
                    'mood': '**mood** — Case in vibe_check (switch)',
                    'basic': '**basic** — Default case in vibe_check (switch)',

                    // Flow control
                    'damn': '**damn** — Return value from function\n\n```cursed\nslay add(a, b) {\n    damn a + b\n}\n```',
                    'yolo': '**yolo** — Return (alt syntax)',
                    'ghosted': '**ghosted** — Break out of loop',
                    'simp': '**simp** — Continue to next iteration',
                    'later': '**later** — Defer (run on scope exit)\n\n```cursed\nlater cleanup()\n```',

                    // Concurrency
                    'stan': '**stan** — Spawn goroutine\n\n```cursed\nstan { doWork() }\n```',

                    // Error handling
                    'yikes': '**yikes** — Error type / throw error',
                    'fam': '**fam** — Error handling block (try-catch)',
                    'shook': '**shook** — Catch/handle error',

                    // Constants
                    'based': '**based** — Boolean `true`',
                    'cringe': '**cringe** — Boolean `false`',
                    'cap': '**cap** — Boolean `false` (alt)',
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

    // Stdlib module completion
    context.subscriptions.push(
        vscode.languages.registerCompletionItemProvider('cursed', {
            provideCompletionItems() {
                const modules = [
                    { name: 'vibez', detail: 'Core I/O operations' },
                    { name: 'mathz', detail: 'Mathematical operations' },
                    { name: 'stringz', detail: 'String manipulation' },
                    { name: 'arrayz', detail: 'Array operations' },
                    { name: 'testz', detail: 'Testing framework' },
                    { name: 'cryptz', detail: 'Cryptographic functions' },
                    { name: 'filez', detail: 'File I/O operations' },
                    { name: 'httpz', detail: 'HTTP client/server' },
                    { name: 'timez', detail: 'Time and date operations' },
                    { name: 'jsonz', detail: 'JSON parsing' },
                    { name: 'concurrenz', detail: 'Concurrency primitives' },
                ];

                return modules.map(m => {
                    const item = new vscode.CompletionItem(m.name, vscode.CompletionItemKind.Module);
                    item.detail = m.detail;
                    item.documentation = new vscode.MarkdownString(`Import: \`yeet "${m.name}"\``);
                    return item;
                });
            }
        })
    );
}

export function deactivate() {}
