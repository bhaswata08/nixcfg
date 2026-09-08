use std::fs::File;
use std::io::{self, IsTerminal, Read, Seek, SeekFrom, Stdout};
use std::path::{Path, PathBuf};
use std::process::Command;
use std::time::{Duration, Instant};

use crossterm::{
    event::{self, Event, KeyCode, KeyEventKind, KeyModifiers},
    execute,
    terminal::{disable_raw_mode, enable_raw_mode, EnterAlternateScreen, LeaveAlternateScreen},
};
use ratatui::{
    backend::CrosstermBackend,
    layout::{Alignment, Constraint, Direction, Layout, Rect},
    style::{Color, Modifier, Style},
    text::{Line, Span},
    widgets::{Block, BorderType, Borders, Cell, Paragraph, Row, Table, TableState},
    Frame, Terminal,
};
use serde::Deserialize;

fn resolve_companion_path() -> Result<PathBuf, String> {
    let raw = match std::env::var("OCO_COMPANION") {
        Ok(val) if !val.trim().is_empty() => val,
        _ => "~/.claude/plugins/cache/tasict-opencode-plugin-cc/opencode/current/scripts/opencode-companion.mjs".to_string(),
    };

    let path = expand_tilde(&raw);
    if !path.exists() {
        return Err(format!(
            "opencode companion script not found at {}",
            path.display()
        ));
    }
    Ok(path)
}

fn expand_tilde(path_str: &str) -> PathBuf {
    if let Some(rest) = path_str.strip_prefix("~/") {
        if let Ok(home) = std::env::var("HOME") {
            return PathBuf::from(home).join(rest);
        }
    } else if path_str == "~" {
        if let Ok(home) = std::env::var("HOME") {
            return PathBuf::from(home);
        }
    }
    PathBuf::from(path_str)
}

#[derive(Debug, Deserialize, Clone, Default)]
#[serde(rename_all = "camelCase")]
pub struct StatusOutput {
    pub workspace_root: Option<String>,
    #[serde(default)]
    pub running: Vec<RawJob>,
    pub latest_finished: Option<RawJob>,
    #[serde(default)]
    pub recent: Vec<RawJob>,
}

#[derive(Debug, Deserialize, Clone, Default)]
#[serde(rename_all = "camelCase")]
pub struct RawJob {
    #[serde(default)]
    pub id: String,
    #[serde(default, rename = "type")]
    pub job_type: Option<String>,
    #[serde(default)]
    pub status: Option<String>,
    #[serde(default)]
    pub backend: Option<String>,
    #[serde(default)]
    pub agent: Option<String>,
    #[serde(default)]
    pub created_at: Option<String>,
    #[serde(default)]
    pub updated_at: Option<String>,
    #[serde(default)]
    pub completed_at: Option<String>,
    #[serde(default)]
    pub phase: Option<String>,
    #[serde(default)]
    pub elapsed: Option<String>,
    #[serde(default)]
    pub elapsed_ms: Option<u64>,
    #[serde(default)]
    pub request: Option<RawJobRequest>,
    #[serde(default)]
    pub error_message: Option<String>,
    #[serde(default)]
    pub log_file: Option<String>,
}

#[derive(Debug, Deserialize, Clone, Default)]
#[serde(rename_all = "camelCase")]
pub struct RawJobRequest {
    #[serde(default)]
    pub task_text: Option<String>,
    #[serde(default)]
    pub agent_name: Option<String>,
}

#[derive(Debug, Deserialize, Default)]
struct JobResultData {
    #[serde(default)]
    rendered: Option<String>,
}

#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub enum StatusCategory {
    Active,
    Completed,
    Failed,
    Cancelled,
    Unknown,
}

impl StatusCategory {
    pub fn from_status(status: &str) -> Self {
        match status.trim().to_lowercase().as_str() {
            "queued" | "starting" | "investigating" | "running" | "finalizing" => {
                StatusCategory::Active
            }
            "completed" => StatusCategory::Completed,
            "failed" => StatusCategory::Failed,
            "cancelled" | "canceled" => StatusCategory::Cancelled,
            _ => StatusCategory::Unknown,
        }
    }

    pub fn style(&self) -> Style {
        match self {
            StatusCategory::Active => Style::default()
                .fg(Color::Yellow)
                .add_modifier(Modifier::BOLD),
            StatusCategory::Completed => Style::default().fg(Color::Green),
            StatusCategory::Failed => Style::default().fg(Color::Red),
            StatusCategory::Cancelled => Style::default()
                .fg(Color::DarkGray)
                .add_modifier(Modifier::DIM),
            StatusCategory::Unknown => Style::default().fg(Color::Reset),
        }
    }
}

#[derive(Debug, Clone)]
pub struct JobItem {
    pub id: String,
    pub status: String,
    pub status_category: StatusCategory,
    pub type_agent: String,
    pub backend: String,
    pub elapsed: String,
    pub request_first_line: String,
    pub updated_at: Option<String>,
    pub created_at: Option<String>,
    pub log_file: Option<String>,
}

impl JobItem {
    pub fn from_raw(raw: RawJob) -> Self {
        let status_str = raw.status.unwrap_or_else(|| "unknown".to_string());
        let status_category = StatusCategory::from_status(&status_str);

        let agent = raw
            .agent
            .as_deref()
            .or_else(|| raw.request.as_ref().and_then(|r| r.agent_name.as_deref()));
        let type_agent = match (
            raw.job_type.as_deref().filter(|s| !s.is_empty()),
            agent.filter(|s| !s.is_empty()),
        ) {
            (Some(t), Some(a)) => format!("{t}/{a}"),
            (Some(t), None) => t.to_string(),
            (None, Some(a)) => a.to_string(),
            (None, None) => "-".to_string(),
        };

        let backend = raw.backend.unwrap_or_else(|| "-".to_string());

        let elapsed = if let Some(e) = raw.elapsed.filter(|s| !s.is_empty()) {
            e
        } else if let Some(ms) = raw.elapsed_ms {
            format_duration_ms(ms)
        } else {
            "-".to_string()
        };

        let request_first_line = raw
            .request
            .and_then(|r| r.task_text)
            .map(|t| {
                let first = t.lines().next().unwrap_or("").trim();
                first.replace(['\t', '\r'], " ")
            })
            .unwrap_or_default();

        Self {
            id: raw.id,
            status: status_str,
            status_category,
            type_agent,
            backend,
            elapsed,
            request_first_line,
            updated_at: raw.updated_at,
            created_at: raw.created_at,
            log_file: raw.log_file,
        }
    }
}

fn format_duration_ms(ms: u64) -> String {
    if ms < 1000 {
        "<1s".to_string()
    } else if ms < 60_000 {
        format!("{}s", ms / 1000)
    } else {
        let total_sec = ms / 1000;
        let mins = total_sec / 60;
        let secs = total_sec % 60;
        format!("{mins}m {secs}s")
    }
}

// The companion's jobDataPath is jobLogPath with .json, which is why swapping the extension is safe.
pub fn result_path_from_log_path(log_path: &Path) -> PathBuf {
    log_path.with_extension("json")
}

#[derive(Debug, PartialEq, Eq, Clone)]
pub enum TraceLine {
    ToolCall {
        timestamp: Option<String>,
        name: String,
        args: String,
    },
    ToolDone {
        timestamp: Option<String>,
        name: String,
        duration: Option<String>,
    },
    Thinking {
        timestamp: Option<String>,
        duration: Option<String>,
    },
    Phase {
        timestamp: Option<String>,
        phase: String,
        message: String,
    },
    Other {
        timestamp: Option<String>,
        text: String,
    },
}

impl TraceLine {
    pub fn timestamp(&self) -> Option<&str> {
        match self {
            TraceLine::ToolCall { timestamp, .. } => timestamp.as_deref(),
            TraceLine::ToolDone { timestamp, .. } => timestamp.as_deref(),
            TraceLine::Thinking { timestamp, .. } => timestamp.as_deref(),
            TraceLine::Phase { timestamp, .. } => timestamp.as_deref(),
            TraceLine::Other { timestamp, .. } => timestamp.as_deref(),
        }
    }
}

pub fn extract_timestamp(line: &str) -> (Option<String>, &str) {
    let trimmed = line.trim();
    if trimmed.starts_with('[') {
        if let Some(close_bracket) = trimmed.find(']') {
            let inside = &trimmed[1..close_bracket];
            if let Some(t_idx) = inside.find('T') {
                let time_part = &inside[t_idx + 1..];
                if time_part.len() >= 8 {
                    let b = time_part.as_bytes();
                    if b[0].is_ascii_digit()
                        && b[1].is_ascii_digit()
                        && b[2] == b':'
                        && b[3].is_ascii_digit()
                        && b[4].is_ascii_digit()
                        && b[5] == b':'
                        && b[6].is_ascii_digit()
                        && b[7].is_ascii_digit()
                    {
                        let hh_mm_ss = &time_part[..8];
                        let rest = trimmed[close_bracket + 1..].trim_start();
                        return (Some(hh_mm_ss.to_string()), rest);
                    }
                }
            }
        }
    }
    (None, trimmed)
}

pub fn parse_trace_line(raw: &str) -> TraceLine {
    let (timestamp, body) = extract_timestamp(raw);

    // 1. Tool lines
    if let Some(tool_rest) = body.strip_prefix("tool:") {
        let tool_rest = tool_rest.trim();

        // tool: NAME completed (DUR) or tool: NAME completed
        if let Some(comp_idx) = tool_rest.find(" completed") {
            let name = tool_rest[..comp_idx].trim().to_string();
            let after = tool_rest[comp_idx + " completed".len()..].trim();
            let duration = if after.starts_with('(') && after.ends_with(')') {
                Some(after[1..after.len() - 1].trim().to_string())
            } else if !after.is_empty() {
                Some(after.to_string())
            } else {
                None
            };
            return TraceLine::ToolDone {
                timestamp,
                name,
                duration,
            };
        }

        // tool: NAME (ARGS)
        if let Some(paren_start) = tool_rest.find('(') {
            let name = tool_rest[..paren_start].trim().to_string();
            let raw_args = tool_rest[paren_start + 1..].trim();
            let args = if let Some(stripped) = raw_args.strip_suffix(')') {
                stripped.to_string()
            } else {
                raw_args.to_string()
            };
            return TraceLine::ToolCall {
                timestamp,
                name,
                args,
            };
        }

        if !tool_rest.contains("failed:") && !tool_rest.is_empty() {
            return TraceLine::ToolCall {
                timestamp,
                name: tool_rest.to_string(),
                args: String::new(),
            };
        }
    }

    // 2. agent thinking completed (DUR) or agent thinking completed
    if let Some(think_rest) = body.strip_prefix("agent thinking completed") {
        let after = think_rest.trim();
        let duration = if after.starts_with('(') && after.ends_with(')') {
            Some(after[1..after.len() - 1].trim().to_string())
        } else if !after.is_empty() {
            Some(after.to_string())
        } else {
            None
        };
        return TraceLine::Thinking {
            timestamp,
            duration,
        };
    }

    // 3. [phase] message
    if body.starts_with('[') {
        if let Some(close_idx) = body.find(']') {
            let phase = body[1..close_idx].trim().to_string();
            let message = body[close_idx + 1..].trim().to_string();
            return TraceLine::Phase {
                timestamp,
                phase,
                message,
            };
        }
    }

    // 4. anything else
    TraceLine::Other {
        timestamp,
        text: body.to_string(),
    }
}

#[derive(Debug, PartialEq, Eq, Clone)]
pub struct ProcessedTraceEntry {
    pub line: TraceLine,
    pub raw_body: String,
    pub count: usize,
}

pub fn collapse_trace_lines(raw_lines: &[&str]) -> Vec<ProcessedTraceEntry> {
    let mut entries: Vec<ProcessedTraceEntry> = Vec::new();

    for line in raw_lines {
        let (_ts, body) = extract_timestamp(line);
        let parsed = parse_trace_line(line);

        if let Some(last) = entries.last_mut() {
            if last.raw_body == body {
                last.count += 1;
                continue;
            }
        }

        entries.push(ProcessedTraceEntry {
            line: parsed,
            raw_body: body.to_string(),
            count: 1,
        });
    }

    entries
}

pub fn render_trace_entry(entry: &ProcessedTraceEntry, pane_width: u16) -> Line<'static> {
    let suffix = if entry.count > 1 {
        format!(" (x{})", entry.count)
    } else {
        String::new()
    };

    let mut spans = Vec::new();

    if let Some(ts) = entry.line.timestamp() {
        spans.push(Span::styled(
            format!("{ts} "),
            Style::default().add_modifier(Modifier::DIM),
        ));
    }

    let ts_len = entry.line.timestamp().map(|t| t.len() + 1).unwrap_or(0);

    match &entry.line {
        TraceLine::ToolCall { name, args, .. } => {
            let args_display = if args.is_empty() {
                String::new()
            } else {
                format!("({args})")
            };

            let prefix_len = ts_len + name.len() + 1 + suffix.len();
            let width = pane_width as usize;

            let final_args = if width > 0 && prefix_len + args_display.len() > width {
                let available = width.saturating_sub(prefix_len);
                if available >= 1 {
                    let mut truncated: String = args_display
                        .chars()
                        .take(available.saturating_sub(1))
                        .collect();
                    truncated.push('\u{2026}');
                    truncated
                } else {
                    "\u{2026}".to_string()
                }
            } else {
                args_display
            };

            spans.push(Span::styled(
                format!("{name} "),
                Style::default()
                    .fg(Color::Cyan)
                    .add_modifier(Modifier::BOLD),
            ));
            spans.push(Span::styled(
                format!("{final_args}{suffix}"),
                Style::default().add_modifier(Modifier::DIM),
            ));
        }
        TraceLine::ToolDone { name, duration, .. } => {
            let text = if let Some(dur) = duration {
                format!("{name} done {dur}{suffix}")
            } else {
                format!("{name} done{suffix}")
            };
            spans.push(Span::styled(
                text,
                Style::default()
                    .fg(Color::Green)
                    .add_modifier(Modifier::DIM),
            ));
        }
        TraceLine::Thinking { duration, .. } => {
            let text = if let Some(dur) = duration {
                format!("agent thinking completed ({dur}){suffix}")
            } else {
                format!("agent thinking completed{suffix}")
            };
            spans.push(Span::styled(
                text,
                Style::default()
                    .fg(Color::DarkGray)
                    .add_modifier(Modifier::DIM),
            ));
        }
        TraceLine::Phase { phase, message, .. } => {
            spans.push(Span::styled(
                format!("[{phase}] "),
                Style::default().fg(Color::Yellow),
            ));
            spans.push(Span::raw(format!("{message}{suffix}")));
        }
        TraceLine::Other { text, .. } => {
            spans.push(Span::raw(format!("{text}{suffix}")));
        }
    }

    Line::from(spans)
}

pub fn bound_lines(lines: &[&str], max_lines: usize) -> Vec<String> {
    let count = lines.len();
    let start = count.saturating_sub(max_lines);
    lines[start..].iter().map(|s| s.to_string()).collect()
}

pub fn clamp_scroll(scroll: usize, total_lines: usize, visible_lines: usize) -> usize {
    let max_scroll = total_lines.saturating_sub(visible_lines);
    scroll.min(max_scroll)
}

pub fn wrap_text(text: &str, max_width: usize) -> Vec<String> {
    if max_width == 0 {
        return text.lines().map(|s| s.to_string()).collect();
    }
    let mut result = Vec::new();
    for line in text.lines() {
        let trimmed = line.trim_end();
        if trimmed.is_empty() {
            result.push(String::new());
            continue;
        }
        if trimmed.len() <= max_width {
            result.push(trimmed.to_string());
            continue;
        }
        let mut cur = String::new();
        for word in trimmed.split_whitespace() {
            if cur.is_empty() {
                if word.len() > max_width {
                    let mut rem = word;
                    while rem.len() > max_width {
                        result.push(rem[..max_width].to_string());
                        rem = &rem[max_width..];
                    }
                    cur.push_str(rem);
                } else {
                    cur.push_str(word);
                }
            } else if cur.len() + 1 + word.len() <= max_width {
                cur.push(' ');
                cur.push_str(word);
            } else {
                result.push(cur);
                cur = String::new();
                if word.len() > max_width {
                    let mut rem = word;
                    while rem.len() > max_width {
                        result.push(rem[..max_width].to_string());
                        rem = &rem[max_width..];
                    }
                    cur.push_str(rem);
                } else {
                    cur.push_str(word);
                }
            }
        }
        if !cur.is_empty() {
            result.push(cur);
        }
    }
    result
}

const MAX_LOG_READ_BYTES: u64 = 256 * 1024; // 256 KB
const MAX_LOG_LINES: usize = 800;

fn read_log_tail(path: &Path) -> io::Result<Vec<String>> {
    let mut file = File::open(path)?;
    let metadata = file.metadata()?;
    let file_len = metadata.len();
    let seek_pos = file_len.saturating_sub(MAX_LOG_READ_BYTES);

    file.seek(SeekFrom::Start(seek_pos))?;
    let mut buffer = Vec::with_capacity((file_len - seek_pos) as usize);
    file.read_to_end(&mut buffer)?;

    let content = String::from_utf8_lossy(&buffer);
    let mut raw_lines: Vec<&str> = content.lines().collect();

    if seek_pos > 0 && !buffer.starts_with(b"\n") && !raw_lines.is_empty() {
        raw_lines.remove(0);
    }

    Ok(bound_lines(&raw_lines, MAX_LOG_LINES))
}

fn load_detail_lines(job: &JobItem, inner_width: u16) -> Vec<Line<'static>> {
    let mut lines = Vec::new();
    let log_path_buf = job.log_file.as_ref().map(PathBuf::from);
    let mut loaded_trace = false;

    if let Some(ref log_path) = log_path_buf {
        if log_path.exists() {
            if let Ok(raw_strings) = read_log_tail(log_path) {
                let slice: Vec<&str> = raw_strings.iter().map(|s| s.as_str()).collect();
                let entries = collapse_trace_lines(&slice);
                for entry in entries {
                    lines.push(render_trace_entry(&entry, inner_width));
                }
                loaded_trace = true;
            }
        }
    }

    if let Some(ref log_path) = log_path_buf {
        // The companion's jobDataPath is jobLogPath with .json, which is why swapping the extension is safe.
        let result_path = result_path_from_log_path(log_path);
        if result_path.exists() {
            if let Ok(content) = std::fs::read_to_string(&result_path) {
                if let Ok(res) = serde_json::from_str::<JobResultData>(&content) {
                    if let Some(rendered) = res.rendered.filter(|r| !r.trim().is_empty()) {
                        let sep_width = inner_width as usize;
                        let left_dash = "---";
                        let label = " Result ";
                        let used = left_dash.len() + label.len();
                        let right_dash = if sep_width > used {
                            "-".repeat(sep_width - used)
                        } else {
                            "---".to_string()
                        };
                        let sep_text = format!("{left_dash}{label}{right_dash}");

                        lines.push(Line::from(Span::styled(
                            sep_text,
                            Style::default()
                                .fg(Color::Yellow)
                                .add_modifier(Modifier::BOLD),
                        )));

                        let wrapped = wrap_text(&rendered, inner_width as usize);
                        for wrap_line in wrapped {
                            lines.push(Line::from(Span::raw(wrap_line)));
                        }
                    }
                }
            }
        }
    }

    if lines.is_empty() {
        if loaded_trace {
            lines.push(Line::from(Span::styled(
                "Log file is empty.",
                Style::default().fg(Color::DarkGray),
            )));
        } else {
            lines.push(Line::from(Span::styled(
                "No trace log available for this job.",
                Style::default().fg(Color::DarkGray),
            )));
        }
    }

    lines
}

#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub enum FocusedPane {
    Table,
    Detail,
}

pub struct DetailCache {
    pub job_id: String,
    pub log_len: u64,
    pub result_len: Option<u64>,
    pub width: u16,
    pub lines: Vec<Line<'static>>,
}

pub struct App {
    pub companion_path: PathBuf,
    pub workspace_root: String,
    pub jobs: Vec<JobItem>,
    pub running_count: usize,
    pub recent_count: usize,
    pub table_state: TableState,
    pub should_quit: bool,
    pub last_error: Option<String>,
    pub visible_rows: usize,

    pub focused_pane: FocusedPane,
    pub detail_scroll: usize,
    pub detail_auto_follow: bool,
    pub detail_visible_lines: usize,
    pub detail_total_lines: usize,
    pub detail_cache: Option<DetailCache>,
    pub last_selected_job_id: Option<String>,
}

impl App {
    pub fn new(companion_path: PathBuf) -> Self {
        let mut app = Self {
            companion_path,
            workspace_root: ".".to_string(),
            jobs: Vec::new(),
            running_count: 0,
            recent_count: 0,
            table_state: TableState::default(),
            should_quit: false,
            last_error: None,
            visible_rows: 10,
            focused_pane: FocusedPane::Table,
            detail_scroll: 0,
            detail_auto_follow: true,
            detail_visible_lines: 10,
            detail_total_lines: 0,
            detail_cache: None,
            last_selected_job_id: None,
        };
        app.refresh();
        app
    }

    pub fn selected_job(&self) -> Option<&JobItem> {
        self.table_state.selected().and_then(|i| self.jobs.get(i))
    }

    pub fn check_selection_changed(&mut self) {
        let current_id = self.selected_job().map(|j| j.id.clone());
        if current_id != self.last_selected_job_id {
            self.last_selected_job_id = current_id;
            self.reset_detail_to_bottom();
        }
    }

    pub fn reset_detail_to_bottom(&mut self) {
        self.detail_auto_follow = true;
        self.detail_scroll = self.max_detail_scroll();
    }

    pub fn max_detail_scroll(&self) -> usize {
        self.detail_total_lines
            .saturating_sub(self.detail_visible_lines)
    }

    pub fn scroll_detail_down(&mut self, amount: usize) {
        let max = self.max_detail_scroll();
        self.detail_scroll = clamp_scroll(
            self.detail_scroll + amount,
            self.detail_total_lines,
            self.detail_visible_lines,
        );
        if self.detail_scroll >= max {
            self.detail_auto_follow = true;
        }
    }

    pub fn scroll_detail_up(&mut self, amount: usize) {
        self.detail_scroll = self.detail_scroll.saturating_sub(amount);
        self.detail_auto_follow = false;
    }

    pub fn scroll_detail_top(&mut self) {
        self.detail_scroll = 0;
        if self.max_detail_scroll() > 0 {
            self.detail_auto_follow = false;
        }
    }

    pub fn scroll_detail_bottom(&mut self) {
        self.detail_scroll = self.max_detail_scroll();
        self.detail_auto_follow = true;
    }

    pub fn scroll_detail_half_page_down(&mut self) {
        let amount = (self.detail_visible_lines / 2).max(1);
        self.scroll_detail_down(amount);
    }

    pub fn scroll_detail_half_page_up(&mut self) {
        let amount = (self.detail_visible_lines / 2).max(1);
        self.scroll_detail_up(amount);
    }

    pub fn toggle_focus(&mut self) {
        self.focused_pane = match self.focused_pane {
            FocusedPane::Table => FocusedPane::Detail,
            FocusedPane::Detail => FocusedPane::Table,
        };
    }

    pub fn refresh(&mut self) {
        match fetch_status(&self.companion_path) {
            Ok(data) => {
                if let Some(ws) = data.workspace_root {
                    self.workspace_root = ws;
                }

                let mut running: Vec<JobItem> =
                    data.running.into_iter().map(JobItem::from_raw).collect();
                sort_jobs_newest_first(&mut running);

                let mut recent_raw = Vec::new();
                if let Some(lf) = data.latest_finished {
                    recent_raw.push(lf);
                }
                recent_raw.extend(data.recent);

                let mut recent: Vec<JobItem> = Vec::new();
                for r in recent_raw {
                    if !running.iter().any(|j| j.id == r.id) && !recent.iter().any(|j| j.id == r.id)
                    {
                        recent.push(JobItem::from_raw(r));
                    }
                }
                sort_jobs_newest_first(&mut recent);

                self.running_count = running.len();
                self.recent_count = recent.len();

                let mut combined = running;
                combined.extend(recent);
                self.jobs = combined;
                self.last_error = None;

                if self.jobs.is_empty() {
                    self.table_state.select(None);
                } else {
                    let current = self.table_state.selected().unwrap_or(0);
                    self.table_state
                        .select(Some(current.min(self.jobs.len() - 1)));
                }
                self.check_selection_changed();
            }
            Err(err) => {
                self.last_error = Some(err);
            }
        }
    }

    pub fn move_down(&mut self, amount: usize) {
        if self.jobs.is_empty() {
            self.table_state.select(None);
            return;
        }
        let current = self.table_state.selected().unwrap_or(0);
        let next = (current + amount).min(self.jobs.len() - 1);
        self.table_state.select(Some(next));
        self.check_selection_changed();
    }

    pub fn move_up(&mut self, amount: usize) {
        if self.jobs.is_empty() {
            self.table_state.select(None);
            return;
        }
        let current = self.table_state.selected().unwrap_or(0);
        let next = current.saturating_sub(amount);
        self.table_state.select(Some(next));
        self.check_selection_changed();
    }

    pub fn select_first(&mut self) {
        if !self.jobs.is_empty() {
            self.table_state.select(Some(0));
            self.check_selection_changed();
        }
    }

    pub fn select_last(&mut self) {
        if !self.jobs.is_empty() {
            self.table_state.select(Some(self.jobs.len() - 1));
            self.check_selection_changed();
        }
    }

    pub fn half_page_down(&mut self) {
        let amount = (self.visible_rows / 2).max(1);
        self.move_down(amount);
    }

    pub fn half_page_up(&mut self) {
        let amount = (self.visible_rows / 2).max(1);
        self.move_up(amount);
    }
}

fn sort_jobs_newest_first(jobs: &mut [JobItem]) {
    jobs.sort_by(|a, b| {
        let key_a = a
            .updated_at
            .as_deref()
            .or(a.created_at.as_deref())
            .unwrap_or("");
        let key_b = b
            .updated_at
            .as_deref()
            .or(b.created_at.as_deref())
            .unwrap_or("");
        key_b.cmp(key_a)
    });
}

fn fetch_status(companion: &Path) -> Result<StatusOutput, String> {
    let output = Command::new("node")
        .arg(companion)
        .arg("status")
        .arg("--json")
        .arg("--all")
        .output()
        .map_err(|e| format!("failed to execute node: {e}"))?;

    if !output.status.success() {
        let stderr = String::from_utf8_lossy(&output.stderr);
        return Err(format!("companion failed: {}", stderr.trim()));
    }

    let stdout = String::from_utf8_lossy(&output.stdout);
    serde_json::from_str(&stdout).map_err(|e| format!("invalid json: {e}"))
}

struct TerminalGuard;

impl Drop for TerminalGuard {
    fn drop(&mut self) {
        let _ = disable_raw_mode();
        let _ = execute!(io::stdout(), LeaveAlternateScreen, crossterm::cursor::Show);
    }
}

fn setup_panic_hook() {
    let original = std::panic::take_hook();
    std::panic::set_hook(Box::new(move |info| {
        let _ = disable_raw_mode();
        let _ = execute!(io::stdout(), LeaveAlternateScreen, crossterm::cursor::Show);
        original(info);
    }));
}

fn render_ui(frame: &mut Frame, app: &mut App) {
    let area = frame.area();

    // Guard narrow or short window against subtraction overflow
    if area.width < 10 || area.height < 4 {
        let msg = Paragraph::new("Terminal too small")
            .alignment(Alignment::Center)
            .style(Style::default().fg(Color::DarkGray));
        frame.render_widget(msg, area);
        return;
    }

    let chunks = Layout::default()
        .direction(Direction::Vertical)
        .constraints([
            Constraint::Length(3),
            Constraint::Min(1),
            Constraint::Length(1),
        ])
        .split(area);

    let header_area = chunks[0];
    let main_area = chunks[1];
    let footer_area = chunks[2];

    let (table_area, detail_area): (Rect, Option<Rect>) = if area.height < 20 {
        (main_area, None)
    } else {
        let main_chunks = Layout::default()
            .direction(Direction::Vertical)
            .constraints([Constraint::Percentage(55), Constraint::Percentage(45)])
            .split(main_area);
        (main_chunks[0], Some(main_chunks[1]))
    };

    // Compute visible rows for half-page scrolling (excluding headers and borders)
    app.visible_rows = table_area.height.saturating_sub(3) as usize;

    let mut header_spans = vec![
        Span::styled("Workspace: ", Style::default().add_modifier(Modifier::BOLD)),
        Span::styled(&app.workspace_root, Style::default().fg(Color::Cyan)),
        Span::raw("  |  "),
        Span::styled(
            format!("{} running", app.running_count),
            Style::default()
                .fg(Color::Yellow)
                .add_modifier(Modifier::BOLD),
        ),
        Span::raw(", "),
        Span::styled(
            format!("{} recent", app.recent_count),
            Style::default()
                .fg(Color::Green)
                .add_modifier(Modifier::BOLD),
        ),
        Span::raw(format!(" ({} total)", app.jobs.len())),
    ];

    if let Some(err) = &app.last_error {
        header_spans.push(Span::raw("  |  "));
        header_spans.push(Span::styled(
            format!("Error: {err}"),
            Style::default().fg(Color::Red),
        ));
    }

    let header_block = Block::default()
        .borders(Borders::ALL)
        .border_type(BorderType::Rounded)
        .title(" OpenCode Companion ");
    let header_paragraph = Paragraph::new(Line::from(header_spans)).block(header_block);
    frame.render_widget(header_paragraph, header_area);

    let table_border_style = if app.focused_pane == FocusedPane::Table || detail_area.is_none() {
        Style::default().fg(Color::Cyan)
    } else {
        Style::default().fg(Color::DarkGray)
    };

    if app.jobs.is_empty() {
        let empty_block = Block::default()
            .borders(Borders::ALL)
            .border_type(BorderType::Rounded)
            .border_style(table_border_style)
            .title(" Jobs ");
        let empty_text = Paragraph::new("No OpenCode jobs found for this workspace.")
            .block(empty_block)
            .alignment(Alignment::Center)
            .style(Style::default().fg(Color::DarkGray));
        frame.render_widget(empty_text, table_area);
    } else {
        let widths = [
            Constraint::Length(13),
            Constraint::Length(20),
            Constraint::Length(12),
            Constraint::Length(9),
            Constraint::Length(8),
            Constraint::Min(10),
        ];

        let rows: Vec<Row> = app
            .jobs
            .iter()
            .map(|job| {
                let status_style = job.status_category.style();
                Row::new(vec![
                    Cell::from(job.status.as_str()).style(status_style),
                    Cell::from(job.id.as_str()),
                    Cell::from(job.type_agent.as_str()),
                    Cell::from(job.backend.as_str()),
                    Cell::from(job.elapsed.as_str()),
                    Cell::from(job.request_first_line.as_str()),
                ])
            })
            .collect();

        let table = Table::new(rows, widths)
            .header(
                Row::new(vec![
                    "STATUS",
                    "ID",
                    "TYPE/AGENT",
                    "BACKEND",
                    "ELAPSED",
                    "REQUEST",
                ])
                .style(Style::default().add_modifier(Modifier::BOLD))
                .bottom_margin(1),
            )
            .block(
                Block::default()
                    .borders(Borders::ALL)
                    .border_type(BorderType::Rounded)
                    .border_style(table_border_style)
                    .title(" Jobs "),
            )
            .row_highlight_style(
                Style::default()
                    .bg(Color::DarkGray)
                    .add_modifier(Modifier::BOLD),
            )
            .highlight_symbol("> ");

        frame.render_stateful_widget(table, table_area, &mut app.table_state);
    }

    if let Some(d_area) = detail_area {
        let inner_width = d_area.width.saturating_sub(2);
        let inner_height = d_area.height.saturating_sub(2);
        app.detail_visible_lines = inner_height as usize;

        let (job_id, _log_path, log_len, result_len) = if let Some(job) = app.selected_job() {
            let p = job.log_file.as_ref().map(PathBuf::from);
            let l_len = p
                .as_ref()
                .and_then(|lp| std::fs::metadata(lp).ok())
                .map(|m| m.len())
                .unwrap_or(0);
            let r_len = p.as_ref().and_then(|lp| {
                let rp = result_path_from_log_path(lp);
                std::fs::metadata(rp).ok().map(|m| m.len())
            });
            (Some(job.id.clone()), p, l_len, r_len)
        } else {
            (None, None, 0, None)
        };

        let need_reload = match &app.detail_cache {
            Some(cache) => match &job_id {
                Some(id) => {
                    cache.job_id != *id
                        || cache.log_len != log_len
                        || cache.result_len != result_len
                        || cache.width != inner_width
                }
                None => true,
            },
            None => true,
        };

        if need_reload {
            let lines = if let Some(job) = app.selected_job() {
                load_detail_lines(job, inner_width)
            } else {
                vec![Line::from(Span::styled(
                    "No job selected.",
                    Style::default().fg(Color::DarkGray),
                ))]
            };

            if let Some(id) = job_id {
                app.detail_cache = Some(DetailCache {
                    job_id: id,
                    log_len,
                    result_len,
                    width: inner_width,
                    lines,
                });
            } else {
                app.detail_cache = None;
            }
        }

        let detail_lines = app
            .detail_cache
            .as_ref()
            .map(|c| c.lines.clone())
            .unwrap_or_default();

        app.detail_total_lines = detail_lines.len();

        if app.detail_auto_follow {
            app.detail_scroll = app.max_detail_scroll();
        } else {
            app.detail_scroll = clamp_scroll(
                app.detail_scroll,
                app.detail_total_lines,
                app.detail_visible_lines,
            );
        }

        let detail_border_style = if app.focused_pane == FocusedPane::Detail {
            Style::default().fg(Color::Cyan)
        } else {
            Style::default().fg(Color::DarkGray)
        };

        let detail_block = Block::default()
            .borders(Borders::ALL)
            .border_type(BorderType::Rounded)
            .border_style(detail_border_style)
            .title(" Detail ");

        let detail_paragraph = Paragraph::new(detail_lines)
            .block(detail_block)
            .scroll((app.detail_scroll as u16, 0));

        frame.render_widget(detail_paragraph, d_area);
    }

    let footer_spans = vec![
        Span::styled(
            " Tab",
            Style::default()
                .fg(Color::Cyan)
                .add_modifier(Modifier::BOLD),
        ),
        Span::raw(": focus  "),
        Span::styled(
            "j/k",
            Style::default()
                .fg(Color::Cyan)
                .add_modifier(Modifier::BOLD),
        ),
        Span::raw(": nav/scroll  "),
        Span::styled(
            "g/G",
            Style::default()
                .fg(Color::Cyan)
                .add_modifier(Modifier::BOLD),
        ),
        Span::raw(": top/bottom  "),
        Span::styled(
            "^d/^u",
            Style::default()
                .fg(Color::Cyan)
                .add_modifier(Modifier::BOLD),
        ),
        Span::raw(": half-page  "),
        Span::styled(
            "r",
            Style::default()
                .fg(Color::Cyan)
                .add_modifier(Modifier::BOLD),
        ),
        Span::raw(": refresh  "),
        Span::styled(
            "q",
            Style::default()
                .fg(Color::Cyan)
                .add_modifier(Modifier::BOLD),
        ),
        Span::raw(": quit"),
    ];
    let footer_paragraph = Paragraph::new(Line::from(footer_spans))
        .style(Style::default().bg(Color::DarkGray).fg(Color::White));
    frame.render_widget(footer_paragraph, footer_area);
}

fn run_app(
    terminal: &mut Terminal<CrosstermBackend<Stdout>>,
    mut app: App,
) -> Result<(), Box<dyn std::error::Error>> {
    let refresh_interval = Duration::from_secs(3);
    let mut last_refresh = Instant::now();

    loop {
        terminal.draw(|f| render_ui(f, &mut app))?;

        let time_until_refresh = refresh_interval.saturating_sub(last_refresh.elapsed());
        let poll_timeout = time_until_refresh.min(Duration::from_millis(250));

        if event::poll(poll_timeout)? {
            if let Event::Key(key) = event::read()? {
                if key.kind == KeyEventKind::Press {
                    match key.code {
                        KeyCode::Char('q') => break,
                        KeyCode::Char('c') if key.modifiers.contains(KeyModifiers::CONTROL) => {
                            break
                        }
                        KeyCode::Tab => {
                            app.toggle_focus();
                        }
                        KeyCode::Char('j') | KeyCode::Down => {
                            if app.focused_pane == FocusedPane::Table {
                                app.move_down(1);
                            } else {
                                app.scroll_detail_down(1);
                            }
                        }
                        KeyCode::Char('k') | KeyCode::Up => {
                            if app.focused_pane == FocusedPane::Table {
                                app.move_up(1);
                            } else {
                                app.scroll_detail_up(1);
                            }
                        }
                        KeyCode::Char('g') => {
                            if app.focused_pane == FocusedPane::Table {
                                app.select_first();
                            } else {
                                app.scroll_detail_top();
                            }
                        }
                        KeyCode::Char('G') => {
                            if app.focused_pane == FocusedPane::Table {
                                app.select_last();
                            } else {
                                app.scroll_detail_bottom();
                            }
                        }
                        KeyCode::Char('d') if key.modifiers.contains(KeyModifiers::CONTROL) => {
                            if app.focused_pane == FocusedPane::Table {
                                app.half_page_down();
                            } else {
                                app.scroll_detail_half_page_down();
                            }
                        }
                        KeyCode::Char('u') if key.modifiers.contains(KeyModifiers::CONTROL) => {
                            if app.focused_pane == FocusedPane::Table {
                                app.half_page_up();
                            } else {
                                app.scroll_detail_half_page_up();
                            }
                        }
                        KeyCode::Char('r') => {
                            app.refresh();
                            last_refresh = Instant::now();
                        }
                        _ => {}
                    }
                }
            }
        }

        if last_refresh.elapsed() >= refresh_interval {
            app.refresh();
            last_refresh = Instant::now();
        }

        if app.should_quit {
            break;
        }
    }

    Ok(())
}

fn main() -> Result<(), Box<dyn std::error::Error>> {
    if !io::stdout().is_terminal() {
        eprintln!(
            "oco-tui needs an interactive terminal; use `oco status` when piping or scripting."
        );
        std::process::exit(1);
    }

    let companion_path = match resolve_companion_path() {
        Ok(p) => p,
        Err(err) => {
            eprintln!("{err}");
            std::process::exit(1);
        }
    };

    setup_panic_hook();

    enable_raw_mode()?;
    let mut stdout = io::stdout();
    execute!(stdout, EnterAlternateScreen, crossterm::cursor::Hide)?;
    let _guard = TerminalGuard;

    let backend = CrosstermBackend::new(stdout);
    let mut terminal = Terminal::new(backend)?;

    let app = App::new(companion_path);
    run_app(&mut terminal, app)?;

    Ok(())
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn test_status_category_classification() {
        assert_eq!(
            StatusCategory::from_status("queued"),
            StatusCategory::Active
        );
        assert_eq!(
            StatusCategory::from_status("starting"),
            StatusCategory::Active
        );
        assert_eq!(
            StatusCategory::from_status("investigating"),
            StatusCategory::Active
        );
        assert_eq!(
            StatusCategory::from_status("running"),
            StatusCategory::Active
        );
        assert_eq!(
            StatusCategory::from_status("finalizing"),
            StatusCategory::Active
        );
        assert_eq!(
            StatusCategory::from_status("completed"),
            StatusCategory::Completed
        );
        assert_eq!(
            StatusCategory::from_status("failed"),
            StatusCategory::Failed
        );
        assert_eq!(
            StatusCategory::from_status("cancelled"),
            StatusCategory::Cancelled
        );
        assert_eq!(
            StatusCategory::from_status("canceled"),
            StatusCategory::Cancelled
        );
        assert_eq!(
            StatusCategory::from_status("UNKNOWN_PHASE"),
            StatusCategory::Unknown
        );
    }

    #[test]
    fn test_job_item_from_raw() {
        let raw = RawJob {
            id: "task-123".to_string(),
            job_type: Some("task".to_string()),
            status: Some("running".to_string()),
            backend: Some("agy".to_string()),
            agent: Some("coder".to_string()),
            created_at: Some("2026-09-07T10:00:00Z".to_string()),
            updated_at: Some("2026-09-07T10:05:00Z".to_string()),
            completed_at: None,
            phase: Some("investigating".to_string()),
            elapsed: Some("5m".to_string()),
            elapsed_ms: Some(300_000),
            request: Some(RawJobRequest {
                task_text: Some("First line of task\nSecond line".to_string()),
                agent_name: Some("coder".to_string()),
            }),
            error_message: None,
            log_file: Some("/tmp/task-123.log".to_string()),
        };

        let item = JobItem::from_raw(raw);
        assert_eq!(item.id, "task-123");
        assert_eq!(item.status, "running");
        assert_eq!(item.status_category, StatusCategory::Active);
        assert_eq!(item.type_agent, "task/coder");
        assert_eq!(item.backend, "agy");
        assert_eq!(item.elapsed, "5m");
        assert_eq!(item.request_first_line, "First line of task");
        assert_eq!(item.log_file, Some("/tmp/task-123.log".to_string()));
    }

    #[test]
    fn test_json_deserialization_resilience() {
        let json = r#"{
            "workspaceRoot": "/tmp/test",
            "running": [
                {
                    "id": "job-1",
                    "type": "task",
                    "status": "running",
                    "logFile": "/tmp/job-1.log"
                }
            ],
            "latestFinished": null,
            "recent": []
        }"#;

        let parsed: StatusOutput = serde_json::from_str(json).expect("should parse");
        assert_eq!(parsed.workspace_root, Some("/tmp/test".to_string()));
        assert_eq!(parsed.running.len(), 1);
        assert_eq!(parsed.running[0].id, "job-1");
        assert_eq!(
            parsed.running[0].log_file,
            Some("/tmp/job-1.log".to_string())
        );
        assert_eq!(parsed.recent.len(), 0);
    }

    #[test]
    fn test_format_duration() {
        assert_eq!(format_duration_ms(500), "<1s");
        assert_eq!(format_duration_ms(45_000), "45s");
        assert_eq!(format_duration_ms(125_000), "2m 5s");
    }

    #[test]
    fn test_render_empty_and_small_terminals() {
        use ratatui::backend::TestBackend;

        for &(w, h) in &[(5, 2), (10, 3), (15, 5), (80, 24), (200, 60)] {
            let backend = TestBackend::new(w, h);
            let mut terminal = Terminal::new(backend).unwrap();
            let mut app = App {
                companion_path: PathBuf::from("/tmp"),
                workspace_root: "/home/user/project".to_string(),
                jobs: Vec::new(),
                running_count: 0,
                recent_count: 0,
                table_state: TableState::default(),
                should_quit: false,
                last_error: None,
                visible_rows: 10,
                focused_pane: FocusedPane::Table,
                detail_scroll: 0,
                detail_auto_follow: true,
                detail_visible_lines: 10,
                detail_total_lines: 0,
                detail_cache: None,
                last_selected_job_id: None,
            };
            terminal.draw(|f| render_ui(f, &mut app)).unwrap();
        }
    }

    #[test]
    fn test_parse_five_trace_line_shapes() {
        // 1. tool: NAME (ARGS) with timestamp
        let l1 = "[2026-09-08T04:12:14.893Z] tool: run_command (gh issue view 11)";
        assert_eq!(
            parse_trace_line(l1),
            TraceLine::ToolCall {
                timestamp: Some("04:12:14".to_string()),
                name: "run_command".to_string(),
                args: "gh issue view 11".to_string(),
            }
        );

        // 1b. tool: NAME (ARGS) without timestamp
        let l1_no_ts = "tool: run_command (gh issue view 11)";
        assert_eq!(
            parse_trace_line(l1_no_ts),
            TraceLine::ToolCall {
                timestamp: None,
                name: "run_command".to_string(),
                args: "gh issue view 11".to_string(),
            }
        );

        // 2. tool: NAME completed (DUR) with timestamp
        let l2 = "[2026-09-08T04:12:16.497Z] tool: run_command completed (1.66s)";
        assert_eq!(
            parse_trace_line(l2),
            TraceLine::ToolDone {
                timestamp: Some("04:12:16".to_string()),
                name: "run_command".to_string(),
                duration: Some("1.66s".to_string()),
            }
        );

        // 2b. tool: NAME completed without duration and without timestamp
        let l2_no_ts = "tool: view_file completed";
        assert_eq!(
            parse_trace_line(l2_no_ts),
            TraceLine::ToolDone {
                timestamp: None,
                name: "view_file".to_string(),
                duration: None,
            }
        );

        // 3. agent thinking completed (DUR) with timestamp
        let l3 = "[2026-09-08T04:12:14.892Z] agent thinking completed (6.16s)";
        assert_eq!(
            parse_trace_line(l3),
            TraceLine::Thinking {
                timestamp: Some("04:12:14".to_string()),
                duration: Some("6.16s".to_string()),
            }
        );

        // 3b. agent thinking completed without timestamp
        let l3_no_ts = "agent thinking completed (3.50s)";
        assert_eq!(
            parse_trace_line(l3_no_ts),
            TraceLine::Thinking {
                timestamp: None,
                duration: Some("3.50s".to_string()),
            }
        );

        // 4. [phase] message with timestamp
        let l4 = "[2026-09-08T04:11:37.311Z] [investigating] Running task...";
        assert_eq!(
            parse_trace_line(l4),
            TraceLine::Phase {
                timestamp: Some("04:11:37".to_string()),
                phase: "investigating".to_string(),
                message: "Running task...".to_string(),
            }
        );

        // 4b. [phase] message without timestamp
        let l4_no_ts = "[starting] Job task-123 started";
        assert_eq!(
            parse_trace_line(l4_no_ts),
            TraceLine::Phase {
                timestamp: None,
                phase: "starting".to_string(),
                message: "Job task-123 started".to_string(),
            }
        );

        // 5. anything else with timestamp
        let l5 =
            "[2026-09-08T04:12:04.462Z] session started (33102552-f3a4-4dbf-bdfd-d82a91758b82)";
        assert_eq!(
            parse_trace_line(l5),
            TraceLine::Other {
                timestamp: Some("04:12:04".to_string()),
                text: "session started (33102552-f3a4-4dbf-bdfd-d82a91758b82)".to_string(),
            }
        );

        // 5b. anything else without timestamp
        let l5_no_ts = "plain log line with no prefix";
        assert_eq!(
            parse_trace_line(l5_no_ts),
            TraceLine::Other {
                timestamp: None,
                text: "plain log line with no prefix".to_string(),
            }
        );
    }

    #[test]
    fn test_consecutive_duplicate_collapse() {
        let lines = [
            "[2026-09-08T04:11:34.980Z] [starting] Job task-mts5k9jg-69jhyt started",
            "[2026-09-08T04:11:34.980Z] [starting] Job task-mts5k9jg-69jhyt started",
            "[2026-09-08T04:11:35.055Z] [starting] Background worker connecting to OpenCode...",
            "[2026-09-08T04:11:35.055Z] [starting] Background worker connecting to OpenCode...",
            "[2026-09-08T04:12:14.893Z] tool: run_command (gh issue view 11)",
        ];

        let collapsed = collapse_trace_lines(&lines);
        assert_eq!(collapsed.len(), 3);
        assert_eq!(collapsed[0].count, 2);
        assert_eq!(collapsed[1].count, 2);
        assert_eq!(collapsed[2].count, 1);

        // Suffix (x2) rendered
        let rendered0 = render_trace_entry(&collapsed[0], 80);
        let text0: String = rendered0.spans.iter().map(|s| s.content.as_ref()).collect();
        assert!(text0.contains("(x2)"));

        let rendered2 = render_trace_entry(&collapsed[2], 80);
        let text2: String = rendered2.spans.iter().map(|s| s.content.as_ref()).collect();
        assert!(!text2.contains("(x"));
    }

    #[test]
    fn test_tail_bound_keeps_last_n_lines() {
        let lines: Vec<String> = (1..=10).map(|i| format!("line {i}")).collect();
        let slice: Vec<&str> = lines.iter().map(|s| s.as_str()).collect();

        let bounded = bound_lines(&slice, 4);
        assert_eq!(bounded.len(), 4);
        assert_eq!(bounded, vec!["line 7", "line 8", "line 9", "line 10"]);

        let bounded_all = bound_lines(&slice, 20);
        assert_eq!(bounded_all.len(), 10);
        assert_eq!(bounded_all[0], "line 1");
    }

    #[test]
    fn test_detail_scroll_clamping() {
        // Clamp at top: scroll 0 remains 0
        assert_eq!(clamp_scroll(0, 100, 20), 0);

        // Within range remains unchanged: 50 <= (100 - 20 = 80)
        assert_eq!(clamp_scroll(50, 100, 20), 50);

        // Clamp at bottom: scroll >= 80 clamps to 80
        assert_eq!(clamp_scroll(80, 100, 20), 80);
        assert_eq!(clamp_scroll(100, 100, 20), 80);
        assert_eq!(clamp_scroll(999, 100, 20), 80);

        // Total lines <= visible lines clamps to 0
        assert_eq!(clamp_scroll(10, 15, 20), 0);
        assert_eq!(clamp_scroll(0, 15, 20), 0);
    }

    #[test]
    fn test_render_ui_with_and_without_selection() {
        use ratatui::backend::TestBackend;

        let sample_job = JobItem {
            id: "task-test-1".to_string(),
            status: "running".to_string(),
            status_category: StatusCategory::Active,
            type_agent: "task/coder".to_string(),
            backend: "agy".to_string(),
            elapsed: "10s".to_string(),
            request_first_line: "do something".to_string(),
            updated_at: None,
            created_at: None,
            log_file: Some("/tmp/nonexistent-trace.log".to_string()),
        };

        // 1. With job selected, large terminal (detail pane ON)
        let backend = TestBackend::new(100, 30);
        let mut terminal = Terminal::new(backend).unwrap();
        let mut app = App {
            companion_path: PathBuf::from("/tmp"),
            workspace_root: "/test".to_string(),
            jobs: vec![sample_job.clone()],
            running_count: 1,
            recent_count: 0,
            table_state: {
                let mut s = TableState::default();
                s.select(Some(0));
                s
            },
            should_quit: false,
            last_error: None,
            visible_rows: 10,
            focused_pane: FocusedPane::Detail,
            detail_scroll: 0,
            detail_auto_follow: true,
            detail_visible_lines: 10,
            detail_total_lines: 0,
            detail_cache: None,
            last_selected_job_id: Some("task-test-1".to_string()),
        };
        terminal.draw(|f| render_ui(f, &mut app)).unwrap();

        // 2. With no job selected, large terminal
        let backend = TestBackend::new(100, 30);
        let mut terminal = Terminal::new(backend).unwrap();
        let mut app_no_jobs = App {
            companion_path: PathBuf::from("/tmp"),
            workspace_root: "/test".to_string(),
            jobs: Vec::new(),
            running_count: 0,
            recent_count: 0,
            table_state: TableState::default(),
            should_quit: false,
            last_error: None,
            visible_rows: 10,
            focused_pane: FocusedPane::Table,
            detail_scroll: 0,
            detail_auto_follow: true,
            detail_visible_lines: 10,
            detail_total_lines: 0,
            detail_cache: None,
            last_selected_job_id: None,
        };
        terminal.draw(|f| render_ui(f, &mut app_no_jobs)).unwrap();

        // 3. Small terminal (height < 20, detail pane dropped) with job selected
        let backend = TestBackend::new(60, 15);
        let mut terminal = Terminal::new(backend).unwrap();
        let mut app_small = App {
            companion_path: PathBuf::from("/tmp"),
            workspace_root: "/test".to_string(),
            jobs: vec![sample_job],
            running_count: 1,
            recent_count: 0,
            table_state: {
                let mut s = TableState::default();
                s.select(Some(0));
                s
            },
            should_quit: false,
            last_error: None,
            visible_rows: 10,
            focused_pane: FocusedPane::Table,
            detail_scroll: 0,
            detail_auto_follow: true,
            detail_visible_lines: 10,
            detail_total_lines: 0,
            detail_cache: None,
            last_selected_job_id: Some("task-test-1".to_string()),
        };
        terminal.draw(|f| render_ui(f, &mut app_small)).unwrap();
    }
}
