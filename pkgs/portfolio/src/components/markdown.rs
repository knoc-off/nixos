use yew::prelude::*;
use pulldown_cmark::{Parser, html::push_html};

#[derive(Properties, PartialEq)]
pub struct MarkdownViewerProps {
    pub markdown: String,
}

#[function_component(MarkdownViewer)]
pub fn markdown_viewer(props: &MarkdownViewerProps) -> Html {
    // Convert Markdown to HTML
    let parser = Parser::new(&props.markdown);
    let mut html_output = String::new();
    push_html(&mut html_output, parser);

    // Safely create an Html instance from the string (beware of untrusted content)
    let html_content = Html::from_html_unchecked(html_output.into());

    html! {
        <div class="markdown-content">
            {html_content}
        </div>
    }
}

