# CURSED Language Support

Language support for the [CURSED programming language](https://github.com/ghuntley/cursed) — programming, but make it gen z.

## Features

- **Syntax Highlighting** — Full TextMate grammar for `.💀` and `.cursed` files
- **Snippets** — 50+ snippets for all language constructs
- **Hover Documentation** — Hover over any keyword for inline docs
- **Run & Build** — Run/build programs with `Ctrl+F5` or the status bar button
- **Spell Check Dictionary** — Built-in cSpell dictionary for CURSED keywords

## Quick Reference

| CURSED | Meaning |
| ------ | ------- |
| `sus` | Variable declaration |
| `facts` | Constant declaration |
| `slay` | Function definition |
| `damn` / `yolo` | Return |
| `lowkey` / `highkey` | If / Else |
| `periodt` | While loop |
| `bestie` | For loop |
| `flex` | Range (in for loops) |
| `vibe_check` / `mood` / `basic` | Switch / Case / Default |
| `match` / `when` | Pattern matching |
| `ghosted` / `simp` | Break / Continue |
| `later` | Defer |
| `yeet` | Import |
| `vibe` | Package declaration |
| `squad` | Struct |
| `collab` | Interface |
| `impl` | Implementation block |
| `be_like` | Type alias |
| `stan` | Goroutine |
| `dm` | Channel type |
| `fam` / `shook` | Try / Catch |
| `yikes` | Error type / throw |
| `based` / `cringe` | True / False |
| `nah` | Null |
| `ඞ` | Pointer |
| `fr fr` | Line comment |
| `no cap` ... `on god` | Block comment |

## Types

| CURSED | Type |
| ------ | ---- |
| `normie` | i64 |
| `smol` | i8 |
| `mid` | i32 |
| `thicc` | i128 |
| `drip` | signed int |
| `snack` | f32 |
| `meal` | f64 |
| `tea` | string |
| `lit` | bool |
| `sip` | char |
| `byte` | u8 |
| `rune` | u32 |

## Stdlib Modules

`vibez` · `mathz` · `stringz` · `arrayz` · `testz` · `cryptz` · `filez` · `httpz` · `timez` · `jsonz` · `concurrenz`

## Example

```cursed
vibe main

yeet "vibez"

fr fr Hello World in CURSED
slay main_character() {
    vibez.spill("Hello, World!")
}
```

## Building

```bash
bash build.sh
```

This compiles the extension, packages it as a `.vsix`, and installs it into VS Code. The version is auto-bumped only when source files have changed.
