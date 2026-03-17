{...}: {
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
  };
}
