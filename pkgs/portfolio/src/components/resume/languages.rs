use yew::prelude::*;

#[derive(Clone, PartialEq)]
pub struct Language {
    pub name: String,
    pub level: String,
    pub icon: String,
}

#[derive(Properties, PartialEq)]
pub struct LanguagesProps {
    pub languages: Vec<Language>,
}

#[function_component(LanguagesSection)]
pub fn languages_section(props: &LanguagesProps) -> Html {
    html! {
        <section>
            <h2>{"LANGUAGES"}</h2>
            <div>
                { props.languages.iter().map(|lang| html! {
                    <div>
                        <img src={lang.icon.clone()} alt={format!("{} icon", lang.name)} />
                        <span>{format!("{}: {}", lang.name, lang.level)}</span>
                    </div>
                }).collect::<Html>() }
            </div>
        </section>
    }
}
