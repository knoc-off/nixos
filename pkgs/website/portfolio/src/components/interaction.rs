use yew::prelude::*;
use wasm_bindgen_futures::spawn_local;
use web_sys::HtmlInputElement;
use gloo_net::http::Request;
use serde::{Serialize, Deserialize};

#[derive(Serialize, Deserialize, Clone, PartialEq)]
struct FormData {
    name: String,
    fruits: Vec<String>,
}

#[derive(Serialize, Deserialize, Clone, PartialEq)]
struct BackendResponse {
    message: String,
}

#[function_component(FruitSelector)]
pub fn fruit_selector() -> Html {
    let name = use_state(|| String::new());
    let fruits = use_state(|| vec![]);
    let result = use_state(|| None);

    let onsubmit = {
        let name = name.clone();
        let fruits = fruits.clone();
        let result = result.clone();

        Callback::from(move |e: SubmitEvent| {
            e.prevent_default();
            let form_data = FormData {
                name: (*name).clone(),
                fruits: (*fruits).clone(),
            };

            let result = result.clone();
            spawn_local(async move {
                let response = Request::post("/api/process")
                    .json(&form_data)
                    .unwrap()
                    .send()
                    .await
                    .unwrap()
                    .json::<BackendResponse>()
                    .await
                    .unwrap();
                result.set(Some(response));
            });
        })
    };

    let onnameinput = {
        let name = name.clone();
        Callback::from(move |e: InputEvent| {
            let input: HtmlInputElement = e.target_unchecked_into();
            name.set(input.value());
        })
    };

    let onfruitchange = {
        let fruits = fruits.clone();
        Callback::from(move |e: Event| {
            let checkbox: HtmlInputElement = e.target_unchecked_into();
            let mut current_fruits = (*fruits).clone();
            if checkbox.checked() {
                current_fruits.push(checkbox.value());
            } else {
                current_fruits.retain(|f| f != &checkbox.value());
            }
            fruits.set(current_fruits);
        })
    };

    html! {
        <div>
            <h1>{"Fruit Selector"}</h1>
            <form onsubmit={onsubmit}>
                <div>
                    <label for="name">{"Name: "}</label>
                    <input type="text" id="name" oninput={onnameinput} value={(*name).clone()} />
                </div>
                <div>
                    <label>{"Select your favorite fruits:"}</label>
                    <div>
                        <input type="checkbox" id="apple" value="Apple" onchange={onfruitchange.clone()} />
                        <label for="apple">{"Apple"}</label>
                    </div>
                    <div>
                        <input type="checkbox" id="banana" value="Banana" onchange={onfruitchange.clone()} />
                        <label for="banana">{"Banana"}</label>
                    </div>
                    <div>
                        <input type="checkbox" id="orange" value="Orange" onchange={onfruitchange.clone()} />
                        <label for="orange">{"Orange"}</label>
                    </div>
                </div>
                <button type="submit">{"Submit"}</button>
            </form>
            {
                if let Some(response) = (*result).clone() {
                    html! { <p>{response.message}</p> }
                } else {
                    html! {}
                }
            }
        </div>
    }
}
