{ pkgs, config, libs, ...}:
{
  home.packages = with pkgs; [
    qemu
    virt-manager
  ];


}
