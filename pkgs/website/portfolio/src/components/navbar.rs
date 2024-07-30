use crate::components::link_item::{LinkItem, ImageLinkItem};
use yew::prelude::*;

use crate::data::link::LinkData;

#[function_component(Navbar)]
pub fn navbar() -> Html {
    html! {
        <nav class="navbar">
            <div>
                <ImageLinkItem
                    data={LinkData { link: "https://www.linkedin.com/in/niko-selby/".to_string(), alt_text: "linkedin".to_string() }}
                    img_src={"/static/icons/tiny/linkedin.svg".to_string()}
                />
                <ImageLinkItem
                    data={LinkData { link: "https://github.com/knoc-off".to_string(), alt_text: "github".to_string() }}
                    img_src={"/static/icons/tiny/github.svg".to_string()}
                />
                <ImageLinkItem
                    data={LinkData { link: "/resume".to_string(), alt_text: "CV".to_string() }}
                    img_src={"/static/icons/tiny/pdf.svg".to_string()}
                />
            </div>

            <div style="display: flex; justify-content: center;">
                <LinkItem link={"/resume".to_string()} alt_text={"resume".to_string()} />
                <LinkItem link={"/home".to_string()} alt_text={"home".to_string()}  />
            </div>
        </nav>
    }
}
