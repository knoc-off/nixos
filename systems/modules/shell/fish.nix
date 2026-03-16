{...}: {
  environment = {
    variables = {
      EDITOR = "vi";
      VISUAL = "vi";
    };

    shellAliases = {
      x = "xargs -I '{}' ";
    };
  };
  programs.fish = {
    enable = true;
  };
}
