use std::fs::{create_dir_all, File, OpenOptions};
use std::io::{BufRead, BufReader, Write};
use std::path::Path;
use std::process::Command;
use std::sync::{Arc, Mutex};
use std::thread;
use std::time::{Duration, Instant};

const PIPE_NAME: &str = "/tmp/volume_pipe";

struct VolumeInterpolator {
    current_volume: f64,
    target_volume: f64,
    interpolation_time: f64,
    last_update_time: Instant,
    running: bool,
}

impl VolumeInterpolator {
    fn new(initial_volume: f64, interpolation_time: f64) -> Self {
        VolumeInterpolator {
            current_volume: initial_volume,
            target_volume: initial_volume,
            interpolation_time,
            last_update_time: Instant::now(),
            running: false,
        }
    }

    fn set_volume(&mut self, new_volume: f64) {
        self.target_volume = new_volume;
        self.last_update_time = Instant::now();
    }

    fn update(&mut self) {
        while self.running {
            if self.current_volume != self.target_volume {
                let elapsed_time = self.last_update_time.elapsed().as_secs_f64();

                if elapsed_time >= self.interpolation_time {
                    self.current_volume = self.target_volume;
                } else {
                    let t = elapsed_time / self.interpolation_time;
                    self.current_volume = self.current_volume * (1.0 - t) + self.target_volume * t;
                }

                let volume_level = self.current_volume.round() as i32;
                Command::new("amixer")
                    .args(&["sset", "Master", &format!("{}%", volume_level)])
                    .output()
                    .expect("Failed to set volume");

                println!("Current volume: {}%", volume_level);
            }

            thread::sleep(Duration::from_millis(10));
        }
    }

    fn start(&mut self) {
        self.running = true;
        let mut clone = self.clone();
        thread::spawn(move || {
            clone.update();
        });
    }

    fn stop(&mut self) {
        self.running = false;
    }
}

impl Clone for VolumeInterpolator {
    fn clone(&self) -> Self {
        VolumeInterpolator {
            current_volume: self.current_volume,
            target_volume: self.target_volume,
            interpolation_time: self.interpolation_time,
            last_update_time: self.last_update_time,
            running: self.running,
        }
    }
}

fn read_pipe(volume_interpolator: Arc<Mutex<VolumeInterpolator>>) {
    let pipe_path = Path::new(PIPE_NAME);
    if !pipe_path.exists() {
        create_dir_all(pipe_path.parent().unwrap()).expect("Failed to create directory");
        unix_named_pipe::create(pipe_path).expect("Failed to create named pipe");
    }

    let pipe = OpenOptions::new()
        .read(true)
        .write(true)
        .open(pipe_path)
        .expect("Failed to open named pipe");

    let reader = BufReader::new(pipe);
    for message in reader.lines() {
        if let Ok(message) = message {
            if let Ok(new_volume) = message.parse::<f64>() {
                if (0.0..=100.0).contains(&new_volume) {
                    volume_interpolator.lock().unwrap().set_volume(new_volume);
                } else {
                    eprintln!("Invalid volume: {}. Volume should be between 0.00 and 100.00.", message);
                }
            } else {
                eprintln!("Invalid volume: {}", message);
            }
        }
    }
}

fn main() {
    let volume_interpolator = Arc::new(Mutex::new(VolumeInterpolator::new(0.0, 0.5)));
    volume_interpolator.lock().unwrap().start();

    let volume_interpolator_clone = volume_interpolator.clone();
    thread::spawn(move || {
        read_pipe(volume_interpolator_clone);
    });

    loop {
        thread::sleep(Duration::from_secs(1));
    }
}

