use yew::prelude::*;

pub struct Resume;

impl Component for Resume {
    type Message = ();
    type Properties = ();

    fn create(_ctx: &Context<Self>) -> Self {
        Resume
    }

    fn view(&self, _ctx: &Context<Self>) -> Html {
        html! {
            <div>
                <h1>{ "New Page" }</h1>
                <p>{ "This is the content of the new page." }</p>
            </div>
        }
    }
}
