use yew::prelude::*;
use crate::components::resume::*;
use crate::components::social_links::LogoLinkProps;

#[function_component(Resume)]
pub fn about() -> Html {
    let resume_data = create_resume_data();
    html! { <ResumeComponent data={resume_data} /> }
}



pub fn create_resume_data() -> ResumeData {
    ResumeData {
        name: "NICHOLAS SELBY".to_string(),
        title: "SOFTWARE DEVELOPER".to_string(),
        contact: ContactInfo {
            email: "selby@niko.ink".to_string(),
            phone: "+49 176 56615691".to_string(),
            location: "Berlin, Berlin 13465".to_string(),
            linkedin: "".to_string(), // Not provided in the data
            github: "".to_string(), // Not provided in the data
            social_links: vec![

                LogoLinkProps {
                    link: "https://www.linkedin.com/in/johndoe".to_string(),
                    img_src: "/icons/share/icons/SuperTinyIcons/svg/linkedin.svg".to_string(),
                    alt_text: "LinkedIn".to_string(),
                    width: Some("30px".to_string()),
                    height: Some("30px".to_string()),
                    additional_style: None,
                },
                LogoLinkProps {
                    link: "https://github.com/johndoe".to_string(),
                    img_src: "/icons/share/icons/SuperTinyIcons/svg/github.svg".to_string(),
                    alt_text: "GitHub".to_string(),
                    width: Some("30px".to_string()),
                    height: Some("30px".to_string()),
                    additional_style: None,
                },



            ],
        },
        summary: "Versatile Junior Software Developer with a track record of resolving technical issues and enhancing collaboration at Olymp Consulting. Demonstrated expertise in Python Programming. Achieved significant improvements in development processes through innovative technology integration. Skilled in both back-end development and fostering productive relationships. Seeking to utilize excellent communication, interpersonal, and organizational skills to complete tasks. Reliable with a good work ethic and the ability to quickly adapt to new tasks and environments.".to_string(),
        photo_path: "static/Niko.jpeg".to_string(), // No photo path provided in the data
        experience: vec![
            Experience {
                company: "Olymp Consulting".to_string(),
                position: "Junior Software Developer".to_string(),
                location: "Berlin, Berlin".to_string(),
                date_range: "10/2022 - 06/2023".to_string(),
                responsibilities: vec![
                    "Troubleshot, debugged, and resolved technical issues with existing software applications.".to_string(),
                    "Wrote comprehensive documentation for all developed programs or applications.".to_string(),
                    "Set up servers that hosted internal services to increase collaboration.".to_string(),
                    "Researched and proposed new technologies or tools that could improve development processes.".to_string(),
                    "Performed system integration testing to ensure compatibility between components.".to_string(),
                    "Participated in technical discussions and meetings, providing valuable insights and solutions.".to_string(),
                ],
            },
            Experience {
                company: "Motive School of Movement".to_string(),
                position: "Gymnastics Coach".to_string(),
                location: "Greenville, SC".to_string(),
                date_range: "03/2020 - 05/2021".to_string(),
                responsibilities: vec![
                    "Cultivated relationships with other coaches and staff members within the organization.".to_string(),
                    "Demonstrated ability to teach and motivate students of all ages and skill levels in gymnastics.".to_string(),
                    "Provided technical instruction on proper technique for tumbling, vaulting, bars, beam, floor exercises and trampoline.".to_string(),
                ],
            },
        ],
        skills: vec![
            "Python Programming".to_string(),
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
        ],
        education: vec![
            Education {
                institution: "Wade Hampton High School".to_string(),
                location: "Greenville SC".to_string(),
                degree: "High School Diploma".to_string(),
                date: "08/2021".to_string(),
                details: vec![
                    "Relevant Coursework: Computer Science using Java, AP Computer Science".to_string(),
                    "Extracurricular Activities: German Club".to_string(),
                ],
            },
            Education {
                institution: "Fine Arts Center".to_string(),
                location: "Greenville SC".to_string(),
                degree: "Graduation Certificate".to_string(),
                date: "06/2021".to_string(),
                details: vec![],
            },
            Education {
                institution: "T.U. Berlin".to_string(),
                location: "Berlin".to_string(),
                degree: "Gasthörerschaft".to_string(),
                date: "".to_string(),
                details: vec![
                    "Relevant Coursework: IT Fundamentals".to_string(),
                ],
            },
        ],
        languages: vec![
            Language {
                name: "English".to_string(),
                level: "Native".to_string(),
            },
            Language {
                name: "German".to_string(),
                level: "Fluent".to_string(),
            },
        ],
        interests: "Technology, including 3D printing, Arduino, programming, and game development, as well as hobbies like board games, drawing, and cooking.".to_string(),
    }
}
