{lib, ...}:
{
  disko.devices = {
    disk = {
      vdb = {
        device = lib.mkDefault "/dev/vdb";
        type = "disk";
        content = {
          type = "gpt";
          partitions = {
            ESP = {
              size = "500M";
              type = "EF00";
              content = {
                type = "filesystem";
                format = "vfat";
                mountpoint = "/boot";
              };
            };
            root = {
              end = lib.mkDefault "-12G";
              content = {
                type = "filesystem";
                format = "ext4";
                mountpoint = "/";
              };
            };
            plainSwap = { # i dont think the name here matters?
              size = "100%";
              content = { # this is where it gets declared?
                type = "swap";
                resumeDevice = true; # resume from hiberation from this device
              };
            };
          };
        };
      };
    };
  };
}
