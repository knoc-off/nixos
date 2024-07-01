use yew::prelude::*;
use crate::components::markdown::MarkdownViewer;
use crate::components::social_links::LogoLinkProps;
use crate::components::social_links::LogoLink;



// Make these structs public
#[derive(Clone, PartialEq)]
pub struct ResumeData {
    pub name: String,
    pub title: String,
    pub contact: ContactInfo,
    pub summary: String,
    pub photo_path: String,
    pub experience: Vec<Experience>,
    pub skills: Vec<String>,
    pub education: Vec<Education>,
    pub languages: Vec<Language>,
    pub interests: String,
}

#[derive(Clone, PartialEq)]
pub struct ContactInfo {
    pub email: String,
    pub phone: String,
    pub location: String,
    pub linkedin: String,
    pub github: String,
    pub social_links: Vec<LogoLinkProps>,
}

#[derive(Clone, PartialEq)]
pub struct Experience {
    pub company: String,
    pub position: String,
    pub location: String,
    pub date_range: String,
    pub responsibilities: Vec<String>,
}

#[derive(Clone, PartialEq)]
pub struct Education {
    pub institution: String,
    pub location: String,
    pub degree: String,
    pub date: String,
    pub details: Vec<String>,
}

#[derive(Clone, PartialEq)]
pub struct Language {
    pub name: String,
    pub level: String,
}

// Make ResumeComponent public
pub struct ResumeComponent {
    data: ResumeData,
}

#[derive(Properties, PartialEq)]
pub struct ResumeProps {
    pub data: ResumeData,
}





impl Component for ResumeComponent {
    type Message = ();
    type Properties = ResumeProps;

    fn create(ctx: &Context<Self>) -> Self {
        ResumeComponent {
            data: ctx.props().data.clone(),
        }
    }

    fn view(&self, _ctx: &Context<Self>) -> Html {
        html! {
            <>
            <style>
                {"@media print { @page { size: A4; margin: 0; } }"}
                {"

                    .skills-grid {
                        display: flex;
                        flex-wrap: wrap;
                        gap: 10px;
                        margin-top: 10px;
                    }

                    .skill-item {
                        padding: 5px 10px;
                        border-radius: 5px;
                        font-size: 0.9em;
                    }
                "}
            </style>
            <div class="resume-container">
                <div class="resume-grid">
                    <div class="quadrant top-left">
                        <h1>{ &self.data.name }</h1>
                        <h2>{ &self.data.title }</h2>
                        <div class="contact-info">
                            <div class="contact-data">
                                <div class="contact-item">
                                    <img class="contact-icon" src="/icons/email.svg" alt="Email" />
                                    <span>{ &self.data.contact.email }</span>
                                </div>
                                <div class="contact-item">
                                    <img class="contact-icon" src="/icons/phone.svg" alt="Phone" />
                                    <span>{ &self.data.contact.phone }</span>
                                </div>
                                <div class="contact-item">
                                    <img class="contact-icon" src="/icons/location.svg" alt="Location" />
                                    <span>{ &self.data.contact.location }</span>
                                </div>
                            </div>
                            <div class="social-links">
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
                    </div>

                    <div class="quadrant top-right">
                        <img src={self.data.photo_path.clone()} alt="Profile Photo" />
                    </div>

                    <div class="quadrant bottom-left">
                        <MarkdownViewer markdown={format!(r#"
## EXPERIENCE

{}
                        "#,
                        self.data.experience.iter().map(|exp| format!(
                            "### {} - {}\n*{} • {}*\n\n{}\n",
                            exp.company,
                            exp.position,
                            exp.location,
                            exp.date_range,
                            exp.responsibilities.iter().map(|r| format!("- {}", r)).collect::<Vec<_>>().join("\n")
                        )).collect::<Vec<_>>().join("\n")
                        )} />
                        <h2>{"SKILLS"}</h2>
                        <div class="skills-grid">
                            { self.data.skills.iter().map(|skill| html! {
                                <span class="skill-item">{ skill }</span>
                            }).collect::<Html>() }
                        </div>
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
                            "### {}\n*{}* • {}\n{}\n{}",
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
