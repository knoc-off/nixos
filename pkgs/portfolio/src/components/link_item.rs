use yew::prelude::*;
//#use crate::color_utils::get_complementary_color;
use crate::color_utils::darken_color;

#[derive(Properties, PartialEq)]
pub struct LinkItemProps {
    pub text: String,
    pub href: String,
    #[prop_or_default]
    pub color: Option<String>,
    #[prop_or_default]
    pub hover_color: Option<String>,
    #[prop_or_default]
    pub aspect_ratio: Option<f32>,
}

#[function_component(LinkItem)]
pub fn link_item(props: &LinkItemProps) -> Html {
    let color = props.color.clone().unwrap_or_else(|| "#3498db".to_string());
    let hover_color = darken_color(&color, 0.3);
    let aspect_ratio = props.aspect_ratio.unwrap_or(1.0);

    html! {
        <>
        <style>
            {format!(
                "
                .link {{
                    text-decoration: none;
                    color: {};
                    transition: color 0.3s ease, transform 0.1s ease;
                }}
                .link:hover {{
                    color: {};
                    transform: scale({});
                }}
                ",
                color, hover_color, aspect_ratio
            )}
        </style>
        <a class="link" href={props.href.clone()}>{ &props.text }</a>
        </>
    }
}
