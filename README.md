# CURSED 💀

> An esoteric programming language that combines Go-like semantics with Gen Z slang keywords, featuring the world's first use of Among Us `ඞ` characters in pointer syntax.

CURSED is a statically typed programming language with a tree-walking interpreter written in Zig. It replaces traditional keywords with Gen Z slang while keeping Go-inspired semantics.

## Features

- **Gen Z Slang Keywords**: `slay` for functions, `sus` for variables, `vibe` for packages, `lowkey`/`highkey` for if/else
- **Among Us Pointer Syntax**: Uses `ඞ` (U+0D9E) for pointer operations
- **Go-like Semantics**: Familiar control flow, structs, interfaces, and imports
- **Error Handling**: `yikes`/`fam`/`shook` try-catch system with error propagation
- **Tree-sitter Grammar**: Editor syntax highlighting support
- **VS Code Extension**: Syntax highlighting, snippets, diagnostics, and go-to-definition

## Quick Start

### Hello World

```cursed
vibe main
yeet "vibez"

slay main() {
    vibez.spill("Hello, World!")
}
```

### Variables and Types

```cursed
slay demo() {
    sus age normie = 25          // 32-bit integer
    sus name tea = "Alice"       // string
    sus is_cool lit = based      // boolean (true)
    sus height snack = 5.8       // 32-bit float

    vibez.spill("Name:", name)
}
```

### Functions and Control Flow

```cursed
slay calculate(x normie, y normie) normie {
    lowkey x > y {
        damn x + y
    } highkey {
        damn x - y
    }
}

slay loop_example() {
    bestie i := 0; i < 10; i++ {
        lowkey i % 2 == 0 {
            vibez.spill("Even:", i)
        }
    }
}
```

### Error Handling

```cursed
slay divide(a normie, b normie) normie yikes {
    lowkey b == 0 {
        yikes "Division by zero"
    }
    damn a / b
}

slay safe_division() {
    fam {
        result := divide(10, 0) shook
        vibez.spill("Result:", result)
    } sus error {
        vibez.spill("Error:", error.message())
    }
}
```

## Language Overview

### Keywords

| Traditional | CURSED | Usage |
| ----------- | ------ | ----- |
| package | `vibe` | Package declaration |
| import | `yeet` | Import packages |
| func | `slay` | Function definition |
| var | `sus` | Mutable variable |
| const | `facts` | Constant declaration |
| if | `lowkey` | Conditional |
| else | `highkey` | Alternative branch |
| for | `bestie` | Loop |
| while | `periodt` | While loop |
| range | `flex` | Range iteration |
| in | `in` | For-in loops |
| switch | `vibe_check` | Switch statement |
| case | `mood` | Case clause |
| default | `basic` | Default case |
| match | `match` | Match expression |
| return | `damn` | Return statement |
| break | `ghosted` | Break from loop |
| continue | `simp` | Continue loop |
| defer | `later` | Deferred execution |
| go | `stan` | Spawn goroutine |
| select | `select` | Select statement |
| struct | `squad` | Struct definition |
| interface | `collab` | Interface definition |
| impl | `impl` | Implementation block |
| extends | `extends` | Interface inheritance |
| throw | `yeet_error` | Throw error |
| catch | `catch` | Catch error |
| try | `fam` | Error recovery block |
| panic | `shook` | Error propagation |
| where | `where` | Generic constraints |
| pub | `crew` | Package visibility |
| priv | `priv` | Private visibility |
| assign | `be_like` | Assignment operator |
| true | `based` | Boolean true |
| false | `cringe` | Boolean false |
| nil | `nah` | Null value |

### Types

| Type | Description |
| ------ | ------------- |
| `lit` | Boolean |
| `normie` | 32-bit signed integer |
| `smol` | 8-bit signed integer |
| `mid` | 16-bit signed integer |
| `thicc` | 64-bit signed integer |
| `byte` | Unsigned 8-bit integer |
| `rune` | 32-bit integer alias (character code point) |
| `snack` | 32-bit float |
| `meal` | 64-bit float |
| `drip` | Float (legacy alias) |
| `tea` | String |
| `txt` | String alias |
| `sip` | Character |
| `extra` | Complex number |
| `ඞT` | Pointer to type T |
| `dm<T>` | Channel of type T |

## Installation

### Prerequisites

- Zig 0.13+
- Git

### Building from Source

```bash
git clone https://github.com/ghuntley/cursed
cd cursed
zig build
```

### Running Programs

```bash
# Run a CURSED program (interpreter)
./zig-out/bin/cursed-compiler program.💀

# Generate LLVM IR (experimental)
./zig-out/bin/cursed-compiler --emit-ir program.💀

# Debug mode with verbose output
./zig-out/bin/cursed-compiler --debug --verbose program.💀
```

## Project Structure

```text
├── src-zig/            # Zig compiler and interpreter source
├── stdlib/             # Standard library modules
├── examples/           # Example programs
├── test_suite/         # Tests including LeetCode suite
├── tools/              # VS Code extension
├── tree-sitter/        # Tree-sitter grammar
├── build/wasm/         # WASM build target
└── build.zig           # Zig build configuration
```

## Status

The compiler is implemented in Zig and currently operates as a **tree-walking interpreter**. It handles variables, functions, control flow, structs, interfaces, imports, error handling, and stdlib modules.

**Working:**

- Lexer and parser for the full keyword set
- Tree-walking interpreter with stdlib module imports
- Variables, arithmetic, strings, booleans, arrays
- Functions, closures, structs, interfaces, methods
- Control flow (`lowkey`/`highkey`, `bestie`, `periodt`, `vibe_check`)
- Error handling (`fam`/`yikes`/`shook`)
- `later` (defer) statements
- LLVM IR generation for simple programs (`--emit-ir`)

**In progress:**

- Native compilation (`--compile` — runtime library not yet wired up)
- Concurrency (`stan`/`dm` — parsed and partially implemented)
- Garbage collector (implemented but not yet integrated with interpreter)
- Self-hosting compiler in CURSED

## Contributing

Contributions welcome! See the open issues for good starting points.

### Development Guidelines

1. Add tests for new features
2. Update documentation
3. Use conventional commit messages

## Examples

### LeetCode Test Suite

The [`test_suite/leetcode_comprehensive_suite/`](test_suite/leetcode_comprehensive_suite/) contains LeetCode problems across 10 categories implemented in CURSED:

- Arrays and hashing, binary search, dynamic programming
- Linked lists and trees with `ඞ` pointers
- String manipulation, sorting, backtracking

```cursed
// LeetCode #206: Reverse Linked List with Among Us pointers
slay reverse_list(head ඞListNode) ඞListNode {
    sus prev ඞListNode = nah
    sus current ඞListNode = head

    periodt current != nah {
        sus next_temp ඞListNode = current.next
        current.next = prev
        prev = current
        current = next_temp
    }

    damn prev
}
```

### More Examples

The [`examples/`](examples/) directory has programs covering syntax basics, error handling, HTTP servers, crypto, database integration, templates, and more.

## License

MIT License — see [LICENSE](LICENSE) for details.

## Acknowledgments

- Inspired by Go's simplicity and concurrency model
- Gen Z linguistic creativity and internet culture
- The Among Us community for the iconic `ඞ` character

---

*"Stay based, avoid cringe, and always handle your yikes responsibly."* 💀✨
