use gtk4::prelude::*;
use gtk4::{
    gdk::Display, ApplicationWindow, Box as GtkBox, CssProvider, Orientation,
    STYLE_PROVIDER_PRIORITY_APPLICATION, Button, EventControllerMotion, Image, Label, ListBox,
    PositionType, Popover, glib,
};
use gtk4_layer_shell::{Edge, Layer, LayerShell};
use relm4::{Component, ComponentController, ComponentParts, ComponentSender, Controller, RelmApp};
use std::time::Duration;

#[derive(Debug, Clone, Copy)]
enum MenuAction {
    Home,
    Settings,
    About,
}

// Menu button component
#[derive(Debug)]
enum MenuButtonInput {
    Toggle,
    MenuItem(MenuAction),
    MouseEntered,
    MouseLeft,
    CloseTimeout,
}

#[derive(Debug)]
enum MenuButtonOutput {
    ItemSelected(MenuAction),
}

struct MenuButtonModel {
    is_open: bool,
    mouse_in_zone: bool,
    close_timer: Option<glib::SourceId>,
}

struct MenuButtonWidgets {
    button: Button,
    popover: Popover,
    list_box: ListBox,
}

fn create_menu_item(
    icon_name: &str,
    label: &str,
    action: MenuAction,
    sender: &ComponentSender<MenuButtonModel>,
) -> gtk4::ListBoxRow {
    let item_box = GtkBox::builder()
        .orientation(Orientation::Horizontal)
        .spacing(8)
        .margin_start(12)
        .margin_end(12)
        .margin_top(8)
        .margin_bottom(8)
        .build();

    let icon = Image::from_icon_name(icon_name);
    item_box.append(&icon);
    item_box.append(&Label::new(Some(label)));

    let row = gtk4::ListBoxRow::new();
    row.set_child(Some(&item_box));

    row.connect_activate({
        let sender = sender.clone();
        move |_| sender.input(MenuButtonInput::MenuItem(action))
    });

    row
}

impl Component for MenuButtonModel {
    type CommandOutput = ();
    type Input = MenuButtonInput;
    type Output = MenuButtonOutput;
    type Init = ();
    type Root = Button;
    type Widgets = MenuButtonWidgets;

    fn init_root() -> Self::Root {
        Button::new()
    }

    fn init(
        _init: Self::Init,
        root: Self::Root,
        sender: ComponentSender<Self>,
    ) -> ComponentParts<Self> {
        let model = MenuButtonModel {
            is_open: false,
            mouse_in_zone: false,
            close_timer: None,
        };

        // Icon only button
        let icon_image = Image::from_icon_name("open-menu-symbolic");
        root.set_child(Some(&icon_image));

        // Button mouse tracking
        let button_motion = EventControllerMotion::new();
        root.add_controller(button_motion.clone());
        button_motion.connect_enter({
            let sender = sender.clone();
            move |_, _, _| sender.input(MenuButtonInput::MouseEntered)
        });
        button_motion.connect_leave({
            let sender = sender.clone();
            move |_| sender.input(MenuButtonInput::MouseLeft)
        });

        // Connect button click
        root.connect_clicked({
            let sender = sender.clone();
            move |_| sender.input(MenuButtonInput::Toggle)
        });

        // Create popover
        let popover = Popover::builder()
            .has_arrow(false)
            .autohide(false)
            .position(PositionType::Right)
            .build();

        popover.set_parent(&root);

        // Popover mouse tracking
        let popover_motion = EventControllerMotion::new();
        popover.add_controller(popover_motion.clone());
        popover_motion.connect_enter({
            let sender = sender.clone();
            move |_, _, _| sender.input(MenuButtonInput::MouseEntered)
        });
        popover_motion.connect_leave({
            let sender = sender.clone();
            move |_| sender.input(MenuButtonInput::MouseLeft)
        });

        // Create list box for menu items
        let list_box = ListBox::builder()
            .selection_mode(gtk4::SelectionMode::None)
            .build();

        list_box.append(&create_menu_item("go-home-symbolic", "Home", MenuAction::Home, &sender));
        list_box.append(&create_menu_item("preferences-system-symbolic", "Settings", MenuAction::Settings, &sender));
        list_box.append(&create_menu_item("dialog-information-symbolic", "About", MenuAction::About, &sender));

        popover.set_child(Some(&list_box));

        let widgets = MenuButtonWidgets {
            button: root,
            popover,
            list_box,
        };

        ComponentParts { model, widgets }
    }

    fn update(&mut self, msg: Self::Input, sender: ComponentSender<Self>, _root: &Self::Root) {
        match msg {
            MenuButtonInput::Toggle => {
                self.is_open = !self.is_open;
                if let Some(timer) = self.close_timer.take() {
                    timer.remove();
                }
            }

            MenuButtonInput::MenuItem(action) => {
                let _ = sender.output(MenuButtonOutput::ItemSelected(action));
                self.is_open = false;
            }

            MenuButtonInput::MouseEntered => {
                self.mouse_in_zone = true;
                if let Some(timer) = self.close_timer.take() {
                    timer.remove();
                }
            }

            MenuButtonInput::MouseLeft => {
                self.mouse_in_zone = false;
                if !self.mouse_in_zone && self.is_open {
                    if let Some(timer) = self.close_timer.take() {
                        timer.remove();
                    }
                    let sender_clone = sender.clone();
                    let timer = glib::timeout_add_local(Duration::from_millis(500), move || {
                        sender_clone.input(MenuButtonInput::CloseTimeout);
                        glib::ControlFlow::Break
                    });
                    self.close_timer = Some(timer);
                }
            }

            MenuButtonInput::CloseTimeout => {
                self.is_open = false;
                self.close_timer = None;
            }
        }
    }

    fn update_view(&self, widgets: &mut Self::Widgets, _sender: ComponentSender<Self>) {
        if self.is_open {
            widgets.popover.popup();
        } else {
            widgets.popover.popdown();
        }
    }
}

impl Drop for MenuButtonModel {
    fn drop(&mut self) {
        if let Some(timer) = self.close_timer.take() {
            timer.remove();
        }
    }
}

// Main app component
struct AppModel {
    menu_button: Controller<MenuButtonModel>,
}

#[derive(Debug)]
enum AppMsg {
    MenuItem(MenuAction),
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
            .default_width(60)
            .default_height(1504)
            .resizable(false)
            .build();

        window.init_layer_shell();
        window.set_layer(Layer::Top);
        window.set_exclusive_zone(63);

        window.set_anchor(Edge::Left, true);
        window.set_anchor(Edge::Top, true);
        window.set_anchor(Edge::Bottom, true);

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
        let css_provider = CssProvider::new();
        css_provider.load_from_data(
            "window, box {
                background-color: transparent;
                background-image: none;
                background: none;
            }
            button {
                background: none;
                border: none;
                box-shadow: none;
                padding: 4px;
            }
            button:hover {
                background: rgba(255, 255, 255, 0.1);
            }",
        );

        if let Some(display) = Display::default() {
            gtk4::style_context_add_provider_for_display(
                &display,
                &css_provider,
                STYLE_PROVIDER_PRIORITY_APPLICATION,
            );
        }

        let menu_button =
            MenuButtonModel::builder()
                .launch(())
                .forward(sender.input_sender(), |msg| match msg {
                    MenuButtonOutput::ItemSelected(action) => AppMsg::MenuItem(action),
                });

        let model = AppModel { menu_button };

        let main_box = GtkBox::builder()
            .orientation(Orientation::Vertical)
            .spacing(15)
            .margin_top(15)
            .margin_bottom(10)
            .margin_start(0)
            .margin_end(0)
            .halign(gtk4::Align::Center)
            .build();

        let button_widget = model.menu_button.widget();
        button_widget.set_halign(gtk4::Align::Center);
        main_box.append(button_widget);

        root.set_child(Some(&main_box));

        let widgets = AppWidgets {};

        ComponentParts { model, widgets }
    }

    fn update(&mut self, msg: Self::Input, _sender: ComponentSender<Self>, _root: &Self::Root) {
        match msg {
            AppMsg::MenuItem(MenuAction::Home) => println!("Selected: home"),
            AppMsg::MenuItem(MenuAction::Settings) => println!("Selected: settings"),
            AppMsg::MenuItem(MenuAction::About) => println!("Selected: about"),
        }
    }
}

struct AppWidgets {}

fn main() {
    let app = RelmApp::new("com.example.sidebar");
    app.run::<AppModel>(());
}
