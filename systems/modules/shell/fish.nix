{pkgs, ...}: {
  environment = {
    variables = {
      EDITOR = "vi";
      VISUAL = "vi";
    };

    shellAliases = {
      x = "xargs ";
      xi = "xargs -I '{}' ";
    };
  };
  programs.fish = {
    enable = true;
    interactiveShellInit = ''
      stty -echoctl

      function __auto_bg --on-event fish_prompt
          bg 2>/dev/null
      end

      function __fish_ctrl_z
          test -z (commandline); and test (count (jobs)) -gt 0; and fg 2>/dev/null; and commandline -f repaint
      end
      bind \cz __fish_ctrl_z
    '';
  };
}
