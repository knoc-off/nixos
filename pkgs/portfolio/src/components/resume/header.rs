use yew::prelude::*;
use super::contact_info::{ContactInfo, ContactInfoComponent};

#[derive(Properties, PartialEq)]
pub struct HeaderProps {
    pub name: String,
    pub title: String,
    pub contact_info: ContactInfo,
}

#[function_component(Header)]
pub fn header(props: &HeaderProps) -> Html {
    html! {
        <div class="header">
            <h1>{ &props.name }</h1>
            <h2>{ &props.title }</h2>
            <ContactInfoComponent info={props.contact_info.clone()} />
        </div>
    }
}
