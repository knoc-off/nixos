use gloo_timers::callback::Interval;
use yew::prelude::*;

#[derive(Properties, PartialEq, Clone)]
pub struct CarouselProps {
    pub items: Vec<Html>,
    pub interval: u32,
}

pub struct Carousel {
    current_index: usize,
    interval_task: Option<Interval>,
    props: CarouselProps,
}

pub enum Msg {
    Next,
    StartAutoPlay,
    StopAutoPlay,
}

impl Component for Carousel {
    type Message = Msg;
    type Properties = CarouselProps;

    fn create(ctx: &Context<Self>) -> Self {
        let props = ctx.props().clone();
        let link = ctx.link().clone();
        let interval_task = Interval::new(props.interval, move || link.send_message(Msg::Next));

        Self {
            current_index: 0,
            interval_task: Some(interval_task),
            props,
        }
    }

    fn update(&mut self, ctx: &Context<Self>, msg: Self::Message) -> bool {
        match msg {
            Msg::Next => {
                self.current_index = (self.current_index + 1) % self.props.items.len();
                true
            }
            Msg::StartAutoPlay => {
                let handle = {
                    let link = ctx.link().clone();
                    Interval::new(self.props.interval, move || link.send_message(Msg::Next))
                };
                self.interval_task = Some(handle);
                false
            }
            Msg::StopAutoPlay => {
                self.interval_task = None;
                false
            }
        }
    }

    fn view(&self, ctx: &Context<Self>) -> Html {
        let current_item = &self.props.items[self.current_index];

        html! {
            <div>
                <div class="carousel">
                    { current_item.clone() }
                </div>
                <button onclick={ctx.link().callback(|_| Msg::Next)}>{ "Next" }</button>
                <button onclick={ctx.link().callback(|_| Msg::StartAutoPlay)}>{ "Start AutoPlay" }</button>
                <button onclick={ctx.link().callback(|_| Msg::StopAutoPlay)}>{ "Stop AutoPlay" }</button>
            </div>
        }
    }
}
