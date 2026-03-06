{...}: {
  environment.variables = {
    EDITOR = "vi";
    VISUAL = "vi";
  };

  programs.fish = {
    enable = true;
  };
}
