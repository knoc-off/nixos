{
  config,
  self,
  ...
}: {
  imports = [self.nixosModules.services.upvote-rss];

  sops.secrets."services/upvote-rss/env" = {
    owner = config.services.upvote-rss.user;
    group = config.services.upvote-rss.group;
    mode = "0400";
  };

  services.upvote-rss = {
    enable = true;

    nginx = {
      enable = true;
      domain = "upvote.niko.ink";
    };

    redis.createLocally = true;

    environmentFile = config.sops.secrets."services/upvote-rss/env".path;
  };
}
