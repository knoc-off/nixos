import os
import time
import threading
import subprocess

PIPE_NAME = "/tmp/volume_pipe"

class VolumeInterpolator:
    def __init__(self, initial_volume=0.0, interpolation_time=0.5):
        self.current_volume = initial_volume
        self.target_volume = initial_volume
        self.interpolation_time = interpolation_time
        self.last_update_time = time.time()
        self.running = False
        self.event = threading.Event()

    def set_volume(self, new_volume):
        self.target_volume = new_volume
        self.last_update_time = time.time()
        self.event.set()

    def update(self):
        while self.running:
            self.event.wait()
            self.event.clear()

            while self.current_volume != self.target_volume:
                current_time = time.time()
                elapsed_time = current_time - self.last_update_time

                if elapsed_time >= self.interpolation_time:
                    self.current_volume = self.target_volume
                else:
                    t = elapsed_time / self.interpolation_time
                    self.current_volume = self.current_volume * (1 - t) + self.target_volume * t

                volume_level = int(self.current_volume)
                subprocess.run(['amixer', 'sset', 'Master', f'{volume_level}%'], stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)

                print(f"Current volume: {volume_level}%")

                time.sleep(0.01)

    def start(self):
        self.running = True
        threading.Thread(target=self.update).start()

    def stop(self):
        self.running = False
        self.event.set()

def read_pipe(volume_interpolator):
    if not os.path.exists(PIPE_NAME):
        os.mkfifo(PIPE_NAME)

    pipe = open(PIPE_NAME, "r")
    while volume_interpolator.running:
        message = pipe.readline().strip()
        if message:
            try:
                new_volume = float(message)
                if 0.0 <= new_volume <= 100.0:
                    volume_interpolator.set_volume(new_volume)
                else:
                    print(f"Invalid volume: {message}. Volume should be between 0.00 and 100.00.")
            except ValueError:
                print(f"Invalid volume: {message}")
    pipe.close()

def main():
    volume_interpolator = VolumeInterpolator(initial_volume=0.0, interpolation_time=0.5)
    volume_interpolator.start()

    pipe_thread = threading.Thread(target=read_pipe, args=(volume_interpolator,))
    pipe_thread.start()

    try:
        while True:
            time.sleep(1)
    except KeyboardInterrupt:
        volume_interpolator.stop()
        pipe_thread.join()

if __name__ == "__main__":
    main()

