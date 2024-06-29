use crate::components::link_item::LinkItem;
use crate::components::social_links::LogoLink;
use yew::prelude::*;

#[function_component(Navbar)]
pub fn navbar() -> Html {
    html! {
        <nav>
            <div style="display: flex; align-items: center;">
                <LogoLink
                    link={"https://www.linkedin.com/in/niko-selby/".to_string()}
                    img_src={"/icons/share/icons/SuperTinyIcons/svg/linkedin.svg".to_string()}
                    alt_text={"LinkedIn".to_string()}
                />
                <LogoLink
                    link={"https://github.com/knoc-off".to_string()}
                    img_src={"/icons/share/icons/SuperTinyIcons/svg/github.svg".to_string()}
                    alt_text={"GitHub".to_string()}
                />
                <LogoLink
                    link={"/static/cv.pdf".to_string()}
                    img_src={"/icons/share/icons/SuperTinyIcons/svg/pdf.svg".to_string()}
                    alt_text={"CV".to_string()}
                />
            </div>

            <div style="display: flex; justify-content: center;">
                <LinkItem color={"#ffffff"} text={"Home".to_string()} href={"/".to_string()} />
                <LinkItem color={"#ffffff"} text={"About".to_string()} href={"/about".to_string()} />
                <LinkItem color={"#ffffff"} text={"Resume".to_string()} href={"/resume".to_string()} />
                // Add additional navigation links here
            </div>
        </nav>
    }
}
