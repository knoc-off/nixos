mod recipient;
mod letter_body;

pub use recipient::*;
pub use letter_body::*;

use crate::components::resume::ContactInfo; // resuse the contact info component from resume
use crate::data::name::Name;
use crate::data::job::Job;

#[derive(PartialEq, Clone)]
pub struct CoverLetterData {
    pub name: Name,
    pub job: Job,
    pub contact: ContactInfo,
    pub recipient: Recipient,
    pub greeting: String,
    pub body_paragraphs: Vec<String>,
    pub closing: String,
}

