use yew::prelude::*;

use crate::components::cover_letter::{CoverLetterData, LetterBody, Recipient, RecipientComponent};
use crate::components::resume::ContactInfo;

use crate::components::resume::Header;

use crate::data::name::Name;
use crate::data::job::Job;

use crate::data::link::*;

#[derive(Properties, PartialEq)]
pub struct CoverLetterProps {
    pub data: CoverLetterData,
}

#[function_component(CoverLetterPage)]
pub fn cover_letter_page() -> Html {
    let data = create_cover_letter_data();

    html! {
        <div class="cover-letter-page">
            <Header
                name={data.name.clone()}
                contact_info={data.contact.clone()}
                title={data.job.title.to_uppercase().to_string()}
            />
            <RecipientComponent
                name={data.recipient.name.clone()}
                company={data.recipient.company.clone()}
                address={data.recipient.address.clone()}
            />
            <LetterBody // this should accept all coverLetterData, and then pick out parts.
                data={data.clone()}
                //greeting={data.greeting.clone()}
                //paragraphs={data.body_paragraphs.clone()}
                //closing={format!("{} {}", data.closing.clone(), data.name.first.clone())}
            />
        </div>
    }
}

fn create_cover_letter_data() -> CoverLetterData {
    CoverLetterData {
        name: Name {
            first: "Nicholas".to_string(),
            last: "Selby".to_string(),
            middle: Some("".to_string()),
        },

        job: Job {
            title: "Server Admin".to_string(),
        },

        contact: ContactInfo {
            email: "selby@niko.ink".to_string(),
            phone: "+49 176 56615691".to_string(),
            location: "Berlin 13465".to_string(),
            social_links: vec![
                ImageLinkData {
                    data: LinkData {
                        link: "https://www.linkedin.com/in/niko-selby/".to_string(),
                        alt_text: "LinkedIn".to_string(),
                    },
                    img_src: "/static/icons/tiny/linkedin.svg".to_string(),
                },
                ImageLinkData {
                    data: LinkData {
                        link: "https://github.com/knoc-off".to_string(),
                        alt_text: "GitHub".to_string(),
                    },
                    img_src: "/static/icons/tiny/github.svg".to_string(),
                },
            ],
        },
        recipient: Recipient {
            name: Name {
                first: "John".to_string(),
                last: "Doe".to_string(),
                middle: Some("".to_string()),
            },
            company: "xyz company".to_string(),
            address: "xyz address".to_string(),
        },
        greeting: "".to_string(),
        body_paragraphs: vec![
        ], //TODO: change this.
        closing: "Sincerely, ".to_string(),
    }
}
