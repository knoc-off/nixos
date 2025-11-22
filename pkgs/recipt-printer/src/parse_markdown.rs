use escpos::printer::Printer;
use escpos::utils::*;
use pulldown_cmark::{Event, Options, Parser as MarkdownParser, Tag, TagEnd};

const LINE_WIDTH: usize = 42;
const FONT_B_WIDTH: usize = 56;

#[derive(Debug, Clone)]
enum WrapMode {
    Reflow,
    PreserveLines { overflow_indicator: String },
}

struct TableBuilder {
    rows: Vec<Vec<String>>,
    current_row: Vec<String>,
    current_cell: String,
    in_header: bool,
    header_row_count: usize,
}

impl TableBuilder {
    fn new() -> Self {
        Self {
            rows: Vec::new(),
            current_row: Vec::new(),
            current_cell: String::new(),
            in_header: false,
            header_row_count: 0,
        }
    }

    fn add_text(&mut self, text: &str) {
        self.current_cell.push_str(text);
    }

    fn end_cell(&mut self) {
        self.current_row.push(self.current_cell.clone());
        self.current_cell.clear();
    }

    fn end_row(&mut self) {
        if !self.current_row.is_empty() {
            self.rows.push(self.current_row.clone());
            self.current_row.clear();
            if self.in_header {
                self.header_row_count += 1;
            }
        }
    }

    fn format_table(&self) -> Vec<String> {
        if self.rows.is_empty() {
            return Vec::new();
        }

        // Calculate column widths
        let num_cols = self.rows.iter().map(|r| r.len()).max().unwrap_or(0);
        let mut col_widths = vec![0; num_cols];

        for row in &self.rows {
            for (i, cell) in row.iter().enumerate() {
                col_widths[i] = col_widths[i].max(cell.chars().count());
            }
        }

        // Calculate total width needed (including separators)
        let separators_width = num_cols + 1; // | between cells and edges
        let content_width: usize = col_widths.iter().sum();
        let total_needed = content_width + separators_width;

        // If table is too wide, try alternate layouts
        if total_needed > FONT_B_WIDTH {
            // Try transpose first
            if self.should_transpose() {
                return self.format_transposed();
            }

            // Fall back to chunking
            return self.format_chunked();
        }

        // If we have extra space, distribute it evenly
        if total_needed < FONT_B_WIDTH {
            let extra = FONT_B_WIDTH - total_needed;
            let per_col = extra / num_cols;
            let remainder = extra % num_cols;

            for (i, width) in col_widths.iter_mut().enumerate() {
                *width += per_col;
                if i < remainder {
                    *width += 1;
                }
            }
        }

        // Format rows
        let mut output = Vec::new();
        let separator = self.create_separator(&col_widths);

        output.push(separator.clone());
        for (idx, row) in self.rows.iter().enumerate() {
            output.push(self.format_row(row, &col_widths));
            // Add separator after header rows
            if idx + 1 == self.header_row_count {
                output.push(separator.clone());
            }
        }
        output.push(separator);

        output
    }

    fn create_separator(&self, col_widths: &[usize]) -> String {
        let mut sep = String::from("+");
        for width in col_widths {
            sep.push_str(&"-".repeat(*width));
            sep.push('+');
        }
        sep
    }

    fn format_row(&self, row: &[String], col_widths: &[usize]) -> String {
        let mut line = String::from("|");
        for (i, cell) in row.iter().enumerate() {
            let width = col_widths.get(i).copied().unwrap_or(0);
            let cell_len = cell.chars().count();
            let padding = width.saturating_sub(cell_len);

            line.push_str(cell);
            line.push_str(&" ".repeat(padding));
            line.push('|');
        }
        line
    }

    fn should_transpose(&self) -> bool {
        let num_rows = self.rows.len();
        if num_rows > 6 {
            return false; // Too many rows would make vertical too long
        }

        // Calculate average cell content length
        let total_chars: usize = self
            .rows
            .iter()
            .flat_map(|row| row.iter())
            .map(|cell| cell.chars().count())
            .sum();
        let total_cells = self.rows.iter().map(|r| r.len()).sum::<usize>();
        let avg_cell_len = if total_cells > 0 {
            total_chars / total_cells
        } else {
            0
        };

        if avg_cell_len > 25 {
            return false; // Cell content too long for transpose
        }

        // Calculate if transposed would fit
        // After transpose: headers become first col, each data row becomes a column
        let num_cols_after = num_rows; // Each original row becomes a column
        let header_row = if !self.rows.is_empty() {
            &self.rows[0]
        } else {
            return false;
        };

        // Find max width of header labels (these become first column)
        let max_header_width = header_row
            .iter()
            .map(|h| h.chars().count())
            .max()
            .unwrap_or(0);

        // Find max width of data cells (across all columns after transpose)
        let max_data_width = if self.rows.len() > 1 {
            self.rows
                .iter()
                .skip(self.header_row_count)
                .flat_map(|row| row.iter())
                .map(|cell| cell.chars().count())
                .max()
                .unwrap_or(0)
        } else {
            0
        };

        // Width calculation: | header_col | data_col1 | data_col2 | ...
        let separators = num_cols_after + 1;
        let content_width =
            max_header_width + (max_data_width * (num_cols_after - self.header_row_count));
        let total = separators + content_width;

        total <= FONT_B_WIDTH
    }

    fn format_transposed(&self) -> Vec<String> {
        if self.rows.is_empty() {
            return Vec::new();
        }

        // Transpose: headers become first column, data rows become additional columns
        let header_row = if self.header_row_count > 0 {
            &self.rows[0]
        } else {
            return Vec::new();
        };
        let data_rows: Vec<&Vec<String>> = self.rows.iter().skip(self.header_row_count).collect();

        let num_header_cells = header_row.len();
        let num_data_rows = data_rows.len();

        // Build transposed table
        let mut transposed = Vec::new();

        // Each header cell becomes a row
        for col_idx in 0..num_header_cells {
            let mut new_row = Vec::new();

            // First column: header label
            new_row.push(header_row[col_idx].clone());

            // Subsequent columns: data from each original row
            for data_row in &data_rows {
                let cell = data_row.get(col_idx).cloned().unwrap_or_default();
                new_row.push(cell);
            }

            transposed.push(new_row);
        }

        // Calculate column widths for transposed table
        let num_cols = 1 + num_data_rows; // header col + data cols
        let mut col_widths = vec![0; num_cols];

        for row in &transposed {
            for (i, cell) in row.iter().enumerate() {
                col_widths[i] = col_widths[i].max(cell.chars().count());
            }
        }

        // Distribute extra space if available
        let separators_width = num_cols + 1;
        let content_width: usize = col_widths.iter().sum();
        let total_needed = content_width + separators_width;

        if total_needed < FONT_B_WIDTH {
            let extra = FONT_B_WIDTH - total_needed;
            let per_col = extra / num_cols;
            let remainder = extra % num_cols;

            for (i, width) in col_widths.iter_mut().enumerate() {
                *width += per_col;
                if i < remainder {
                    *width += 1;
                }
            }
        }

        // Format the transposed table
        let mut output = Vec::new();
        let separator = self.create_separator(&col_widths);

        output.push(separator.clone());
        for row in &transposed {
            output.push(self.format_row(row, &col_widths));
        }
        output.push(separator);

        output
    }

    fn format_chunked(&self) -> Vec<String> {
        if self.rows.is_empty() {
            return Vec::new();
        }

        let num_cols = self.rows.iter().map(|r| r.len()).max().unwrap_or(0);
        if num_cols == 0 {
            return Vec::new();
        }

        // Calculate column widths
        let mut col_widths = vec![0; num_cols];
        for row in &self.rows {
            for (i, cell) in row.iter().enumerate() {
                col_widths[i] = col_widths[i].max(cell.chars().count());
            }
        }

        // Strategy: Split into chunks, always include first column (key/index) in each chunk
        let first_col_width = col_widths[0];
        let mut chunks = Vec::new();
        let mut current_chunk = vec![0]; // Always start with column 0
        let mut current_width = first_col_width + 2; // +2 for separators

        for col_idx in 1..num_cols {
            let col_width = col_widths[col_idx];
            let needed = col_width + 1; // +1 for separator

            if current_width + needed <= FONT_B_WIDTH {
                current_chunk.push(col_idx);
                current_width += needed;
            } else {
                // Start new chunk
                if current_chunk.len() > 1 {
                    chunks.push(current_chunk);
                }
                current_chunk = vec![0, col_idx]; // Always include first col
                current_width = first_col_width + col_width + 3; // +3 for separators
            }
        }

        // Add last chunk
        if current_chunk.len() > 1 {
            chunks.push(current_chunk);
        }

        // Format each chunk
        let mut output = Vec::new();

        for (chunk_idx, chunk_cols) in chunks.iter().enumerate() {
            if chunk_idx > 0 {
                output.push("".to_string()); // Blank line between chunks
            }

            // Get widths for this chunk
            let chunk_widths: Vec<usize> = chunk_cols.iter().map(|&idx| col_widths[idx]).collect();

            let separator = self.create_separator(&chunk_widths);
            output.push(separator.clone());

            for (row_idx, row) in self.rows.iter().enumerate() {
                let chunk_row: Vec<String> = chunk_cols
                    .iter()
                    .map(|&col_idx| row.get(col_idx).cloned().unwrap_or_default())
                    .collect();

                output.push(self.format_row(&chunk_row, &chunk_widths));

                // Add separator after header
                if row_idx + 1 == self.header_row_count {
                    output.push(separator.clone());
                }
            }

            output.push(separator.clone());
        }

        output
    }
}

#[derive(Debug)]
struct LineOutput {
    content: String,
    overflow: Option<String>,
}

impl LineOutput {
    fn simple(content: String) -> Self {
        Self {
            content,
            overflow: None,
        }
    }

    fn with_overflow(content: String, overflow: String) -> Self {
        Self {
            content,
            overflow: Some(overflow),
        }
    }
}

struct LineWrapper {
    base_width: usize,  // 42 for Font A, 56 for Font B
    width_scale: usize, // Width multiplier from .size(w, h)
    indent: String,
    mode: WrapMode,
    current_line: String,
    col: usize,
}

impl LineWrapper {
    fn new() -> Self {
        Self {
            base_width: LINE_WIDTH,
            width_scale: 1,
            indent: String::new(),
            mode: WrapMode::Reflow,
            current_line: String::new(),
            col: 0,
        }
    }

    fn effective_width(&self) -> usize {
        self.base_width / self.width_scale
    }

    fn set_scale(&mut self, width: usize, _height: usize) {
        self.width_scale = width;
    }

    fn set_font(&mut self, font: Font) {
        self.base_width = match font {
            Font::A => 42,
            Font::B => 56,
            _ => 42, // Default to Font A
        };
    }

    fn with_mode(mut self, mode: WrapMode) -> Self {
        self.mode = mode;
        self
    }

    fn with_indent(mut self, indent: &str) -> Self {
        self.indent = indent.to_string();
        self
    }

    fn set_indent(&mut self, indent: &str) {
        self.indent = indent.to_string();
    }

    fn set_mode(&mut self, mode: WrapMode) {
        self.mode = mode;
    }

    fn add_text(&mut self, text: &str) -> Vec<LineOutput> {
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

    fn flush(&mut self) -> Option<String> {
        if !self.current_line.is_empty() {
            let line = self.current_line.clone();
            self.current_line.clear();
            self.col = 0;
            Some(line)
        } else {
            None
        }
    }

    fn start_line_with(&mut self, prefix: &str) {
        self.current_line = prefix.to_string();
        self.col = prefix.chars().count();
    }
}

pub fn print_markdown<D>(printer: &mut Printer<D>, markdown: &str) -> escpos::errors::Result<()>
where
    D: escpos::driver::Driver,
{
    let mut options = Options::empty();
    options.insert(Options::ENABLE_TABLES);
    options.insert(Options::ENABLE_STRIKETHROUGH);
    let parser = MarkdownParser::new_ext(markdown, options);

    let mut wrapper = LineWrapper::new();
    let mut table_builder: Option<TableBuilder> = None;
    let mut in_table_cell = false;
    let mut list_depth: usize = 0;
    let mut image_url: Option<String> = None;
    let mut image_alt: String = String::new();

    for event in parser {
        match event {
            Event::Start(tag) => match tag {
                Tag::Heading { level, .. } => {
                    // Headers are bold and larger
                    printer.bold(true)?;
                    if level <= pulldown_cmark::HeadingLevel::H2 {
                        printer.size(2, 2)?;
                        wrapper.set_scale(2, 2);
                    }
                }
                Tag::Emphasis => {
                    // Italic -> use underline since italic often not supported
                    printer.underline(UnderlineMode::Single)?;
                }
                Tag::Strong => {
                    printer.bold(true)?;
                }
                Tag::List(_) => {
                    list_depth += 1;
                }
                Tag::Item => {
                    // Flush any pending text
                    if let Some(line) = wrapper.flush() {
                        printer.writeln(&line)?;
                    }
                    // Calculate indent based on nesting level
                    let prefix_spaces = (list_depth - 1) * 2 + 2;
                    let wrap_indent_spaces = (list_depth - 1) * 2 + 4;

                    let prefix = format!("{}- ", " ".repeat(prefix_spaces));
                    let wrap_indent = " ".repeat(wrap_indent_spaces);

                    wrapper.start_line_with(&prefix);
                    wrapper.set_indent(&wrap_indent);
                }
                Tag::Paragraph => {
                    wrapper.set_indent("");
                }
                Tag::CodeBlock(_) => {
                    if let Some(line) = wrapper.flush() {
                        printer.writeln(&line)?;
                    }
                    printer.font(Font::B)?;
                    wrapper.set_font(Font::B);
                    wrapper.set_mode(WrapMode::PreserveLines {
                        overflow_indicator: "...".to_string(),
                    });
                }
                Tag::Table(_) => {
                    if let Some(line) = wrapper.flush() {
                        printer.writeln(&line)?;
                    }
                    table_builder = Some(TableBuilder::new());
                    printer.font(Font::B)?;
                }
                Tag::TableHead => {
                    if let Some(ref mut builder) = table_builder {
                        builder.in_header = true;
                    }
                }
                Tag::TableRow => {}
                Tag::TableCell => {
                    in_table_cell = true;
                }
                Tag::Image { dest_url, .. } => {
                    // Flush any pending text
                    if let Some(line) = wrapper.flush() {
                        printer.writeln(&line)?;
                    }
                    // Store image URL and reset alt text
                    image_url = Some(dest_url.to_string());
                    image_alt.clear();
                }
                _ => {}
            },

            Event::End(tag_end) => match tag_end {
                TagEnd::Heading(_) => {
                    if let Some(line) = wrapper.flush() {
                        printer.writeln(&line)?;
                    }
                    printer.bold(false)?;
                    printer.size(1, 1)?;
                    wrapper.set_scale(1, 1);
                }
                TagEnd::Emphasis => {
                    printer.underline(UnderlineMode::None)?;
                }
                TagEnd::Strong => {
                    printer.bold(false)?;
                }
                TagEnd::Paragraph => {
                    if let Some(line) = wrapper.flush() {
                        printer.writeln(&line)?;
                    }
                    printer.writeln("")?;
                }
                TagEnd::Item => {
                    if let Some(line) = wrapper.flush() {
                        printer.writeln(&line)?;
                    }
                    wrapper.set_indent("");
                }
                TagEnd::List(_) => {
                    list_depth = list_depth.saturating_sub(1);
                    if list_depth == 0 {
                        printer.feed()?;
                    }
                }
                TagEnd::CodeBlock => {
                    printer.font(Font::A)?;
                    printer.writeln("")?;
                    wrapper.set_font(Font::A);
                    wrapper.set_mode(WrapMode::Reflow);
                }
                TagEnd::Table => {
                    if let Some(builder) = table_builder.take() {
                        let formatted = builder.format_table();
                        for line in formatted {
                            printer.writeln(&line)?;
                        }
                        printer.writeln("")?;
                    }
                    printer.font(Font::A)?;
                }
                TagEnd::TableHead => {
                    if let Some(ref mut builder) = table_builder {
                        builder.end_row(); // Finalize the header row!
                        builder.in_header = false;
                    }
                }
                TagEnd::TableRow => {
                    if let Some(ref mut builder) = table_builder {
                        builder.end_row();
                    }
                }
                TagEnd::TableCell => {
                    if let Some(ref mut builder) = table_builder {
                        builder.end_cell();
                    }
                    in_table_cell = false;
                }
                TagEnd::Image => {
                    if let Some(url) = image_url.take() {
                        // Parse optional width from alt text (e.g., "width:128")
                        let width = if image_alt.starts_with("width:") {
                            image_alt
                                .strip_prefix("width:")
                                .and_then(|s| s.parse::<u32>().ok())
                        } else {
                            None
                        };

                        // Default width: 384 pixels (typical receipt printer width)
                        let image_width = width.unwrap_or(384);

                        // Print the image
                        if let Err(e) = printer.bit_image_option(
                            &url,
                            BitImageOption::new(Some(image_width), None, BitImageSize::Normal)?,
                        ) {
                            eprintln!("Failed to print image '{}': {}", url, e);
                        }
                        printer.feed()?;
                    }
                    image_alt.clear();
                }
                _ => {}
            },

            Event::Text(text) => {
                if in_table_cell {
                    if let Some(ref mut builder) = table_builder {
                        builder.add_text(&text);
                    }
                } else if image_url.is_some() {
                    // Capture alt text for image
                    image_alt.push_str(&text);
                } else {
                    let line_outputs = wrapper.add_text(&text);
                    for output in line_outputs {
                        printer.writeln(&output.content)?;
                        if let Some(overflow) = output.overflow {
                            printer.justify(JustifyMode::RIGHT)?;
                            printer.writeln(&overflow)?;
                            printer.justify(JustifyMode::LEFT)?;
                        }
                    }
                }
            }

            Event::Code(code) => {
                if in_table_cell {
                    if let Some(ref mut builder) = table_builder {
                        builder.add_text(&code);
                    }
                } else {
                    // Inline code - just add as text, font changes handled by tags
                    let line_outputs = wrapper.add_text(&code);
                    for output in line_outputs {
                        printer.writeln(&output.content)?;
                        if let Some(overflow) = output.overflow {
                            printer.justify(JustifyMode::RIGHT)?;
                            printer.writeln(&overflow)?;
                            printer.justify(JustifyMode::LEFT)?;
                        }
                    }
                }
            }

            Event::SoftBreak => {
                // Soft breaks are handled by word wrapping
            }

            Event::HardBreak => {
                if let Some(line) = wrapper.flush() {
                    printer.writeln(&line)?;
                }
                printer.writeln("")?;
            }

            Event::Rule => {
                if let Some(line) = wrapper.flush() {
                    printer.writeln(&line)?;
                }
                let rule = "-".repeat(wrapper.effective_width());
                printer.writeln(&rule)?;
            }

            _ => {}
        }
    }

    // Flush any remaining text
    if let Some(line) = wrapper.flush() {
        printer.writeln(&line)?;
    }

    Ok(())
}
