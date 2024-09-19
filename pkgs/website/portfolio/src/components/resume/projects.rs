use yew::prelude::*;

#[derive(Clone, PartialEq)]
pub struct LanguageUsage {
    pub language: String,
    pub color: String,
    pub percentage: f32,
}

#[derive(Clone, PartialEq)]
pub struct Project {
    pub icon_path: String,
    pub name: String,
    pub description: String,
    pub bullets: Vec<String>,
    pub languages: Vec<LanguageUsage>,
    pub url: String,
}

#[derive(Properties, PartialEq)]
pub struct ProjectsProps {
    pub projects: Vec<Project>,
}

#[function_component(ProjectsSection)]
pub fn projects_section(props: &ProjectsProps) -> Html {
    html! {
        <section>
            {for props.projects.iter().map(|project| html! {
                <div class="resume-project">
                    <div class="resume-project-header">
                        <div class="resume-project-icon-container">
                            <img class="resume-project-icon" src={project.icon_path.clone()} alt={format!("{} icon", project.name)} />
                        </div>
                        <div class="resume-project-content">
                            <h3 class="resume-project-name">
                                <a href={project.url.clone()} target="_blank" rel="noopener noreferrer">
                                    {&project.name}
                                </a>
                            </h3>

                            <div class="resume-project-languages">
                                {for project.languages.iter().map(|lang| html! {
                                    <div class="resume-project-language" style={format!("width: {}%; min-width: 4%; background-color: {};", lang.percentage, lang.color)}>
                                        <span class="resume-project-language-text">
                                            {format!("{}: {:.1}%", lang.language, lang.percentage)}
                                        </span>
                                    </div>
                                })}
                            </div>

                            <p class="resume-project-description">{&project.description}</p>

                            <ul class="resume-project-bullets">
                                {for project.bullets.iter().map(|bullet| html! {
                                    <li>{bullet}</li>
                                })}
                            </ul>
                        </div>
                    </div>
                </div>
            })}
        </section>
    }
}
