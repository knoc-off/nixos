{ inputs, config, lib, ... }:
{

  imports = [
      inputs.mywebsite.nixosModules.actix-webserver
  ];

}
