use yew::prelude::*;
use crate::data::name::Name;

#[derive(Properties, PartialEq, Clone)]
pub struct Recipient {
    pub name: Name,
    pub company: String,
    pub address: String,
}

#[derive(Properties, PartialEq)]
pub struct RecipientProps {
    pub name: Name,
    pub company: String,
    pub address: String,
}

#[function_component(RecipientComponent)]
pub fn recipient_component(props: &RecipientProps) -> Html {
    html! {
        <div class="recipient">
            <p>{&props.name.first}</p>
            <p>{&props.company}</p>
            <p>{&props.address}</p>
        </div>
    }
}
