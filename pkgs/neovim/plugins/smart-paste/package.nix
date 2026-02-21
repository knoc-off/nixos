# smart-paste.nvim - Pasted code automatically lands at the correct indentation level
# https://github.com/nemanjamalesija/smart-paste.nvim
{
  vimUtils,
  fetchFromGitHub,
}:
vimUtils.buildVimPlugin {
  pname = "smart-paste-nvim";
  version = "unstable-2025-02-14";

  src = fetchFromGitHub {
    owner = "nemanjamalesija";
    repo = "smart-paste.nvim";
    rev = "64e77245e8caa97ed3c78996465d0087fba008bf";
    hash = "sha256-Abf+VC1jlJsQUtnYLJj7VUvXOi21WTH46rEEU4w6Hm8=";
  };

  meta = {
    description = "Pasted code automatically lands at the correct indentation level";
    homepage = "https://github.com/nemanjamalesija/smart-paste.nvim";
  };
}
