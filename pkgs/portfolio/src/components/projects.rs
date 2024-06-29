use crate::components::markdown::MarkdownViewer;
use yew::prelude::*;

// Assuming the Project struct is defined like this:
#[derive(Properties, PartialEq, Clone)]
pub struct Project {
    pub name: String,
    pub image_url: String,
    pub summary_md: String,
    pub link: String,
}

#[function_component(ProjectItem)]
pub fn project_item(props: &Project) -> Html {
    html! {
        <a href={props.link.clone()} target="_blank" rel="noopener noreferrer">
            <div class="project-item">
                <div class="header">
                    <img src={props.image_url.clone()} alt={props.name.clone()} />
                    <div class="title">
                        <h2>{ &props.name }</h2>
                    </div>
                </div>
                <div class="markdown-view">
                    // Assuming MarkdownViewer is a component that renders Markdown content
                    <MarkdownViewer markdown={props.summary_md.clone()} />
                </div>
            </div>
        </a>
    }
}

#[derive(Properties, PartialEq)]
pub struct ProjectsProps {
    pub projects: Vec<Project>,
}

#[function_component(Projects)]
pub fn projects(props: &ProjectsProps) -> Html {
    html! {
        <div class="projects-list">
            { for props.projects.iter().map(|project| html! {
                <ProjectItem ..project.clone() />
            })}
        </div>
    }
}
