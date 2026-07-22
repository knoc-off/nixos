# Self-assembling which-key group registry.
#
# Feature modules contribute their own <leader>-namespace group labels via
# `whichKeyGroups`, instead of maintaining one central list. This makes the
# config self-maintaining: remove a module's import and its group disappears.
#
# Because `listOf` concatenates across modules, several modules may declare the
# SAME group (e.g. git.nix, git-state.nix and diffview.nix all declaring
# <leader>g = "Git"). The sink below deduplicates by the group's key, so
# redefining a shared group in each owning module is safe and collapses to one
# entry (last definition wins on the label, which is fine for identical labels).
{lib, config, ...}: {
  options.whichKeyGroups = lib.mkOption {
    type = with lib.types; listOf attrs;
    default = [];
    description = ''
      which-key group specs contributed by feature modules. Merged (and
      deduplicated by key) into plugins.which-key.settings.spec.
    '';
  };

  config.plugins.which-key.settings.spec = lib.mkForce (
    let
      # Deduplicate by the group's `__unkeyed` key: build an attrset keyed by it
      # so repeated declarations of the same group collapse to a single entry.
      byKey = lib.foldl' (acc: g: acc // {${g.__unkeyed} = g;}) {} config.whichKeyGroups;
    in
      lib.attrValues byKey
  );
}
