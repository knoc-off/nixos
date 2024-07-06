use yew::prelude::*;
use crate::components::resume::*;
use crate::components::social_links::LogoLinkProps;



#[function_component(Resume)]
pub fn resume() -> Html {
    let resume_data = create_resume_data();
    html! {
        <div class="resume">
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
                    <ExperienceSection experiences={resume_data.experience.clone()} />
                    <EducationSection education={resume_data.education.clone()} />
                    <SkillsSection skills={resume_data.skills.clone()} />
                </div>

                <div class="sidebar">
                    <LanguagesSection languages={resume_data.languages.clone()} />
                    <ProjectsSection projects={resume_data.projects.clone()} />
                    <section>
                        <h2>{"INTERESTS"}</h2>
                        <p>{ &resume_data.interests }</p>
                    </section>
                </div>
            </div>
        </div>
    }
}


pub fn create_resume_data() -> ResumeData {
    ResumeData {
        name: "NICHOLAS SELBY".to_string(),
        title: "SOFTWARE DEVELOPER".to_string(),
        contact: ContactInfo {
            email: "selby@niko.ink".to_string(),
            phone: "+49 176 56615691".to_string(),
            location: "Berlin 13465".to_string(),
            social_links: vec![

                LogoLinkProps {
                    link: "https://www.linkedin.com/in/niko-selby/".to_string(),
                    img_src: "/static/icons/tiny/linkedin.svg".to_string(),
                    alt_text: "LinkedIn".to_string(),
                    width: Some("30px".to_string()),
                    height: Some("30px".to_string()),
                    additional_style: None,
                },
                LogoLinkProps {
                    link: "https://github.com/knoc-off".to_string(),
                    img_src: "/static/icons/tiny/github.svg".to_string(),
                    alt_text: "GitHub".to_string(),
                    width: Some("30px".to_string()),
                    height: Some("30px".to_string()),
                    additional_style: None,
                },



            ],
        },
        summary: "Versatile Junior Software Developer with a track record of resolving technical issues and enhancing collaboration at Olymp Consulting. Demonstrated expertise in Python Programming. Achieved significant improvements in development processes through innovative technology integration. Skilled in both back-end development and fostering productive relationships. Seeking to utilize excellent communication, interpersonal, and organizational skills to complete tasks. Reliable with a good work ethic and the ability to quickly adapt to new tasks and environments.".to_string(),
        photo_path: "static/Niko.jpeg".to_string(),
        experience: vec![
            Experience {
                company: "Olymp Consulting".to_string(),
                position: "Junior Software Developer".to_string(),
                location: "Berlin".to_string(),
                date_range: "10/2022 - 06/2023".to_string(),
                responsibilities: vec![
                    "Configured servers using nixos.".to_string(),
                    "Setup internal services, nextcloud filesharing.".to_string(),
                    "Configured security protocols with Authelia".to_string(),
                ],
            },
            Experience {
                company: "Motive School of Movement".to_string(),
                position: "Gymnastics Coach".to_string(),
                location: "South Carolina".to_string(),
                date_range: "03/2020 - 05/2021".to_string(),
                responsibilities: vec![
                ],
            },
        ],
        skills: vec![
            "Software Documentation".to_string(),
            "Version control".to_string(),
            "Web development".to_string(),
            "UI and UX design".to_string(),
            "CI/CD".to_string(),
            "Docker containers".to_string(),
            "Linux operating systems".to_string(),
            "HTML and CSS".to_string(),
            "Cloud computing".to_string(),
            "Back-end development".to_string(),
            "Data structures".to_string(),
            "Nix Configurations".to_string(),
        ],
        education: vec![
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
            Education {
                institution: "T.U. Berlin".to_string(),
                location: "Berlin".to_string(),
                degree: "Gasthörerschaft".to_string(),
                date: "wintersemester 2023".to_string(),
                details: vec![
                    "Relevant Coursework: IT Fundamentals".to_string(),
                ],
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
        interests: "3D printing, Arduino, game development, sketching, board games, cooking.".to_string(),
        projects: vec![
            Project {
                icon_path: String::from("static/icons/tiny/nixos.svg"),
                name: String::from("Nix Configurations"),
                url: String::from("https://github.com/knoc-off/nixos"),
                description: String::from("My nixos files. My operating system and many programs ive developed/packaged"),
                languages: vec![
                    LanguageUsage { language: String::from("Nix"),     color: String::from("#7e7eff"), percentage: 77.43 },
                    LanguageUsage { language: String::from("Rust"),    color: String::from("#dea584"), percentage: 10.80 },
                    LanguageUsage { language: String::from("Sass"),    color: String::from("#a53b70"), percentage: 5.51 },
                    LanguageUsage { language: String::from("Shell"),   color: String::from("#89e051"), percentage: 2.08 },
                    LanguageUsage { language: String::from("YAML"),    color: String::from("#cb171e"), percentage: 2.00 },
                    LanguageUsage { language: String::from("other"),  color: String::from("#aaaaaa"), percentage: 3.00 },
                ],
            },
            Project {
                icon_path: String::from("static/icons/tiny/webassembly.svg"),
                name: String::from("Yew Website"),
                url: String::from("https://github.com/knoc-off/nixos/tree/main/pkgs/portfolio"),
                description: String::from("This website! Compiled to WASM, programed in Rust"),
                languages: vec![
                    LanguageUsage { language: String::from("Rust"),    color: String::from("#dea584"), percentage: 59.73 },
                    LanguageUsage { language: String::from("Sass"),    color: String::from("#a53b70"), percentage: 34.48 },
                    LanguageUsage { language: String::from("Nix"),     color: String::from("#7e7eff"), percentage: 2.54 },
                    LanguageUsage { language: String::from("TOML"),    color: String::from("#9c4221"), percentage: 2.46 },
                    LanguageUsage { language: String::from("HTML"),    color: String::from("#e34c26"), percentage: 0.79 },
                ],
            },



        ],
    }
}
