use yew::prelude::*;

#[derive(Properties, PartialEq)]
pub struct SkillsProps {
    pub skills: Vec<String>,
}

#[function_component(SkillsSection)]
pub fn skills_section(props: &SkillsProps) -> Html {
    html! {
        <section>
            <h2>{"SKILLS"}</h2>
            <div class="skills">
                { props.skills.iter().map(|skill| html! {
                    <span>{ skill }</span>
                }).collect::<Html>() }
            </div>
        </section>
    }
}
