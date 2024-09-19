use crate::components::main_content::MainContent;
use yew::prelude::*;

#[function_component(Home)]
pub fn home() -> Html {
    html! {
        <div class="home">
            <MainContent />
        </div>
    }
}

