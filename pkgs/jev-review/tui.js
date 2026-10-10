// /jev: a TUI dialog listing the edit hooks; Enter toggles one. Runs in the
// TUI, so no model turn. A separate module because opencode rejects a plugin
// that default-exports both `server` and `tui`. Listed in tui.json `plugin`
// (TUI plugins are not auto-discovered); ./index.js is the server plugin.
import { listHooks, setHook } from "./index.js";

export default {
  id: "jev-review.tui",
  tui: async (api) => {
    const open = async (current) => {
      let hooks;
      try {
        hooks = await listHooks();
      } catch (e) {
        return api.ui.toast({ variant: "error", message: `jev hooks: ${e.message}` });
      }
      if (!hooks.length) return api.ui.toast({ message: "No jev hooks in ~/scratch/jev-probes/hooks" });
      api.ui.dialog.replace(() =>
        api.ui.DialogSelect({
          title: "Jev hooks · enter toggles",
          current,
          options: hooks.map((k) => ({
            title: k.name,
            value: k.name,
            category: k.source,
            description: k.error ? `LOAD ERROR: ${k.error}` : k.meta.description,
            footer: k.on ? "✓ on" : "○ off",
            onSelect: async () => {
              try {
                await setHook(k.name, !k.on);
              } catch (e) {
                api.ui.toast({ variant: "error", message: e.message });
              }
              await open(k.name);
            },
          })),
        })
      );
    };
    api.keymap.registerLayer({
      commands: [{ name: "jev.hooks", title: "Jev hooks", category: "Jev", namespace: "palette", slashName: "jev", run: () => open() }],
    });
  },
};
