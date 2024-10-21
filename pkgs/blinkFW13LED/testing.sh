#!/usr/bin/env bash

set -e -u -o pipefail

# chromeos\:white\:power/brightness

# blink on and off
for i in {1..10}; do
    echo 0 > /sys/class/leds/chromeos\:white\:power/brightness
    sleep 0.5
    echo 1 > /sys/class/leds/chromeos\:white\:power/brightness
    sleep 0.5
done
