use crate::data::link::*;
use yew::prelude::*;

#[function_component(LinkItem)]
pub fn link_item(props: &LinkData) -> Html {
    html! {
        <a href={props.link.clone()} class="link">{ &props.alt_text }</a>
    }
}

#[function_component(ImageLinkItem)]
pub fn image_link_item(props: &ImageLinkData) -> Html {
    html! {
        <a href={props.data.link.clone()} class="image-link">
            <img src={props.img_src.clone()} alt={props.data.alt_text.clone()} />
            <span class="link-text">{ &props.data.alt_text }</span>
        </a>
    }
}



