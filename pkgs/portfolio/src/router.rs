use yew::prelude::*;
use yew_router::prelude::*;
use crate::pages::{home::Home, about::About, resume::Resume};
use crate::pages::resume::create_fake_resume_data;

#[derive(Clone, Routable, PartialEq)]
pub enum AppRoute {
    #[at("/")]
    Home,
    #[at("/about")]
    About,
    #[at("/resume")]
    Resume,
    #[not_found]
    #[at("/404")]
    NotFound,
}

pub fn switch(route: &AppRoute) -> Html {
    match route {
        AppRoute::Home => html! { <Home /> },
        AppRoute::About => html! { <About /> },
        AppRoute::Resume => {
            let resume_data = create_fake_resume_data();
            html! { <Resume data={resume_data} /> }
        },
        AppRoute::NotFound => html! { <h1>{ "404 Not Found" }</h1> },
    }
}
