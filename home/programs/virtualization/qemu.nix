{pkgs, ...}: {
  home.packages = with pkgs; [
    qemu
    virt-manager
  ];
}
