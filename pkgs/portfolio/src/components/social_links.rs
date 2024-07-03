use yew::prelude::*;

#[derive(Properties, PartialEq, Clone)]
pub struct LogoLinkProps {
    pub link: String,
    pub img_src: String,
    pub alt_text: String,
    #[prop_or_default]
    pub width: Option<String>,
    #[prop_or_default]
    pub height: Option<String>,
    #[prop_or_default]
    pub additional_style: Option<String>,
}

#[function_component(LogoLink)]
pub fn logo_link(props: &LogoLinkProps) -> Html {
    // Default values for optional properties
    let width = props.width.clone().unwrap_or_else(|| "3rem".to_string());
    let height = props.height.clone().unwrap_or_else(|| "auto".to_string());
    let additional_style = props.additional_style.clone().unwrap_or_else(|| "".to_string());

    // Combine styles into a single string including animation styles
    let style = format!("width: {}; height: {}; {}", width, height, additional_style);

    html! {
        <>
            <style>
                {"
                .logo-link img {
                    transition: transform 0s linear;
                }
                .logo-link img:hover {
                    transform: translate(-2px, -2px);
                }
                "}
            </style>
            <a href={props.link.clone()} target="_blank" class="logo-link">
                <img src={props.img_src.clone()} alt={props.alt_text.clone()} style={style} />
            </a>
        </>
    }
}
