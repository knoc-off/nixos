{ pkgs, self, modules ? null }:

let

  inherit (self.packages.${pkgs.system}) writeNuScript;
  # Neovim module
  neovimModule = "${pkgs.writeShellScriptBin "module-neovim" ''
    set -euo pipefail

    dir="''${1:-}"
    if [[ -z "$dir" ]]; then
        echo "Usage: $0 <direction>"
        exit 1
    fi

    # Direction mappings for Neovim
    declare -A dir_map=(
        ["l"]="h" ["r"]="l" ["u"]="k" ["d"]="j"
    )
    declare -A cmd_map=(
        ["l"]="<C-w>h" ["r"]="<C-w>l" ["u"]="<C-w>k" ["d"]="<C-w>j"
    )

    # Validate the direction
    if [[ -z "''${dir_map[$dir]:-}" ]]; then
        exit 1
    fi

    direction="''${dir_map[$dir]}"

    # Get active window title
    title=$(hyprctl activewindow -j | jq -r '.title')

    # Extract Neovim PID from window title (expects format '<title> - <PID>')
    if [[ "$title" =~ [[:space:]]-[[:space:]]([0-9]+)$ ]]; then
        nvim_pid="''${BASH_REMATCH[1]}"
    else
        # No Neovim PID found
        exit 1
    fi

    # Construct Neovim socket path
    nvim_socket="/tmp/nvim_''${nvim_pid}.socket"

    # Check if Neovim socket exists
    if [[ ! -S "$nvim_socket" ]]; then
        exit 1
    fi

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

    if [[ "''$result" != "1" ]]; then
        exit 1
    fi

    # Send the focus command to Neovim
    nvim --headless --server "$nvim_socket" --remote-send "''${cmd_map[$dir]}"

    exit 0
  ''}/bin/module-neovim";

  # Placeholder for the Kitty module
  # Replace this with actual logic when available
  kittyModule = "${pkgs.writeShellScriptBin "module-kitty" ''
    set -euo pipefail

    # Get pid of active window
    active_window_pid=$(hyprctl activewindow -j | jq -r '.pid')

    # Construct Kitty socket path
    kitty_socket="/tmp/kitty-$active_window_pid.socket"

    # Check if Kitty socket exists
    if [[ ! -S "$kitty_socket" ]]; then
        exit 1
    fi

    # Execute Kitty command to move focus in the given direction
    # direction map to turn l > left, r > right, u > up, d > down
    case "''${1:-}" in
      l) direction="left" ;;
      r) direction="right" ;;
      u) direction="top" ;;
      d) direction="bottom" ;;
      *) exit 1 ;;
    esac

    kitten @ --to "unix:$kitty_socket" focus-window --match neighbor:"$direction"

    # return last command status
    #return $?

    if [[ $? -eq 0 ]]; then
        exit 0
    fi

    exit 1  # Currently always fails; replace with actual logic
  ''}/bin/module-kitty";

  # This script defines a function `focusShiftContained` that moves the focus of the active window
  # in a specified direction (left, right, up, or down) while ensuring that the window does not move
  # beyond the screen boundaries.
  #
  # Parameters:
  # - screenx: The width of the screen.
  # - screeny: The height of the screen.
  # - direction: The direction to move the focus. It can be one of the following characters:
  #   - 'l' for left
  #   - 'r' for right
  #   - 'u' for up
  #   - 'd' for down
  #
  # The script first retrieves the active window's position and size using `hyprctl`. It then checks
  # if moving in the specified direction would cause the window to go out of the screen boundaries.
  # If so, the script exits without moving the focus. Otherwise, it dispatches the move focus command.
  #
  # this only works if the windows are tiled, if they are floating then it will not work.
  focusShiftContained = "${writeNuScript "focusShiftContained" ''
    # Main function to shift focus of the active window based on the given direction.
    # If the active window is at the edge of the screen, it focuses on the closest floating window.
    # Otherwise, it moves the focus in the given direction.
    #
    # Parameters:
    # - screenx: int - The width of the screen.
    # - screeny: int - The height of the screen.
    # - direction: string - The direction to move the focus ('l', 'r', 'u', 'd').
    def main [direction: string] {
      # 2256 1504
      let screenx = 2256
      let screeny = 1504
      let active_window = (hyprctl activewindow -j | from json)
      let pos = $active_window.at
      let size = $active_window.size

      def check_bounds [pos: list<int>, size: list<int>, screenx: int, screeny: int, direction: string] {
        match $direction {
          "l" => ($pos.0 == 0),
          "r" => ($pos.0 + $size.0 == $screenx),
          "u" => ($pos.1 == 0),
          "d" => ($pos.1 + $size.1 == $screeny),
          _ => false
        }
      }

      if (check_bounds $pos $size $screenx $screeny $direction) {
        let floating_windows = (hyprctl clients -j | from json | where floating)
        let activeworkspace = (hyprctl activeworkspace -j | from json).id
        let floating_windows_on_active_workspace = $floating_windows | where workspace.id == $activeworkspace

        if (($floating_windows_on_active_workspace | length) == 0) {
          return
        }

        def get_center [pos: list<int>, size: list<int>] {
          [($pos.0 + ($size.0 / 2)), ($pos.1 + ($size.1 / 2))]
        }

        let active_window_center = get_center $pos $size
        let closest_window = $floating_windows_on_active_workspace | each {|e|
          let window_center = get_center $e.at $e.size
          let distance = (($active_window_center.0 - $window_center.0) | math abs) + (($active_window_center.1 - $window_center.1) | math abs)
          {window: $e, distance: $distance}
        } | sort-by distance | first | get window

        hyprctl dispatch focuswindow ("address:" + $closest_window.address)
      } else {
        hyprctl dispatch movefocus $direction
      }
    }
  ''}/bin/focusShiftContained";

  # Default modules list if none provided
  modus = [ neovimModule kittyModule focusShiftContained ];

  # if modules is not null, use it instead
  module = if modules != null then modules else modus;

in
pkgs.writeShellScriptBin "fancyfocus" ''
  set -euo pipefail

  # Ensure a direction argument is provided
  dir="''${1:-}"
  if [[ -z "$dir" ]]; then
      echo "Usage: $0 <direction>"
      exit 1
  fi

  # List of modules
  modules=( ${pkgs.lib.concatStringsSep " " module} )

  # Iterate over modules
  for module in "''${modules[@]}"; do
      if "$module" "$dir"; then
          exit 0
      fi
  done

  # If we reach here, none of the modules succeeded
  echo "Failed to move focus"
  exit 1
''
