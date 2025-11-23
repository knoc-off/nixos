mod table;
mod wrapper;

use escpos::printer::Printer;
use escpos::utils::*;
use pulldown_cmark::{Event, Options, Parser as MarkdownParser, Tag, TagEnd};

use table::TableBuilder;
use wrapper::{LineWrapper, WrapMode};

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
                    printer.bold(true)?;
                    if level <= pulldown_cmark::HeadingLevel::H2 {
                        printer.size(2, 2)?;
                        wrapper.set_scale(2, 2);
                    }
                }
                Tag::Emphasis => {
                    printer.underline(UnderlineMode::Single)?;
                }
                Tag::Strong => {
                    printer.bold(true)?;
                }
                Tag::List(_) => {
                    list_depth += 1;
                }
                Tag::Item => {
                    if let Some(line) = wrapper.flush() {
                        printer.writeln(&line)?;
                    }
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
