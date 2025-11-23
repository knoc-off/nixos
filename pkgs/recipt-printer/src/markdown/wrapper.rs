use escpos::utils::Font;

pub const LINE_WIDTH: usize = 42;

#[derive(Debug, Clone)]
pub enum WrapMode {
    Reflow,
    PreserveLines { overflow_indicator: String },
}

#[derive(Debug)]
pub struct LineOutput {
    pub content: String,
    pub overflow: Option<String>,
}

impl LineOutput {
    pub fn simple(content: String) -> Self {
        Self {
            content,
            overflow: None,
        }
    }

    pub fn with_overflow(content: String, overflow: String) -> Self {
        Self {
            content,
            overflow: Some(overflow),
        }
    }
}

pub struct LineWrapper {
    base_width: usize,  // 42 for Font A, 56 for Font B
    width_scale: usize, // Width multiplier from .size(w, h)
    indent: String,
    mode: WrapMode,
    current_line: String,
    col: usize,
}

impl LineWrapper {
    pub fn new() -> Self {
        Self {
            base_width: LINE_WIDTH,
            width_scale: 1,
            indent: String::new(),
            mode: WrapMode::Reflow,
            current_line: String::new(),
            col: 0,
        }
    }

    pub fn effective_width(&self) -> usize {
        self.base_width / self.width_scale
    }

    pub fn set_scale(&mut self, width: usize, _height: usize) {
        self.width_scale = width;
    }

    pub fn set_font(&mut self, font: Font) {
        self.base_width = match font {
            Font::A => 42,
            Font::B => 56,
            _ => 42, // Default to Font A
        };
    }

    pub fn set_indent(&mut self, indent: &str) {
        self.indent = indent.to_string();
    }

    pub fn set_mode(&mut self, mode: WrapMode) {
        self.mode = mode;
    }

    pub fn add_text(&mut self, text: &str) -> Vec<LineOutput> {
        match self.mode.clone() {
            WrapMode::Reflow => self.add_text_reflow(text),
            WrapMode::PreserveLines { overflow_indicator } => {
                self.add_text_preserve_lines(text, &overflow_indicator)
            }
        }
    }

    fn add_text_reflow(&mut self, text: &str) -> Vec<LineOutput> {
        let mut lines = Vec::new();
        let words = text.split_whitespace();
        let effective_width = self.effective_width();

        for word in words {
            let word_len = word.chars().count();
            let space_needed = if self.col == 0 || self.col == self.indent.chars().count() {
                0
            } else {
                1
            };

            // Check if adding this word would exceed line width
            if self.col > 0 && self.col + space_needed + word_len > effective_width {
                // Flush current line and start new one with indent
                lines.push(LineOutput::simple(self.current_line.clone()));
                self.current_line = self.indent.clone();
                self.col = self.indent.chars().count();
            }

            // Add space if not at start of line or right after indent
            if self.col > self.indent.chars().count() {
                self.current_line.push(' ');
                self.col += 1;
            }

            // Add the word
            self.current_line.push_str(word);
            self.col += word_len;
        }

        lines
    }

    fn add_text_preserve_lines(&mut self, text: &str, overflow_indicator: &str) -> Vec<LineOutput> {
        let mut outputs = Vec::new();
        let indicator_len = overflow_indicator.chars().count();
        let effective_width = self.effective_width();

        for line in text.lines() {
            let line_len = line.chars().count();

            if line_len <= effective_width {
                // Line fits, add as-is
                outputs.push(LineOutput::simple(line.to_string()));
            } else {
                // Line too long, truncate and create overflow
                let truncate_at = effective_width - indicator_len;
                let chars: Vec<char> = line.chars().collect();

                let main_part: String = chars.iter().take(truncate_at).collect();
                let overflow_part: String = chars.iter().skip(truncate_at).collect();

                let content = format!("{}{}", main_part, overflow_indicator);
                outputs.push(LineOutput::with_overflow(content, overflow_part));
            }
        }

        outputs
    }

    pub fn flush(&mut self) -> Option<String> {
        if !self.current_line.is_empty() {
            let line = self.current_line.clone();
            self.current_line.clear();
            self.col = 0;
            Some(line)
        } else {
            None
        }
    }

    pub fn start_line_with(&mut self, prefix: &str) {
        self.current_line = prefix.to_string();
        self.col = prefix.chars().count();
    }
}
