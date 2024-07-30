use yew::prelude::*;

#[derive(Properties, PartialEq, Clone)]
pub struct LinkData {
    pub link: String,
    pub alt_text: String,
}

#[derive(Properties, PartialEq, Clone)]
pub struct ImageLinkData {
    pub data: LinkData,
    pub img_src: String,
}
