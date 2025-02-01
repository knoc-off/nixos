use axum::response::IntoResponse;
use askama::Template;
use serde::Deserialize;
use std::fs;
use anyhow::Result;
use crate::HtmlTemplate;

#[derive(Debug, Deserialize)]
pub struct Job {
    pub title: String,
    pub company: String,
    pub location: String,
    pub date_range: String,
    pub bullets: Vec<String>,
}

#[derive(Debug, Deserialize)]
pub struct School {
    pub name: String,
    pub degree: String,
    pub location: String,
    pub dates: String,
}

#[derive(Debug, Deserialize)]
pub struct Project {
    pub name: String,
    pub description: String,
    pub icon: Option<String>,
    pub bullets: Vec<String>,
}

#[derive(Debug, Deserialize)]
pub struct Language {
    pub name: String,
    pub level: String,
    pub icon: Option<String>,
}

#[derive(Debug, Deserialize)]
pub struct Social {
    pub url: String,
    pub icon: String,
    pub name: String,
}

#[derive(Debug, Deserialize)]
pub struct ResumeData {
    pub title: String,
    pub name: String,
    pub headline: String,
    pub socials: Vec<Social>,
    pub email: Option<String>,
    pub phone: Option<String>,
    pub location: Option<String>,
    pub photo_url: Option<String>,
    pub jobs: Vec<Job>,
    pub schools: Vec<School>,
    pub projects: Vec<Project>,
    pub languages: Vec<Language>,
    pub skills: Vec<String>,
    pub interests: String,
}

mod filters {
    use std::fs;
    use std::collections::HashMap;
    use once_cell::sync::Lazy;

    // Define icon set mappings
    static ICON_SETS: Lazy<HashMap<&'static str, &'static str>> = Lazy::new(|| {
        let mut m = HashMap::new();
        m.insert("cf", "circle-flags");
        m.insert("sti", "super-tiny-icons");
        m.insert("tif", "tabler-icons-filled");
        m.insert("tio", "tabler-icons-outline");
        m
    });

    pub fn optional_string(opt: &Option<String>) -> ::askama::Result<String> {
        Ok(opt.clone().unwrap_or_default())
    }

pub fn svg_icon(class: &str) -> ::askama::Result<String> {
    let icon_name = class
        .split_whitespace()
        .find(|c| c.starts_with("svg_icon_"))
        .and_then(|c| c.strip_prefix("svg_icon_"))
        .ok_or_else(|| askama::Error::Custom("No svg_icon_ class found".into()))?;

    let classes = class
        .split_whitespace()
        .filter(|c| !c.starts_with("svg_icon_"))
        .collect::<Vec<_>>()
        .join(" ");

    let file_path = match icon_name.split_once('-') {
        Some((prefix, name)) if ICON_SETS.contains_key(prefix) =>
            format!("static/icons/{}/{}.svg", ICON_SETS[prefix], name),
        _ => format!("static/icons/{}.svg", icon_name),
    };

    match fs::read_to_string(&file_path) {
        Ok(content) => {
            if let (Some(start), Some(end)) = (content.find("<svg"), content.rfind("</svg>")) {
                let svg_part = &content[start..end];
                if let Some(attr_end) = svg_part.find('>') {
                    let attrs = svg_part[4..attr_end]
                        .split_whitespace()
                        .filter(|a| !a.starts_with("class="))
                        .collect::<Vec<_>>()
                        .join(" ");
                    let inner = &svg_part[attr_end + 1..];

                    Ok(format!(
                        r#"<svg xmlns="http://www.w3.org/2000/svg"  class="{}" {} currentColor="currentColor">{}</svg>"#,
                        if classes.is_empty() { "w-6 h-6" } else { &classes },
                        attrs,
                        inner
                    ))
                } else {
                    Ok("<!-- Invalid SVG -->".to_string())
                }
            } else {
                Ok("<!-- Invalid SVG -->".to_string())
            }
        }
        Err(_) => Ok(format!("<!-- Failed to load: {} -->", file_path))
    }
}
}

#[derive(Template)]
#[template(path = "resume.html")]
pub struct ResumeTemplate {
    pub title: String,
    pub name: String,
    pub headline: String,
    pub socials: Vec<Social>,
    pub email: Option<String>,
    pub phone: Option<String>,
    pub location: Option<String>,
    pub photo_url: Option<String>,
    pub jobs: Vec<Job>,
    pub schools: Vec<School>,
    pub projects: Vec<Project>,
    pub languages: Vec<Language>,
    pub skills: Vec<String>,
    pub interests: String,
}

fn load_resume_data() -> Result<ResumeData> {
    let file_content = fs::read_to_string("/opt/website_data/resume_data.json")?;
    let resume_data: ResumeData = serde_json::from_str(&file_content)?;
    Ok(resume_data)
}

pub async fn resume_main() -> impl IntoResponse {
    let resume_data = match load_resume_data() {
        Ok(data) => data,
        Err(e) => {
            eprintln!("Failed to load resume data: {}", e);
            return HtmlTemplate(ResumeTemplate {
                title: "Error".to_owned(),
                name: "Error loading resume".to_owned(),
                headline: "".to_owned(),
                socials: vec![],
                email: None,
                phone: None,
                location: None,
                photo_url: None,
                jobs: vec![],
                schools: vec![],
                projects: vec![],
                languages: vec![],
                skills: vec![],
                interests: "".to_owned(),
            });
        }
    };

    let template = ResumeTemplate {
        title: resume_data.title,
        name: resume_data.name,
        headline: resume_data.headline,
        socials: resume_data.socials,
        email: resume_data.email,
        phone: resume_data.phone,
        location: resume_data.location,
        photo_url: resume_data.photo_url,
        jobs: resume_data.jobs,
        schools: resume_data.schools,
        projects: resume_data.projects,
        languages: resume_data.languages,
        skills: resume_data.skills,
        interests: resume_data.interests,
    };

    HtmlTemplate(template)
}
