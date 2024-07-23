use yew::prelude::*;
use crate::components::social_links::{LogoLink, LogoLinkProps};

#[derive(Clone, PartialEq)]
pub struct ContactInfo {
    pub email: String,
    pub phone: String,
    pub location: String,
    pub social_links: Vec<LogoLinkProps>,
}

#[derive(Properties, PartialEq)]
pub struct ContactInfoProps {
    pub info: ContactInfo,
}

#[function_component(ContactInfoComponent)]
pub fn contact_info(props: &ContactInfoProps) -> Html {
    html! {
        <div class="contact">
            <div>
                <a href={format!("mailto:{}", &props.info.email)}>
                    <span class="icon">{ '\u{E158}' }</span>
                    <span>{ &props.info.email }</span>
                </a>
                <a href={format!("tel:{}", &props.info.phone)}>
                    <span class="icon">{ '\u{E0CD}' }</span>
                    <span>{ &props.info.phone }</span>
                </a>
                <a href={format!("https://www.google.com/maps/search/?api=1&query={}", &props.info.location)} target="_blank">
                    <span class="icon">{ '\u{E0C8}' }</span>
                    <span>{ &props.info.location }</span>
                </a>
            </div>
            <div class="social">
                { props.info.social_links.iter().map(|link| html! {
                    <LogoLink
                        link={link.link.clone()}
                        img_src={link.img_src.clone()}
                        alt_text={link.alt_text.clone()}
                        width={link.width.clone()}
                        height={link.height.clone()}
                        additional_style={link.additional_style.clone()}
                    />
                }).collect::<Html>() }
            </div>
        </div>
    }
}
