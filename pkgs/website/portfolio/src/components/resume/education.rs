use yew::prelude::*;

#[derive(Clone, PartialEq)]
pub struct Education {
    pub institution: String,
    pub location: String,
    pub degree: String,
    pub date: String,
    pub details: Vec<String>,
}

#[derive(Properties, PartialEq)]
pub struct EducationProps {
    pub education: Vec<Education>,
}

#[function_component(EducationSection)]
pub fn education_section(props: &EducationProps) -> Html {
    html! {
        <section>
            {for props.education.iter().map(|edu| html!(
                <div>
                    <div class="title-with-detail">
                        <h3>{&edu.institution}</h3>
                        <p>{format!(" - {}", &edu.degree) }</p>
                    </div>
                    <p>{&edu.location} {" • "} {&edu.date}</p>
                    <ul>
                        {for edu.details.iter().map(|d| html!(
                            <li>{d}</li>
                        ))}
                    </ul>
                </div>
            ))}
        </section>
    }
}
