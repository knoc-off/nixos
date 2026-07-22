# which-key: popup showing available keybinds after pressing a prefix.
#
# Group labels are NOT declared here -- each feature module contributes its own
# via the `whichKeyGroups` option (see which-key-groups.nix), so the group list
# self-assembles from whatever modules are imported.
{...}: {
  plugins.which-key = {
    enable = true;
    settings = {
      delay = 300;
      icons = {
        breadcrumb = ">>";
        separator = "->";
        group = "+";
      };
    };
  };
}
