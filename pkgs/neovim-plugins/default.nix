{ vimUtils, lua }:
{
  overlay = self: super: {
    window-manager = vimUtils.buildVimPlugin {
      pname = "windowServer";
      version = "0.1.0";
      src = ./window-server;
    };
  };
}

