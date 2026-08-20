#!/usr/bin/env bash

# Define the socket based on PID (you might need to adjust this to get the correct PID)
#pid=$(pgrep nvim | head -n 1)
#socket="/tmp/nvim_${pid}.socket"
socket=$1

# The command you want to execute in Neovim
nvim_command="echo 'Hello from Neovim!'"

# Send the command to Neovim and capture the output
result=$(nvim --headless --server "$socket" --remote-expr "execute('$nvim_command')")

# Print the result
echo "Result from Neovim: $result"
