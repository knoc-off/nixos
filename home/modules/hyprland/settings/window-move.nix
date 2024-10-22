{pkgs, hyprfocuscommand ? "hyprctl dispatch movefocus" }:
let


in
pkgs.writeShellScriptBin "fancyfocus" ''
  set -euo pipefail

  # Direction mappings for Neovim and Hyprland
  declare -A dir_map=(
      ["left"]="h" ["right"]="l" ["up"]="k" ["down"]="j"
  )
  declare -A hypr_short=(
      ["left"]="l" ["right"]="r" ["up"]="u" ["down"]="d"
  )
  declare -A cmd_map=(
      ["left"]="<C-w>h" ["right"]="<C-w>l" ["up"]="<C-w>k" ["down"]="<C-w>j"
  )

  # Ensure a direction argument is provided
  dir="''${1:-}"
  if [[ -z "$dir" ]]; then
      echo "Usage: $0 <direction>"
      exit 1
  fi

  # Validate the direction
  if [[ -z "''${dir_map[$dir]:-}" ]]; then
      echo "Invalid direction: $dir"
      exit 1
  fi

  # Function to fallback to Hyprland movefocus command
  movefocus() { ${hyprfocuscommand} "''${hypr_short[$dir]}"; }

  # Get active window title
  title=$(hyprctl activewindow -j | jq -r '.title')

  #date
  echo "date: $(date)" >> /log/fancyfocus/log.txt

  echo "title: $title" >> /log/fancyfocus/log.txt
  echo "dir: $dir" >> /log/fancyfocus/log.txt

  # Extract Neovim PID from window title (expects format '<title> - <PID>')
  if [[ "$title" =~ [[:space:]]-[[:space:]]([0-9]+)$ ]]; then
      nvim_pid="''${BASH_REMATCH[1]}"
  else
      # No Neovim PID found; fallback to Hyprland
      echo "no pid" >> /log/fancyfocus/log.txt
      movefocus
      exit 0
  fi

  echo "pid: $nvim_pid" >> /log/fancyfocus/log.txt
  # Construct Neovim socket path
  nvim_socket="/tmp/nvim_''${nvim_pid}.socket"

  echo "socket: $nvim_socket" >> /log/fancyfocus/log.txt
  # Check if Neovim socket exists
  if [[ ! -S "$nvim_socket" ]]; then
      # Socket doesn't exist; fallback to Hyprland
      movefocus
      exit 0
  fi


  direction="''${dir_map[$dir]}"

  # Lua code to check if Neovim can move focus in the given direction
  lua_code="
    local dir='$direction'
    local cur_win=vim.api.nvim_get_current_win()
    vim.cmd('wincmd '..dir)
    if cur_win~=vim.api.nvim_get_current_win() then
        vim.cmd('wincmd '..({h='l',j='k',k='j',l='h'})[dir])
        return 1
    else return 0 end
  "


  # Escape single quotes in the Lua code
  escaped_lua_code=$(printf '%s' "$lua_code" | sed "s/'/'''/g")

  # Execute Lua code in Neovim and get the result
  result=$(nvim --headless --server "$nvim_socket" --remote-expr "ExecuteLua('$escaped_lua_code')")

  echo "result: $result" >> /log/fancyfocus/log.txt

  # If Neovim cannot move focus, fallback to Hyprland
  if [[ "''$result" != "1" ]]; then
      movefocus
      exit 0
  fi

  # Send the focus command to Neovim
  nvim --headless --server "$nvim_socket" --remote-send "''${cmd_map[$dir]}"
''
