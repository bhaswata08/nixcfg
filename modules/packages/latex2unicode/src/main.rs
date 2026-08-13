//! Reads a LaTeX formula on stdin, writes 2D unicode art on stdout.
//!
//! This is render-markdown.nvim's `latex` converter. It replaces a pylatexenc +
//! unicodeit Python script: the conversion itself only took ~1ms, but each call
//! paid ~50ms of interpreter startup, and render-markdown blocks the UI thread
//! while every on-screen equation converts. A native binary starts in ~1ms.
//!
//! `term-maths` does the 2D layout (fractions, matrices, tall brackets, stacked
//! limits). `unicodeit` covers plain symbol substitution for anything the layout
//! cannot parse. Exiting non-zero hands the formula to the next converter in
//! render-markdown's chain, which is `latex2text`.

use std::io::{self, Read, Write};
use std::panic;

/// Above this many bytes, skip the 2D layout entirely. term-maths cost grows
/// superlinearly (measured: 1KB 20ms, 2KB 60ms, 4KB 210ms, 8KB 750ms) and
/// render-markdown converts on the UI thread, so a formula-shaped blob pasted
/// into `$$ ... $$` would freeze Neovim. Symbol substitution is flat-cost and
/// stays readable. Real equations are far below this.
const LAYOUT_LIMIT: usize = 1024;

/// term-maths reads `_` and `^` as layout operators and stacks a script it
/// cannot map onto its own line. Swapping the operator for a private-use
/// character hides it from the layout pass; it survives rendering untouched and
/// is swapped back afterwards.
const SUB_MARK: char = '\u{E000}';
const SUP_MARK: char = '\u{E001}';
/// Same trick for `:=`, which the layout otherwise splits into `: =`.
const WALRUS_MARK: char = '\u{E002}';

/// Characters that have a Unicode subscript or superscript form. Anything
/// outside these cannot be written inline, which is what the old Python
/// converter used to decide between an inline and a stacked script. Only
/// membership matters here; term-maths performs the substitution itself.
const SUP_FROM: &str = "0123456789+-=()abcdefghijklmnoprstuvwxyz\u{2212}\u{00D7}";
const SUB_FROM: &str = "0123456789+-=()aehijklmnoprstuvx\u{2212}";

/// Operators whose scripts are limits and belong above and below the symbol.
/// Stacking those is correct display style, so their scripts are never hidden
/// from the layout pass.
const LARGE_OPS: &[&str] = &[
    "\\int",
    "\\iint",
    "\\iiint",
    "\\oint",
    "\\sum",
    "\\prod",
    "\\coprod",
    "\\lim",
    "\\limsup",
    "\\liminf",
    "\\bigcup",
    "\\bigcap",
    "\\bigoplus",
    "\\bigotimes",
    "\\bigodot",
    "\\bigsqcup",
    "\\bigvee",
    "\\bigwedge",
    "\\max",
    "\\min",
    "\\sup",
    "\\inf",
    "\\argmax",
    "\\argmin",
];

/// `\limits` asks the operator before it to stack its scripts, so the tracked
/// base must survive it.
const KEEPS_LIMITS: &str = "\\limits";
/// `\nolimits` asks for the opposite, so it drops the base and lets an
/// unmappable script be hidden from the layout pass like any ordinary script.
const DROPS_LIMITS: &str = "\\nolimits";

/// Whether a rendered script has to be stacked because it cannot be written
/// inline. That is the case when no character of the body has a Unicode sub or
/// superscript form. A body that mixes mappable and unmappable characters is
/// left alone: term-maths renders those inline already (`e^{-x^2}` -> `e⁻ˣ²`),
/// and second-guessing it there costs more than it fixes.
fn must_stack(rendered: &str, up: bool) -> bool {
    let from = if up { SUP_FROM } else { SUB_FROM };
    !rendered.is_empty() && !rendered.chars().any(|c| from.contains(c))
}

/// Read the script body starting at `chars[i]`: a brace group, a `\command`, or
/// a single character. Returns the body without braces and the next index.
fn read_body(chars: &[char], i: usize) -> Option<(String, usize)> {
    match chars.get(i)? {
        '{' => {
            let mut depth = 0usize;
            let mut body = String::new();
            for (offset, &c) in chars[i..].iter().enumerate() {
                match c {
                    '{' => {
                        depth += 1;
                        if depth > 1 {
                            body.push(c);
                        }
                    }
                    '}' => {
                        depth -= 1;
                        if depth == 0 {
                            return Some((body, i + offset + 1));
                        }
                        body.push(c);
                    }
                    _ => body.push(c),
                }
            }
            None
        }
        '\\' => {
            let mut end = i + 1;
            while chars.get(end).is_some_and(|c| c.is_ascii_alphabetic()) {
                end += 1;
            }
            Some((chars[i..end].iter().collect(), end))
        }
        c => Some((c.to_string(), i + 1)),
    }
}

/// Hide scripts term-maths would stack, so they stay on one line. Scripts it can
/// render inline are left exactly as written, since it already handles those.
fn protect_scripts(src: &str) -> String {
    let chars: Vec<char> = src.chars().collect();
    let mut out = String::with_capacity(src.len());
    let mut i = 0;
    // The symbol the current script attaches to. Scripts do not update it, so
    // both halves of `\int_0^\infty` still see `\int` as their base.
    let mut base = String::new();

    while i < chars.len() {
        let c = chars[i];
        if c != '_' && c != '^' {
            if c == '\\' {
                let (cmd, next) = read_body(&chars, i).unwrap_or((c.to_string(), i + 1));
                out.push_str(&cmd);
                match cmd.as_str() {
                    KEEPS_LIMITS => {}
                    DROPS_LIMITS => base.clear(),
                    _ => base = cmd,
                }
                i = next;
                continue;
            }
            if !c.is_whitespace() {
                base = c.to_string();
            }
            out.push(c);
            i += 1;
            continue;
        }
        let up = c == '^';
        let Some((body, next)) = read_body(&chars, i + 1) else {
            out.push(c);
            i += 1;
            continue;
        };
        // Resolve \theta -> θ first: what matters is whether the *rendered*
        // script can sit inline, not whether the LaTeX source can.
        let rendered = unicodeit::replace(&body);
        if must_stack(&rendered, up) && !LARGE_OPS.contains(&base.as_str()) {
            out.push(if up { SUP_MARK } else { SUB_MARK });
            out.push_str(&rendered);
        } else {
            out.extend(&chars[i..next]);
        }
        i = next;
    }
    out
}

/// Layout via term-maths, falling back to flat symbol substitution when it
/// yields nothing. Panics are treated as a parse failure so a malformed formula
/// degrades instead of killing the process.
fn convert(src: &str) -> Option<String> {
    if src.len() > LAYOUT_LIMIT {
        let flat = unicodeit::replace(src);
        return (!flat.trim().is_empty()).then_some(flat);
    }

    let prepared = protect_scripts(src).replace(":=", &WALRUS_MARK.to_string());
    let laid_out = panic::catch_unwind(|| term_maths::render(&prepared).to_string()).ok();

    if let Some(text) = laid_out {
        let text = text
            .replace(SUB_MARK, "_")
            .replace(SUP_MARK, "^")
            .replace(WALRUS_MARK, ":=");
        if !text.trim().is_empty() {
            return Some(text);
        }
    }

    let flat = unicodeit::replace(src);
    (!flat.trim().is_empty()).then_some(flat)
}

/// Drop trailing spaces the grid layout pads with. render-markdown measures the
/// widest line to align the block, so trailing blanks would offset it.
fn trim_grid(text: &str) -> String {
    let lines: Vec<&str> = text.lines().map(str::trim_end).collect();
    match lines.iter().rposition(|line| !line.is_empty()) {
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

#[cfg(test)]
mod tests {
    use super::*;

    /// What a caller actually receives on stdout for `src`.
    fn render(src: &str) -> String {
        trim_grid(&convert(src).expect("converter produced no output"))
    }

    fn line_count(src: &str) -> usize {
        render(src).lines().count()
    }

    #[test]
    fn unmappable_script_stays_on_one_line() {
        // Unicode has no subscript theta, so the layout used to move it to a
        // second line and strand it away from the `h` it belongs to.
        assert_eq!(render(r"h_\theta(x)"), "h_θ(x)");
        assert_eq!(render(r"x_{\alpha}"), "x_α");
        // Several unmappable characters behave the same as one.
        assert_eq!(render(r"x_{\mu\nu}"), "x_μν");
    }

    #[test]
    fn walrus_is_not_split() {
        assert_eq!(render("a := b"), "a := b");
    }

    #[test]
    fn mappable_scripts_are_left_to_the_layout() {
        assert_eq!(render("x_i"), "xᵢ");
        assert_eq!(render("x_{ij}"), "xᵢⱼ");
        assert_eq!(render("x^{(i)}"), "x⁽ⁱ⁾");
        assert_eq!(render(r"\alpha^2 + \beta_{ij} \le \gamma"), "α² + βᵢⱼ ≤ γ");
    }

    #[test]
    fn large_operators_keep_stacked_limits() {
        // Limits belong above and below the operator, so these must stay 2D
        // even though theta cannot be written inline.
        assert!(line_count(r"\sum_\theta f") > 1);
        assert!(line_count(r"\int_0^\infty f") > 1);
        assert!(line_count(r"\max_\theta f") > 1);
        assert!(line_count(r"\bigoplus_\alpha X") > 1);
    }

    #[test]
    fn limits_and_nolimits_are_opposites() {
        // `\limits` keeps the operator's stacking; `\nolimits` asks for inline.
        assert!(line_count(r"\sum\limits_\theta f") > 1);
        assert_eq!(line_count(r"\sum\nolimits_\theta f"), 1);
    }

    #[test]
    fn oversized_input_skips_the_layout_pass() {
        // term-maths cost grows superlinearly, and render-markdown converts on
        // the UI thread, so past the cap the flat substitution runs instead.
        let big = "x + ".repeat(LAYOUT_LIMIT) + "y";
        assert!(big.len() > LAYOUT_LIMIT);

        let start = std::time::Instant::now();
        let out = render(&big);
        // The layout pass takes seconds at this size; substitution is immediate.
        assert!(
            start.elapsed() < std::time::Duration::from_secs(1),
            "oversized input took {:?}, layout pass was not skipped",
            start.elapsed()
        );
        assert!(out.contains('x'));
        assert_eq!(out.lines().count(), 1);
    }

    #[test]
    fn malformed_input_does_not_panic() {
        for src in [r"\frac{", "x^{2", r"\foobarbaz{x}", "hello world"] {
            let _ = convert(src);
        }
    }
}
