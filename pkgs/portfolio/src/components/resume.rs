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
    pub icon: String,
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
                                    <a href={format!("mailto:{}", &self.data.contact.email)}>
                                        <span class="contact-icon fa-icon">{ '\u{E158}' }</span>
                                        <span>{ &self.data.contact.email }</span>
                                    </a>
                                </div>
                                <div class="contact-item">
                                    <a href={format!("tel:{}", &self.data.contact.phone)}>
                                        <span class="contact-icon fa-icon">{ '\u{E0CD}' }</span>
                                        <span>{ &self.data.contact.phone }</span>
                                    </a>
                                </div>
                                <div class="contact-item">
                                    <a href={format!("https://www.google.com/maps/search/?api=1&query={}", &self.data.contact.location)} target="_blank">
                                        <span class="contact-icon fa-icon">{ '\u{E0C8}' }</span>
                                        <span>{ &self.data.contact.location }</span>
                                    </a>
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
                        "#,
                        self.data.education.iter().map(|edu| format!(
                            "### {}\n*{}* • {}\n{}\n{}",
                            edu.institution,
                            edu.location,
                            edu.date,
                            edu.degree,
                            edu.details.iter().map(|d| format!("- {}", d)).collect::<Vec<_>>().join("\n")
                        )).collect::<Vec<_>>().join("\n\n")
                        )} />

                        <h2>{"LANGUAGES"}</h2>
                        <div class="languages-list">
                            { self.data.languages.iter().map(|lang| html! {
                                <div class="language-item">
                                    <img src={lang.icon.clone()} alt={format!("{} icon", lang.name)} class="language-icon" />
                                    <span>{format!("{}: {}", lang.name, lang.level)}</span>
                                </div>
                            }).collect::<Html>() }
                        </div>

                        <h2>{"INTERESTS"}</h2>
                        <p>{ &self.data.interests }</p>
                    </div>




                </div>
            </div>
            </>
        }
    }
}
