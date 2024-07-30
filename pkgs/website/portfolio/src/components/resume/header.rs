use yew::prelude::*;
use super::contact_info::{ContactInfo, ContactInfoComponent};
use crate::data::name::Name;


#[derive(Properties, PartialEq)]
pub struct HeaderProps {
    pub name: Name,
    pub title: String,
    pub contact_info: ContactInfo,
}

#[function_component(Header)]
pub fn header(props: &HeaderProps) -> Html {
    html! {
        <div class="header">
            <div class="name-title">
                <div class="name">
                    <span class="first-name">{ &props.name.first.to_uppercase() }</span>
                    <span class="last-name">{ &props.name.last.to_uppercase() }</span>
                </div>
                <h2 class="title">{ &props.title }</h2>
            </div>
            <ContactInfoComponent info={props.contact_info.clone()} />
        </div>
    }
}
