use yew::prelude::*;

use crate::components::{ navbar::Navbar, footer::Footer, about_section::AboutSection  , projects::*};

#[function_component(MainContent)]
pub fn main_content() -> Html {
    let projects = vec![
        Project {
            name: "My Website".to_string(),
            image_url: "/icons/share/icons/SuperTinyIcons/svg/webassembly.svg".to_string(),
            summary_md: "
Website leveraging the Yew framework, which compiles to wasm. I aim to grow this project into something more substantial.

".to_string(),
            link: "https://github.com/knoc-off/Website".to_string()
        },
        Project {
            name: "Discord-GPT".to_string(),
            image_url: "/icons/share/icons/SuperTinyIcons/svg/discord.svg".to_string(),
            summary_md: "
Discord bot using ChatGPT to enable sentiment-based conversations within Discord channels. Built when chatGPT hype was at its peak
".to_string(),
            link: "https://github.com/knoc-off/DiscordGPT-rs".to_string()
        },
        Project {
            name: "My Nixos Configs".to_string(),
            image_url: "/icons/share/icons/SuperTinyIcons/svg/nixos.svg".to_string(),
            summary_md: "
My nixos configs, this defines all of my systems.
server management, custom pc, raspberry pi, etc.
".to_string(),
            link: "https://github.com/knoc-off/nixos/".to_string()
        },
        Project {
            name: "My Neovim Configs".to_string(),
            image_url: "/icons/share/icons/SuperTinyIcons/svg/vim.svg".to_string(),
            summary_md: "
This nix-flake exports a carbon copy of the editor i use daily. this makes it extremely portable.

".to_string(),
            link: "https://github.com/knoc-off/neovim-config".to_string()
        },
    ];

    html! {

        <div>
            <Navbar />
            <main>
                <section>
                    <AboutSection />
                    <h2>{ "My Projects:" }</h2>
                    <Projects projects={projects} />
                </section>
            </main>
            <Footer />
        </div>
    }
}
