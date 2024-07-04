use yew::prelude::*;
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
            <div class="resume">
                <div class="grid">
                    <div class="header">
                        <h1>{ &self.data.name }</h1>
                        <h2>{ &self.data.title }</h2>
                        <div class="contact">
                            <div>
                                <a href={format!("mailto:{}", &self.data.contact.email)}>
                                    <span class="icon">{ '\u{E158}' }</span>
                                    <span>{ &self.data.contact.email }</span>
                                </a>
                                <a href={format!("tel:{}", &self.data.contact.phone)}>
                                    <span class="icon">{ '\u{E0CD}' }</span>
                                    <span>{ &self.data.contact.phone }</span>
                                </a>
                                <a href={format!("https://www.google.com/maps/search/?api=1&query={}", &self.data.contact.location)} target="_blank">
                                    <span class="icon">{ '\u{E0C8}' }</span>
                                    <span>{ &self.data.contact.location }</span>
                                </a>
                            </div>
                            <div class="social">
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

                    <div class="photo">
                        <img src={self.data.photo_path.clone()} alt="Profile Photo" />
                    </div>

                    <div class="main">
                        <section>
                            <h2>{"EXPERIENCE"}</h2>
                            {for self.data.experience.iter().map(|exp| html!(
                                <div>
                                    <h3>{&exp.position}</h3>
                                    <p>{format!(" - {}", &exp.company) }</p>
                                    <p>{&exp.location} {" • "} {&exp.date_range}</p>
                                    <ul>
                                        {for exp.responsibilities.iter().map(|r| html!(
                                            <li>{r}</li>
                                        ))}
                                    </ul>
                                </div>
                            ))}
                        </section>

                        <section>
                            <h2>{"EDUCATION"}</h2>
                            {for self.data.education.iter().map(|edu| html!(
                                <div>
                                    <h3>{&edu.institution}</h3>
                                    <p>{&edu.location} {" • "} {&edu.date}</p>
                                    <ul>
                                        {for edu.details.iter().map(|d| html!(
                                            <li>{d}</li>
                                        ))}
                                    </ul>
                                </div>
                            ))}
                        </section>

                        <section>
                            <h2>{"SKILLS"}</h2>
                            <div class="skills">
                                { self.data.skills.iter().map(|skill| html! {
                                    <span>{ skill }</span>
                                }).collect::<Html>() }
                            </div>
                        </section>
                    </div>

                    <div class="sidebar">
                        <section>
                            <h2>{"LANGUAGES"}</h2>
                            <div>
                                { self.data.languages.iter().map(|lang| html! {
                                    <div>
                                        <img src={lang.icon.clone()} alt={format!("{} icon", lang.name)} />
                                        <span>{format!("{}: {}", lang.name, lang.level)}</span>
                                    </div>
                                }).collect::<Html>() }
                            </div>
                        </section>

                        <section>
                            <h2>{"INTERESTS"}</h2>
                            <p>{ &self.data.interests }</p>
                        </section>
                    </div>
                </div>
            </div>
        }
    }
}
