mod contact_info;
mod education;
mod experience;
mod header;
mod languages;
mod projects;
mod itemized_list;

pub use contact_info::*;
pub use education::*;
pub use experience::*;
pub use header::*;
pub use languages::*;
pub use projects::*;
pub use itemized_list::*;

use crate::data::name::Name;

#[derive(Clone, PartialEq)]
pub struct ResumeData {
    pub name: Name,
    pub title: String,
    pub contact: ContactInfo,
    pub summary: String,
    pub photo_path: String,
    pub experience: Vec<Experience>,
    pub software: Vec<String>,
    pub education: Vec<Education>,
    pub languages: Vec<Language>,
    pub interests: String,
    pub projects: Vec<Project>,
}
