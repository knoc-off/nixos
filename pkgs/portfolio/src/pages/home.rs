use yew::prelude::*;
use crate::components::main_content::MainContent;

#[function_component(Home)]
pub fn home() -> Html {
    html! {
        <div class="home">
            <MainContent />
        </div>
    }
}
