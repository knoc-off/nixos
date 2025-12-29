use gtk4::prelude::*;
use gtk4::{glib, Application, ApplicationWindow, Button, Orientation, Box as GtkBox};
use gtk4_layer_shell::{Edge, Layer, LayerShell};
use relm4::{Component, ComponentParts, ComponentSender, RelmApp, RelmWidgetExt};

struct AppModel {
    counter: u32,
}

#[derive(Debug)]
enum AppMsg {
    ButtonClicked,
}

struct AppWidgets {
    button: Button,
}

impl Component for AppModel {
    type CommandOutput = ();
    type Input = AppMsg;
    type Output = ();
    type Init = ();
    type Root = ApplicationWindow;
    type Widgets = AppWidgets;

    fn init_root() -> Self::Root {
        let window = ApplicationWindow::builder()
            .title("Sidebar")
            .default_width(300)
            .default_height(0) // Will fill screen height
            .build();

        // Initialize layer shell
        window.init_layer_shell();

        // Configure layer shell properties
        window.set_layer(Layer::Top);
        window.auto_exclusive_zone_enable();

        // Anchor to the left edge and stretch vertically
        window.set_anchor(Edge::Left, true);
        window.set_anchor(Edge::Top, true);
        window.set_anchor(Edge::Bottom, true);

        // Set margins
        window.set_margin(Edge::Left, 0);
        window.set_margin(Edge::Top, 0);
        window.set_margin(Edge::Bottom, 0);

        window
    }

    fn init(
        _init: Self::Init,
        root: Self::Root,
        sender: ComponentSender<Self>,
    ) -> ComponentParts<Self> {
        let model = AppModel { counter: 0 };

        // Create the main container
        let main_box = GtkBox::builder()
            .orientation(Orientation::Vertical)
            .spacing(10)
            .margin_top(20)
            .margin_bottom(20)
            .margin_start(20)
            .margin_end(20)
            .build();

        // Create a button
        let button = Button::builder()
            .label("Click me!")
            .build();

        // Add button to the container
        main_box.append(&button);

        // Set the container as the window's child
        root.set_child(Some(&main_box));

        // Connect button click event
        {
            let sender = sender.clone();
            button.connect_clicked(move |_| {
                sender.input(AppMsg::ButtonClicked);
            });
        }

        let widgets = AppWidgets { button };

        ComponentParts { model, widgets }
    }

    fn update(&mut self, msg: Self::Input, _sender: ComponentSender<Self>, _root: &Self::Root) {
        match msg {
            AppMsg::ButtonClicked => {
                self.counter += 1;
                println!("Button clicked {} times!", self.counter);
            }
        }
    }

    fn update_view(&self, widgets: &mut Self::Widgets, _sender: ComponentSender<Self>) {
        widgets.button.set_label(&format!("Clicked {} times", self.counter));
    }
}

fn main() {
    // Create GTK application
    let app = RelmApp::new("com.example.sidebar");

    // Run the application
    app.run::<AppModel>(());
}
