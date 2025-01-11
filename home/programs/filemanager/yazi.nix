{pkgs, ...}: let
  #yazi-plugins = pkgs.fetchFromGitHub {
	#	owner = "yazi-rs";
	#	repo = "plugins";
	#	rev = "";
	#	hash = "sha256-...";
	#};
in {
	programs.yazi = {
		enable = true;
    #enableZshIntegration = true;
    #shellWrapperName = "y";

    #plugins = {
		#	chmod = "${yazi-plugins}/chmod.yazi";
		#	full-border = "${yazi-plugins}/full-border.yazi";
		#	max-preview = "${yazi-plugins}/max-preview.yazi";
		#	starship = pkgs.fetchFromGitHub {
		#		owner = "Rolv-Apneseth";
		#		repo = "starship.yazi";
		#		rev = "...";
		#		sha256 = "sha256-...";
		#	};
		#};

    #initLua = ''
		#	require("full-border"):setup()
		#	require("starship"):setup()
		#'';

	};

  home.packages = with pkgs; [
    p7zip-rar

  ];


}
