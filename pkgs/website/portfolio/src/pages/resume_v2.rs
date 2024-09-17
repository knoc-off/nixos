use crate::components::resume::*;
use wasm_bindgen::prelude::*;
use yew::prelude::*;

use crate::data::name::Name;
use crate::data::link::*;
//use crate::components::link_item::ImageLinkItem;

// Add this function to call window.print()
#[wasm_bindgen]
extern "C" {
    #[wasm_bindgen(js_namespace = window)]
    fn print();
}

#[function_component(ResumeV2)]
pub fn resume() -> Html {
    let resume_data = create_resume_data();

    let print_resume = Callback::from(|_| {
        print();
    });

    html! {
        <div>
            <button class="print-button no-print" onclick={print_resume}>{"Print Resume"}</button>
            <div class="resumeV2">
                <div class="grid">
                    <div class="sidebar">
                        <img src={resume_data.photo_path.clone()} alt="Profile Photo" class="profile-photo" />
                        <div class="name-title">
                            <h1>{&resume_data.name.first} {&resume_data.name.last}</h1>
                            <h2>{&resume_data.title}</h2>
                        </div>
                        <div class="address">
                            <p>{&resume_data.name.first} {&resume_data.name.last}</p>
                            <p>{&resume_data.contact.location}</p>
                        </div>
                        <div class="contact">
                            <p>{&resume_data.contact.email}</p>
                            <p>{&resume_data.contact.phone}</p>
                        </div>
                        <div class="divider"></div>
                        <LanguagesSection languages={resume_data.languages.clone()} />
                        <SkillsSection skills={resume_data.skills.clone()} />
                    </div>

                    <div class="main">
                        <EducationSection education={resume_data.education.clone()} />
                        <ExperienceSection experiences={resume_data.experience.clone()} />
                        <ProjectsSection projects={resume_data.projects.clone()} />
                    </div>
                </div>
            </div>
        </div>
    }
}

pub fn create_resume_data() -> ResumeData {
    ResumeData {
        name: Name {
            first: "Nicholas".to_string(),
            last: "Selby".to_string(),
            middle: None,
        },
        title: "Server Admin,\nProgrammer".to_string(),
        contact: ContactInfo {
            email: "selby@niko.ink".to_string(),
            phone: "+49 176 56615691".to_string(),
            location: "Stolzingstraße 7\n13465 Berlin, DE".to_string(),
            social_links: vec![],
        },
        summary: "".to_string(), // No summary in the PDF
        photo_path: "static/Niko.jpeg".to_string(),
        experience: vec![
            Experience {
                company: "OLYMP Consulting".to_string(),
                position: "Junior Software Developer".to_string(),
                location: "Berlin".to_string(),
                date_range: "2022-2023 | 1 year".to_string(),
                responsibilities: vec![
                    "Server configuration/management with NixOS,".to_string(),
                    "establishing internal service Autheliea, workflow".to_string(),
                    "changes".to_string(),
                ],
            },
        ],
        skills: vec![
            "Linux".to_string(), "NixOS".to_string(), "Docker".to_string(),
            "Podman".to_string(), "CI/CD".to_string(), "Rust".to_string(),
            "UI/UX".to_string(), "HTML/CSS".to_string(), "Javascript".to_string(),
            "Java".to_string(), "Bash".to_string(), "Json".to_string(),
            "Python".to_string(), "Git".to_string(),
        ],
        education: vec![
            Education {
                institution: "TU Berlin".to_string(),
                location: "DE".to_string(),
                degree: "Gasthörer/Class auditing".to_string(),
                date: "2023".to_string(),
                details: vec!["Intro to programming".to_string()],
            },
            Education {
                institution: "Wade Hampton High School".to_string(),
                location: "USA".to_string(),
                degree: "High School Diploma".to_string(),
                date: "2017-2021".to_string(),
                details: vec![],
            },
            Education {
                institution: "The Fine Arts Center".to_string(),
                location: "USA".to_string(),
                degree: "Parallel visual art high school".to_string(),
                date: "2017-2021".to_string(),
                details: vec![],
            },
        ],
        languages: vec![
            Language {
                name: "English".to_string(),
                level: "Native".to_string(),
                icon: "".to_string(),
            },
            Language {
                name: "German".to_string(),
                level: "Fluent".to_string(),
                icon: "".to_string(),
            },
        ],
        interests: vec![],
        projects: vec![
            Project {
                icon_path: "".to_string(),
                name: "Nix Configurations".to_string(),
                url: "".to_string(),
                description: "".to_string(),
                bullets: vec![
                    "Configures multiple systems via a single, version-controlled repository".to_string(),
                    "OCI containers for services (WP)".to_string(),
                    "Manages secrets using sops-nix for encrypted configuration".to_string(),
                ],
                languages: vec![],
            },
            Project {
                icon_path: "".to_string(),
                name: "Yew Website".to_string(),
                url: "".to_string(),
                description: "".to_string(),
                bullets: vec![
                    "Configures multiple systems via a single, version-controlled repository".to_string(),
                    "OCI containers for services (WP)".to_string(),
                    "Manages secrets using sops-nix for encrypted configuration".to_string(),
                ],
                languages: vec![],
            },
        ],
    }
}
