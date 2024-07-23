use yew::prelude::*;
use yew_router::prelude::*;
use app::router::{switch, AppRoute};

#[function_component(App)]
fn app() -> Html {
    html! {
        <BrowserRouter>
            <Switch<AppRoute> render={|routes: AppRoute| switch(&routes)} />
        </BrowserRouter>
    }
}

fn main() {
    yew::Renderer::<App>::new().render();
}
