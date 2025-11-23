pub const FONT_B_WIDTH: usize = 56;

pub struct TableBuilder {
    rows: Vec<Vec<String>>,
    current_row: Vec<String>,
    current_cell: String,
    pub in_header: bool,
    pub header_row_count: usize,
}

impl TableBuilder {
    pub fn new() -> Self {
        Self {
            rows: Vec::new(),
            current_row: Vec::new(),
            current_cell: String::new(),
            in_header: false,
            header_row_count: 0,
        }
    }

    pub fn add_text(&mut self, text: &str) {
        self.current_cell.push_str(text);
    }

    pub fn end_cell(&mut self) {
        self.current_row.push(self.current_cell.clone());
        self.current_cell.clear();
    }

    pub fn end_row(&mut self) {
        if !self.current_row.is_empty() {
            self.rows.push(self.current_row.clone());
            self.current_row.clear();
            if self.in_header {
                self.header_row_count += 1;
            }
        }
    }

    pub fn format_table(&self) -> Vec<String> {
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
