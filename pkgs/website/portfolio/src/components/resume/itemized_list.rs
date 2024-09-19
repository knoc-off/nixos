use yew::prelude::*;

#[derive(Properties, PartialEq)]
pub struct ItemsProps {
    pub items: Vec<String>,
}

#[function_component(ItemizedList)]
pub fn skills_section(props: &ItemsProps) -> Html {
    html! {
        <section>
            <div class="itemized-list">
                { props.items.iter().map(|skill| html! {
                    <span>{ skill }</span>
                }).collect::<Html>() }
            </div>
        </section>
    }
}
