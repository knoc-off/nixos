use yew::prelude::*;
use yew_router::prelude::*;
use crate::pages::{home::Home, about::About, resume::Resume};

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
        AppRoute::Resume => html! { <Resume /> },
        AppRoute::NotFound => html! { <h1>{ "404 Not Found" }</h1> },
    }
}
