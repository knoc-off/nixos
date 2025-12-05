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
    let options = Options::ENABLE_TABLES | Options::ENABLE_STRIKETHROUGH;
    let parser = MarkdownParser::new_ext(markdown, options);

    let mut wrapper = LineWrapper::new();
    let mut table_builder: Option<TableBuilder> = None;
    let mut list_depth: usize = 0;
    let mut image_state: Option<(String, String)> = None; // (url, alt_text)

    for event in parser {
        match event {
            // Heading
            Event::Start(Tag::Heading { level, .. }) => {
                printer.bold(true)?;
                if level <= pulldown_cmark::HeadingLevel::H2 {
                    printer.size(2, 2)?;
                    wrapper.set_scale(2, 2);
                }
            }
            Event::End(TagEnd::Heading(_)) => {
                if let Some(line) = wrapper.flush() {
                    printer.writeln(&line)?;
                }
                printer.bold(false)?;
                printer.size(1, 1)?;
                wrapper.set_scale(1, 1);
            }

            // Emphasis
            Event::Start(Tag::Emphasis) => {
                printer.underline(UnderlineMode::Single)?;
            }
            Event::End(TagEnd::Emphasis) => {
                printer.underline(UnderlineMode::None)?;
            }

            // Strong
            Event::Start(Tag::Strong) => {
                printer.bold(true)?;
            }
            Event::End(TagEnd::Strong) => {
                printer.bold(false)?;
            }

            // List
            Event::Start(Tag::List(_)) => {
                list_depth += 1;
            }
            Event::End(TagEnd::List(_)) => {
                list_depth = list_depth.saturating_sub(1);
                if list_depth == 0 {
                    printer.feed()?;
                }
            }

            // Item
            Event::Start(Tag::Item) => {
                if let Some(line) = wrapper.flush() {
                    printer.writeln(&line)?;
                }
                let prefix_spaces = (list_depth - 1) * 2 + 2;
                let wrap_indent_spaces = (list_depth - 1) * 2 + 4;
                wrapper.start_line_with(&format!("{}- ", " ".repeat(prefix_spaces)));
                wrapper.set_indent(&" ".repeat(wrap_indent_spaces));
            }
            Event::End(TagEnd::Item) => {
                if let Some(line) = wrapper.flush() {
                    printer.writeln(&line)?;
                }
                wrapper.set_indent("");
            }

            // Paragraph
            Event::Start(Tag::Paragraph) => {
                wrapper.set_indent("");
            }
            Event::End(TagEnd::Paragraph) => {
                if let Some(line) = wrapper.flush() {
                    printer.writeln(&line)?;
                }
                printer.writeln("")?;
            }

            // CodeBlock
            Event::Start(Tag::CodeBlock(_)) => {
                if let Some(line) = wrapper.flush() {
                    printer.writeln(&line)?;
                }
                printer.font(Font::B)?;
                wrapper.set_font(Font::B);
                wrapper.set_mode(WrapMode::PreserveLines {
                    overflow_indicator: "...".to_string(),
                });
            }
            Event::End(TagEnd::CodeBlock) => {
                printer.font(Font::A)?;
                printer.writeln("")?;
                wrapper.set_font(Font::A);
                wrapper.set_mode(WrapMode::Reflow);
            }

            // Table
            Event::Start(Tag::Table(_)) => {
                if let Some(line) = wrapper.flush() {
                    printer.writeln(&line)?;
                }
                table_builder = Some(TableBuilder::new());
                printer.font(Font::B)?;
            }
            Event::End(TagEnd::Table) => {
                if let Some(builder) = table_builder.take() {
                    for line in builder.format_table() {
                        printer.writeln(&line)?;
                    }
                    printer.writeln("")?;
                }
                printer.font(Font::A)?;
            }

            // TableHead
            Event::Start(Tag::TableHead) => {
                if let Some(ref mut builder) = table_builder {
                    builder.in_header = true;
                }
            }
            Event::End(TagEnd::TableHead) => {
                if let Some(ref mut builder) = table_builder {
                    builder.end_row();
                    builder.in_header = false;
                }
            }

            // TableRow
            Event::Start(Tag::TableRow) => {}
            Event::End(TagEnd::TableRow) => {
                if let Some(ref mut builder) = table_builder {
                    builder.end_row();
                }
            }

            // TableCell
            Event::Start(Tag::TableCell) => {}
            Event::End(TagEnd::TableCell) => {
                if let Some(ref mut builder) = table_builder {
                    builder.end_cell();
                }
            }

            // Image
            Event::Start(Tag::Image { dest_url, .. }) => {
                if let Some(line) = wrapper.flush() {
                    printer.writeln(&line)?;
                }
                image_state = Some((dest_url.to_string(), String::new()));
            }
            Event::End(TagEnd::Image) => {
                if let Some((url, alt_text)) = image_state.take() {
                    let width = alt_text
                        .strip_prefix("width:")
                        .and_then(|s| s.parse().ok())
                        .unwrap_or(384);

                    if let Err(e) = printer.bit_image_option(
                        &url,
                        BitImageOption::new(Some(width), None, BitImageSize::Normal)?,
                    ) {
                        eprintln!("Failed to print image '{}': {}", url, e);
                    }
                    printer.feed()?;
                }
            }

            // Text and Code (combined - same handling)
            Event::Text(text) | Event::Code(text) => {
                if let Some(ref mut builder) = table_builder {
                    builder.add_text(&text);
                } else if let Some((_, ref mut alt_text)) = image_state {
                    alt_text.push_str(&text);
                } else {
                    for output in wrapper.add_text(&text) {
                        printer.writeln(&output.content)?;
                        if let Some(overflow) = output.overflow {
                            printer.justify(JustifyMode::RIGHT)?;
                            printer.writeln(&overflow)?;
                            printer.justify(JustifyMode::LEFT)?;
                        }
                    }
                }
            }

            // HardBreak
            Event::HardBreak => {
                if let Some(line) = wrapper.flush() {
                    printer.writeln(&line)?;
                }
                printer.writeln("")?;
            }

            // Rule
            Event::Rule => {
                if let Some(line) = wrapper.flush() {
                    printer.writeln(&line)?;
                }
                printer.writeln(&"-".repeat(wrapper.effective_width()))?;
            }

            // SoftBreak and others
            _ => {}
        }
    }

    if let Some(line) = wrapper.flush() {
        printer.writeln(&line)?;
    }
    Ok(())
}
