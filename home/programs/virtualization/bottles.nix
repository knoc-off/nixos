{pkgs, ...}: {
  # install the bottles-unwrapped package, add an overlay before
  # installing the package
  home.packages = with pkgs; [
    bottles-unwrapped
  ];
}
