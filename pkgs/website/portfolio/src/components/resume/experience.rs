use yew::prelude::*;

#[derive(Clone, PartialEq)]
pub struct Experience {
    pub company: String,
    pub position: String,
    pub location: String,
    pub date_range: String,
    pub responsibilities: Vec<String>,
}

#[derive(Properties, PartialEq)]
pub struct ExperienceProps {
    pub experiences: Vec<Experience>,
}

#[function_component(ExperienceSection)]
pub fn experience_section(props: &ExperienceProps) -> Html {
    html! {
        <section>
            {for props.experiences.iter().map(|exp| html!(
                <div>
                    <div class="title-with-detail">
                        <h3>{&exp.position}</h3>
                        <p>{format!(" - {}", &exp.company) }</p>
                    </div>
                    <p>{&exp.location} {" • "} {&exp.date_range}</p>
                    <ul>
                        {for exp.responsibilities.iter().map(|r| html!(
                            <li>{r}</li>
                        ))}
                    </ul>
                </div>
            ))}
        </section>
    }
}
