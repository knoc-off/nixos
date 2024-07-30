use yew::prelude::*;
use crate::components::interaction::FruitSelector;

#[function_component(About)]
pub fn about() -> Html {
    html! {
        <FruitSelector />
    }
}
