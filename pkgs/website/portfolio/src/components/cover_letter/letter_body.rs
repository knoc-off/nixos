use crate::pages::cover_letter::CoverLetterProps;
use yew::prelude::*;

#[derive(Properties, PartialEq)]
pub struct LetterBodyProps {
    pub greeting: String,
    pub paragraphs: Vec<String>,
    pub closing: String,
}
//greeting={data.greeting.clone()}
//paragraphs={data.body_paragraphs.clone()}
//closing={format!("{} {}", data.closing.clone(), data.name.first.clone())}

#[function_component(LetterBody)]
pub fn letter_body(props: &CoverLetterProps) -> Html {
    html! {
        <div class="letter-body">
            <p class="greeting">{&props.data.greeting}</p>
            { for props.data.body_paragraphs.iter().map(|paragraph| html! {
                <p>{paragraph
                    .replace("{company_name}", &props.data.recipient.company)
                    .replace("{recipient_name}", &props.data.recipient.name.first)
                    .replace("{job_title}", &props.data.job.title)
                    .replace("{phone}", &props.data.contact.phone)
                    .replace("{email}", &props.data.contact.email)
                }</p>
            })}
            <div class="ending">
                <p class="closing">{&props.data.closing}</p>
                <p class="signature">{format!("{} {}", &props.data.name.first, &props.data.name.last )}</p>
            </div>
        </div>
    }
}
