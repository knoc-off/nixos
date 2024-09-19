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

#[function_component(Resume)]
pub fn resume() -> Html {
    let resume_data = create_resume_data();

    // Create a callback for the print button
    let print_resume = Callback::from(|_| {
        print();
    });

    html! {
        <div>
            <button class="print-button no-print" onclick={print_resume}>{"Print Resume"}</button>
            <div class="resume a4-paper">
                // Add the print button
                <div class="grid">
                    <Header
                        name={resume_data.name.clone()}
                        title={resume_data.title.clone()}
                        contact_info={resume_data.contact.clone()}
                    />

                    <div class="photo">
                        <img src={resume_data.photo_path.clone()} alt="Profile Photo" />
                    </div>

                    <div class="main">
                        <h2>{"Experience"}</h2>
                        <ExperienceSection experiences={resume_data.experience.clone()} />
                        <h2>{"Education"}</h2>
                        <EducationSection education={resume_data.education.clone()} />
                        <h2>{"Project Highlight"}</h2>
                        <ProjectsSection projects={resume_data.projects.clone()} />
                    </div>

                    <div class="sidebar">
                        <h2>{"Languages"}</h2>
                        <LanguagesSection languages={resume_data.languages.clone()} />

                        <h2>{"Software"}</h2>
                        <ItemizedList items={resume_data.software.clone()} />
                        <section>
                            <h2>{"Interests"}</h2>
                            <p>{resume_data.interests}</p>
                        </section>
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
            middle: Some("".to_string()),
        },
        title: "Server Admin, Programmer".to_string(),
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
        summary: "Junior software developer with experience in server configuration, web development, and system security. Proficient in Rust, Nix, and various web technologies. Skilled in Docker, CI/CD, and Linux systems. Demonstrated ability to set up and maintain internal services. Fluent in English and German.".to_string(),
        photo_path: "static/Niko.jpeg".to_string(),
        experience: vec![
            Experience {
                company: "Olymp Consulting".to_string(),
                position: "Junior Software Developer".to_string(),
                location: "Berlin".to_string(),
                date_range: "10/2022 - 06/2023".to_string(),
                responsibilities: vec![
                    "Configured and managed servers using NixOS.".to_string(),
                    "Establish internal services, such as Autheliea.".to_string(),
                    //"Proposed workflow changes and implemented them.".to_string(),
                    "implemented my proposed workflow changes".to_string(),
                ],
            },
            //Experience {
            //    company: "Motive School of Movement".to_string(),
            //    position: "Gymnastics Coach".to_string(),
            //    location: "South Carolina".to_string(),
            //    date_range: "03/2020 - 05/2021".to_string(),
            //    responsibilities: vec![
            //    ],
            //},
        ],
        software: vec![
            "Linux".to_string(),
            "NixOS".to_string(),
            "Docker".to_string(),
            "Podman".to_string(),
            "CI/CD".to_string(),
            "Rust".to_string(),
            "UI/UX".to_string(),
            "HTML/CSS".to_string(),
            "JavaScript".to_string(),
            "Java".to_string(),
            "Bash".to_string(),
            "Json".to_string(),
            "Python".to_string(),
            "Git".to_string(),
        ],
        education: vec![
            Education {
                institution: "T.U. Berlin".to_string(),
                location: "Berlin".to_string(),
                degree: "Gasthörerschaft".to_string(),
                date: "Wintersemester 2023".to_string(),
                details: vec![
                ],
            },
            Education {
                institution: "Wade Hampton High School".to_string(),
                location: "South Carolina".to_string(),
                degree: "High School Diploma".to_string(),
                date: "08/2021".to_string(),
                details: vec![
                    //"Relevant Coursework: Computer Science using Java, AP Computer Science".to_string(),
                    //"Extracurricular Activities: German Club".to_string(),
                ],
            },
            Education {
                institution: "Fine Arts Center".to_string(),
                location: "South Carolina".to_string(),
                degree: "Graduation Certificate".to_string(),
                date: "06/2021".to_string(),
                details: vec![],
            },
        ],
        languages: vec![
            Language {
                name: "English".to_string(),
                level: "Native".to_string(),
                icon: "static/icons/flags/us.svg".to_string(),
            },
            Language {
                name: "German".to_string(),
                level: "Fluent".to_string(),
                icon: "static/icons/flags/de.svg".to_string(),
            },
        ],
        interests: "I enjoy hosting board game nights
and cooking for friends and family. I
also tinker with Arduinos, 3D
printing, and game development!".to_string(),

        projects: vec![
            Project {
                icon_path: String::from("static/icons/tiny/nixos.svg"),
                name: String::from("Nix Configurations"),
                url: String::from("https://github.com/knoc-off/nixos"),
                description: String::from(""),
                bullets: vec![
                    "Configures multiple systems via a single, version-controlled repository.".to_string(),
                    "Set up OCI containers for services like WordPress".to_string(),
                    //"Utilizes Disko for declarative disk partitioning".to_string(),
                    "Manages secrets using sops-nix for encrypted configuration".to_string(),
                ],
                languages: vec![
                    LanguageUsage { language: String::from("Nix"),     color: String::from("#7e7eff"), percentage: 77.0 },
                    LanguageUsage { language: String::from("Rust"),    color: String::from("#dea584"), percentage: 10.0 },
                    LanguageUsage { language: String::from("Sass"),    color: String::from("#a53b70"), percentage: 5.0 },
                    LanguageUsage { language: String::from("Shell"),   color: String::from("#89e051"), percentage: 2.0 },
                    LanguageUsage { language: String::from("YAML"),    color: String::from("#cb171e"), percentage: 2.00 },
                    LanguageUsage { language: String::from("other"),   color: String::from("#aaaaaa"), percentage: 4.00 },
                ],
            },
            Project {
                icon_path: String::from("static/icons/tiny/webassembly.svg"),
                name: String::from("Yew Website"),
                url: String::from("https://github.com/knoc-off/nixos/tree/main/pkgs/portfolio"),
                description: String::from(""),
                bullets: vec![
                    "Uses Yew for WebAssembly and front-end development.".to_string(),
                    "built around reusable components, bundling logic and presentation".to_string(),
                    "Utilizes Trunk for Rust and WebAssembly build/bundling.".to_string(),
                ],
                languages: vec![
                    LanguageUsage { language: String::from("Rust"),    color: String::from("#dea584"), percentage: 60.0 },
                    LanguageUsage { language: String::from("Scss"),    color: String::from("#a53b70"), percentage: 34.0 },
                    LanguageUsage { language: String::from("Nix"),     color: String::from("#7e7eff"), percentage: 3.00 },
                    LanguageUsage { language: String::from("TOML"),    color: String::from("#9c4221"), percentage: 2.00 },
                    LanguageUsage { language: String::from("HTML"),    color: String::from("#e34c26"), percentage: 1.00 },
                ],
            },
        ],
    }
}
