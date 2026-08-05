//! Reads a LaTeX formula on stdin, writes 2D unicode art on stdout.
//!
//! This is render-markdown.nvim's `latex` converter. It replaces a pylatexenc +
//! unicodeit Python script: the conversion itself only took ~1ms, but each call
//! paid ~50ms of interpreter startup, and render-markdown blocks the UI thread
//! while every equation in the buffer converts. A native binary starts in ~1ms,
//! which takes an 80-equation buffer from ~550ms to ~40ms.
//!
//! `term-maths` does the 2D layout (fractions, matrices, tall brackets, stacked
//! limits). `unicodeit` covers plain symbol substitution for anything the layout
//! cannot parse. Exiting non-zero hands the formula to the next converter in
//! render-markdown's chain, which is `latex2text`.

use std::io::{self, Read, Write};
use std::panic;

/// Layout via term-maths, falling back to flat symbol substitution when it
/// yields nothing. Panics are treated as a parse failure so a malformed formula
/// degrades instead of killing the process.
fn convert(src: &str) -> Option<String> {
    let laid_out = panic::catch_unwind(|| term_maths::render(src).to_string()).ok();

    if let Some(text) = laid_out {
        if !text.trim().is_empty() {
            return Some(text);
        }
    }

    let flat = unicodeit::replace(src);
    if flat.trim().is_empty() {
        None
    } else {
        Some(flat)
    }
}

/// Drop trailing spaces the grid layout pads with. render-markdown measures the
/// widest line to align the block, so trailing blanks would offset it.
fn trim_grid(text: &str) -> String {
    let lines: Vec<&str> = text.lines().map(str::trim_end).collect();
    let last = lines.iter().rposition(|line| !line.is_empty());
    match last {
        Some(end) => lines[..=end].join("\n"),
        None => String::new(),
    }
}

fn main() {
    let mut src = String::new();
    if io::stdin().read_to_string(&mut src).is_err() {
        std::process::exit(1);
    }
    let src = src.trim();
    if src.is_empty() {
        return;
    }

    // term-maths reports parse failures by panicking; keep the backtrace out of
    // Neovim's messages since a non-zero exit is the real signal.
    panic::set_hook(Box::new(|_| {}));

    let Some(output) = convert(src) else {
        std::process::exit(1);
    };

    let output = trim_grid(&output);
    if output.is_empty() {
        std::process::exit(1);
    }

    if io::stdout().write_all(output.as_bytes()).is_err() {
        std::process::exit(1);
    }
}
