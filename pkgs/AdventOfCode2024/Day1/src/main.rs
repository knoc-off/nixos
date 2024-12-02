use bevy::{prelude::*, color::palettes::css::*};
use rand::prelude::*;


use std::fs::File;
use std::io::{BufRead, BufReader};


#[derive(Resource)]
struct NumberColumns {
    left: Vec<i64>,
    right: Vec<i64>,
    middle: Vec<i64>, // used to represent the difference between the left and right columns
    result: i64,
}

#[derive(Resource)]
struct SortingState {
    current_min_idx: usize,
    checking_idx: usize,
    scan_start_idx: usize,
    timer: Timer,
    left_is_sorted: bool,
    //right_is_sorted: bool,
}



#[derive(Debug, Clone, Copy, Default, PartialEq, Eq, Hash, States)]
enum GlobalState {
    #[default]
    Sorting,
    Difference,
    Add,
    Done,
}


// enum for text types, result, difference, etc
#[derive(Component)]
enum TextType {
    Result,
    Difference,
    Misc,
}


#[derive(Component)]
struct ColumnText {
    side: ColumnSide,
}

#[derive(PartialEq)]
enum ColumnSide {
    Left,
    Right,
    Middle,
    Result,
}

fn read_numbers_from_file(filepath: &str) -> Result<(Vec<i64>, Vec<i64>), std::io::Error> {
   let file = File::open(filepath)?;
   let reader = BufReader::new(file);

   let mut left = Vec::new();
   let mut right = Vec::new();

   for line in reader.lines() {
       let line = line?;
       let line = line.trim();
       if line.is_empty() {
           continue;
       }
       let tokens: Vec<&str> = line.split_whitespace().collect();
       if tokens.len() != 2 {
           // Handle error: Expected two numbers per line
           println!("Line does not have two numbers: {}", line);
           continue;
       }
       let left_num: i64 = tokens[0].parse().unwrap_or(0);
       let right_num: i64 = tokens[1].parse().unwrap_or(0);
       left.push(left_num);
       right.push(right_num);
   }

   Ok((left, right))
}

fn main() {
    let (left_numbers, right_numbers) = read_numbers_from_file("input.txt").expect("Failed to read numbers from file");

    let len = left_numbers.len().min(right_numbers.len());
    let left_numbers = left_numbers[..len].to_vec();
    let right_numbers = right_numbers[..len].to_vec();

    App::new()
        .add_plugins(DefaultPlugins)
        .insert_resource(NumberColumns {
            left: left_numbers,
            right: right_numbers,
            middle: vec![0; len],
            result: 0,

        })
        .insert_resource(SortingState {
            current_min_idx: 0,
            checking_idx: 1,
            scan_start_idx: 0,
            timer: Timer::from_seconds(0.000001, TimerMode::Repeating),
            left_is_sorted: false,
        })
        .init_state::<GlobalState>()
        .add_systems(Startup, setup)
        .add_systems(Update, ( animate_sorting, update_columns ).chain().run_if(in_state(GlobalState::Sorting)))
        .add_systems(Update, ( animate_difference, update_columns ).chain().run_if(in_state(GlobalState::Difference)))
        .add_systems(Update, ( add_animate, update_columns ).chain().run_if(in_state(GlobalState::Add)))
        .run();
}

fn setup(mut commands: Commands, asset_server: Res<AssetServer>) {
    commands.spawn(Camera2d);

    // Left column
    commands.spawn((
        TextType::Misc,
        Text::new(""),
        TextFont {
            font: asset_server.load("fonts/FiraSans-Regular.otf"),
            font_size: 10.0,
            ..default()
        },
        TextLayout::new_with_justify(JustifyText::Left),
        Node {
            position_type: PositionType::Absolute,
            left: Val::Percent(5.0),
            top: Val::Percent(1.0),
            ..default()
        },
        ColumnText { side: ColumnSide::Left },
    ));

    commands.spawn((
        TextType::Misc,
        Text::new(""),
        TextFont {
            font: asset_server.load("fonts/FiraSans-Regular.otf"),
            font_size: 10.0,
            ..default()
        },
        TextLayout::new_with_justify(JustifyText::Left),
        Node {
            position_type: PositionType::Absolute,
            right: Val::Percent(5.0),
            top: Val::Percent(1.0),
            ..default()
        },
        ColumnText { side: ColumnSide::Right },
    ));

    commands.spawn((
        TextType::Difference,
        Text::new(""),
        TextFont {
            font: asset_server.load("fonts/FiraSans-Regular.otf"),
            font_size: 10.0,
            ..default()
        },
        TextLayout::new_with_justify(JustifyText::Center),
        Node {
            position_type: PositionType::Absolute,
            left: Val::Percent(50.0),
            top: Val::Percent(1.0),
            ..default()
        },
        ColumnText { side: ColumnSide::Middle },
    ));

    commands.spawn((
        TextType::Result,
        ColumnText { side: ColumnSide::Result }, // idk not great
        Text::new("-"),
        TextFont {
            font: asset_server.load("fonts/FiraSans-Regular.otf"),
            font_size: 40.0,
            ..default()
        },
        TextLayout::new_with_justify(JustifyText::Center),
        Node {
            position_type: PositionType::Absolute,
            left: Val::Percent(5.0),
            bottom: Val::Percent(5.0),
            ..default()
        },
    ));
}


fn add_animate(
    time: Res<Time>,
    mut numbers: ResMut<NumberColumns>,
    mut sort_state: ResMut<SortingState>,
    mut state: ResMut<NextState<GlobalState>>,
) {
    sort_state.timer.tick(time.delta());

    if ! sort_state.timer.finished() {
        return;
    }

    let len = numbers.middle.len();


    numbers.result = numbers.result + numbers.middle[sort_state.scan_start_idx];


    // numbers.middle[sort_state.scan_start_idx] += numbers.middle[sort_state.scan_start_idx];
    sort_state.scan_start_idx += 1;


    if sort_state.scan_start_idx >= len {
        // set the GlobalState to Done
        state.set(GlobalState::Done);
        // reset index
        sort_state.scan_start_idx = 0;
    }
}


fn update_columns(
    numbers: Res<NumberColumns>,
    sort_state: Res<SortingState>,
    mut query: Query<(&mut Text, &mut TextColor, &ColumnText)>,
) {
    for (mut text, mut text_color, column) in &mut query {
        let numbers_vec = match column.side {
            ColumnSide::Left => &numbers.left,
            ColumnSide::Right => &numbers.right,
            ColumnSide::Middle => &numbers.middle,
            ColumnSide::Result => &vec![numbers.result],
        };

        let mut content = String::new();
        for (idx, &num) in numbers_vec.iter().enumerate() {
            text_color.0 = if idx < sort_state.scan_start_idx {
                GRAY.into()
            } else if idx == sort_state.current_min_idx {
                GREEN.into()
            } else if idx == sort_state.checking_idx {
                GOLD.into()
            } else if idx > sort_state.checking_idx {
                LIGHT_GRAY.into()
            } else {
                DARK_GRAY.into()
            };
            content.push_str(&format!("{}\n", num));
        }
        text.0 = content;
    }
}

   fn animate_sorting(
       time: Res<Time>,
       mut numbers: ResMut<NumberColumns>,
       mut sort_state: ResMut<SortingState>,
       mut state: ResMut<NextState<GlobalState>>,
   ) {
       sort_state.timer.tick(time.delta());

       if !sort_state.timer.finished() {
           return;
       }

       let len = if !sort_state.left_is_sorted {
           numbers.left.len()
       } else {
           numbers.right.len()
       };

       if sort_state.scan_start_idx >= len - 1 {
           if !sort_state.left_is_sorted {
               sort_state.left_is_sorted = true;
               sort_state.scan_start_idx = 0;
           } else {
               // Both columns are sorted, proceed to Difference state
               state.set(GlobalState::Difference);
               sort_state.scan_start_idx = 0;
               return;
           }
       }

       // Find index of the minimum element in the unsorted portion
       let (min_idx, _) = if !sort_state.left_is_sorted {
           numbers.left.iter()
               .enumerate()
               .skip(sort_state.scan_start_idx)
               .min_by_key(|&(_, &num)| num)
               .unwrap()
       } else {
           numbers.right.iter()
               .enumerate()
               .skip(sort_state.scan_start_idx)
               .min_by_key(|&(_, &num)| num)
               .unwrap()
       };

       // Swap the smallest element with the element at the current index
       if !sort_state.left_is_sorted {
           numbers.left.swap(sort_state.scan_start_idx, min_idx);
       } else {
           numbers.right.swap(sort_state.scan_start_idx, min_idx);
       }

       // Move to the next index
       sort_state.scan_start_idx += 1;
   }

fn animate_difference( // difference of left and right coulmn absolute
    time: Res<Time>,
    mut numbers: ResMut<NumberColumns>,
    mut sort_state: ResMut<SortingState>,
    mut state: ResMut<NextState<GlobalState>>,
) {

    sort_state.timer.tick(time.delta());

    if ! sort_state.timer.finished() {
        return;
    }

    let len = numbers.left.len();

    if sort_state.scan_start_idx >= len {
        return;
    }

    numbers.middle[sort_state.scan_start_idx] = (numbers.left[sort_state.scan_start_idx] - numbers.right[sort_state.scan_start_idx]).abs();
    sort_state.scan_start_idx += 1;


    if sort_state.scan_start_idx >= len {
        // set the GlobalState to Add
        state.set(GlobalState::Add);
        // reset index
        sort_state.scan_start_idx = 0;

    }
}

