use yew::prelude::*;
use crate::components::markdown::MarkdownViewer;
use crate::components::social_links::LogoLinkProps;
use crate::components::social_links::LogoLink;

#[derive(Clone, PartialEq)]
pub struct ResumeData {
    name: String,
    title: String,
    contact: ContactInfo,
    summary: String,
    experience: Vec<Experience>,
    skills: Vec<String>,
    education: Vec<Education>,
    languages: Vec<Language>,
    interests: String,
}

#[derive(Clone, PartialEq)]
pub struct ContactInfo {
    email: String,
    phone: String,
    location: String,
    linkedin: String,
    github: String,
    social_links: Vec<LogoLinkProps>,
}

#[derive(Clone, PartialEq)]
pub struct Experience {
    company: String,
    position: String,
    location: String,
    date_range: String,
    responsibilities: Vec<String>,
}

#[derive(Clone, PartialEq)]
pub struct Education {
    institution: String,
    location: String,
    degree: String,
    date: String,
    details: Vec<String>,
}

#[derive(Clone, PartialEq)]
pub struct Language {
    name: String,
    level: String,
}

pub struct Resume {
    data: ResumeData,
}

#[derive(Properties, PartialEq)]
pub struct ResumeProps {
    pub data: ResumeData,
}

impl Component for Resume {
    type Message = ();
    type Properties = ResumeProps;

    fn create(ctx: &Context<Self>) -> Self {
        Resume {
            data: ctx.props().data.clone(),
        }
    }

    fn view(&self, _ctx: &Context<Self>) -> Html {
        html! {
            <>
            <style>
                {"@media print { @page { size: A4; margin: 0; } }"}
                {"
                    .contact-info {
                        display: flex;
                        justify-content: space-around;
                        align-items: center;
                    }

                    .contact-item {
                        display: flex;
                        align-items: center;
                        justify-content: center;
                        transition: transform 0.3s;
                    }

                    .contact-item:hover {
                        transform: scale(1.1);
                    }

                    .contact-item img {
                        width: 20px;
                        height: 20px;
                    }
                "}
            </style>
            <div class="resume-container">
                <div class="resume-grid">
                    <div class="quadrant top-left">
                        <h1>{ &self.data.name }</h1>
                        <h2>{ &self.data.title }</h2>
                        <div class="contact-info">
                            { self.data.contact.social_links.iter().map(|link| html! {
                                <LogoLink
                                    link={link.link.clone()}
                                    img_src={link.img_src.clone()}
                                    alt_text={link.alt_text.clone()}
                                    width={link.width.clone()}
                                    height={link.height.clone()}
                                    additional_style={link.additional_style.clone()}
                                />
                            }).collect::<Html>() }
                        </div>
                    </div>
                    <div class="quadrant top-right">
                        <MarkdownViewer markdown={format!(r#"
## PROFESSIONAL SUMMARY

{}
                        "#,
                        self.data.summary
                        )} />
                    </div>
                    <div class="quadrant bottom-left">
                        <MarkdownViewer markdown={format!(r#"
## EXPERIENCE

{}

## SKILLS

{}
                        "#,
                        self.data.experience.iter().map(|exp| format!(
                            "### {} - {}\n*{} • {}*\n\n{}\n",
                            exp.company,
                            exp.position,
                            exp.location,
                            exp.date_range,
                            exp.responsibilities.iter().map(|r| format!("- {}", r)).collect::<Vec<_>>().join("\n")
                        )).collect::<Vec<_>>().join("\n"),
                        self.data.skills.iter().map(|s| format!("- {}", s)).collect::<Vec<_>>().join("\n")
                        )} />
                    </div>
                    <div class="quadrant bottom-right">
                        <MarkdownViewer markdown={format!(r#"
## EDUCATION

{}

## LANGUAGES

{}

## INTERESTS

{}
                        "#,
                        self.data.education.iter().map(|edu| format!(
                            "### {}\n*{} • {}*\n{}\n{}",
                            edu.institution,
                            edu.location,
                            edu.date,
                            edu.degree,
                            edu.details.iter().map(|d| format!("- {}", d)).collect::<Vec<_>>().join("\n")
                        )).collect::<Vec<_>>().join("\n\n"),
                        self.data.languages.iter().map(|lang| format!("- {}: {}", lang.name, lang.level)).collect::<Vec<_>>().join("\n"),
                        self.data.interests
                        )} />
                    </div>
                </div>
            </div>
            </>
        }
    }
}

pub fn create_fake_resume_data() -> ResumeData {
    ResumeData {
        name: "John Doe".to_string(),
        title: "Software Engineer".to_string(),
        contact: ContactInfo {
            email: "john.doe@example.com".to_string(),
            phone: "555-1234".to_string(),
            location: "New York, NY".to_string(),
            linkedin: "https://www.linkedin.com/in/johndoe".to_string(),
            github: "https://github.com/johndoe".to_string(),




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
        summary: "Experienced software engineer with a passion for developing innovative programs that expedite the efficiency and effectiveness of organizational success.".to_string(),
        experience: vec![
            Experience {
                company: "TechCorp".to_string(),
                position: "Senior Developer".to_string(),
                location: "New York, NY".to_string(),
                date_range: "Jan 2020 - Present".to_string(),
                responsibilities: vec![
                    "Lead a team of 10 developers in creating a new e-commerce platform.".to_string(),
                    "Implemented a microservices architecture using Docker and Kubernetes.".to_string(),
                ],
            },
            Experience {
                company: "Web Solutions".to_string(),
                position: "Software Developer".to_string(),
                location: "San Francisco, CA".to_string(),
                date_range: "Jun 2015 - Dec 2019".to_string(),
                responsibilities: vec![
                    "Developed front-end and back-end features for client projects.".to_string(),
                    "Collaborated with designers to improve user experience.".to_string(),
                ],
            },
        ],
        skills: vec![
            "Rust".to_string(),
            "JavaScript".to_string(),
            "Docker".to_string(),
            "Kubernetes".to_string(),
        ],
        education: vec![
            Education {
                institution: "State University".to_string(),
                location: "Los Angeles, CA".to_string(),
                degree: "Bachelor of Science in Computer Science".to_string(),
                date: "Class of 2015".to_string(),
                details: vec![
                    "Dean's List".to_string(),
                    "Graduated with Honors".to_string(),
                ],
            },
        ],
        languages: vec![
            Language {
                name: "English".to_string(),
                level: "Native".to_string(),
            },
            Language {
                name: "Spanish".to_string(),
                level: "Fluent".to_string(),
            },
        ],
        interests: "Open source contribution, hiking, photography".to_string(),
    }
}
