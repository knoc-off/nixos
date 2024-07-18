{
  name = "dark";
  author = "knoff";
  base00 = "131415"; # 131415
  base01 = "1a1c1d"; # 1a1c1d
  base02 = "242628"; # 242628
  base03 = "393b3c"; # 393b3c
  base04 = "adb5bd"; # adb5bd
  base05 = "ced4da"; # ced4da
  base06 = "dee2e6"; # dee2e6
  base07 = "f8f9fa"; # f8f9fa
  base08 = "F07178"; # F07178
  base09 = "FF8F40"; # FF8F40
  base0A = "FFB454"; # FFB454
  base0B = "B8CC52"; # B8CC52
  base0C = "95E6CB"; # 95E6CB
  base0D = "59C2FF"; # 59C2FF
  base0E = "D2A6FF"; # D2A6FF
  base0F = "E6B673"; # E6B673

  hp = "#FF00FF";
  # these colors are not used in the theme, but are used to find what
  # change is made when you change a color in the theme.
  # they are all unique colors, And distinct from each other.
  # they are also all bright colors, so they are easy to see.
  # follows roygbiv, and then some.
  idk00 = "FF0000"; # FF0000
  idk01 = "FF8000"; # FF8000
  idk02 = "FFFF00"; # FFFF00
  idk03 = "80FF00"; # 80FF00
  idk04 = "00FF00"; # 00FF00
  idk05 = "00FF80"; # 00FF80
  idk06 = "00FFFF"; # 00FFFF
  idk07 = "0080FF"; # 0080FF
  idk08 = "0000FF"; # 0000FF
  idk09 = "8000FF"; # 8000FF
  idk0A = "FF00FF"; # FF00FF
  idk0B = "FF0080"; # FF0080

  # These should all go from light to dark

  gray00 = "a3a4a5"; # a3a4a5
  gray01 = "88898a"; # 88898a
  gray02 = "6e6f70"; # 6e6f70
  gray03 = "565758"; # 565758
  gray04 = "3e3f40"; # 3e3f40
  gray05 = "28292a"; # 28292a
  gray06 = "131415"; # 131415

  white00 = "f8f9fa"; # f8f9fa
  white01 = "e9ecef"; # e9ecef
  white02 = "dee2e6"; # dee2e6
  white03 = "ced4da"; # ced4da
  white04 = "adb5bd"; # adb5bd
  white05 = "6c757d"; # 6c757d

  #white01 = "#e6e6e6";
  #white03 = "#b3b3b3";
  #white05 = "#808080";
  #white07 = "#4d4d4d";
  #white09 = "#1a1a1a";
  #white10 = "#000000";

  # Red
  red00 = "fe7272"; # fe7272
  red01 = "e95a58"; # e95a58
  red02 = "d44240"; # d44240
  red03 = "bb2f2d"; # bb2f2d
  red04 = "9e211f"; # 9e211f
  red05 = "821111"; # 821111

  # Orange
  orange00 = "FF8C00"; # FF8C00
  orange01 = "FF6B00"; # FF6B00
  orange02 = "E85400"; # E85400
  orange03 = "D9480F"; # D9480F

  # Brown
  brown00 = "A3685A"; # A3685A
  brown01 = "854442"; # 854442

  # Yellow
  yellow00 = "FFD900"; # ffd900
  yellow01 = "E6C000"; # E6C000
  yellow02 = "CCB200"; # CCB200
  yellow03 = "B39800"; # B39800
  yellow04 = "997800"; # 997800
  yellow05 = "7F5F00"; # 7F5F00

  # Green
  green00 = "B5BD68"; # B5BD68
  green01 = "768948"; # 768948
  green02 = "3C5340"; # 3C5340
  green03 = "324635"; # 324635
  green04 = "283C2C"; # 283C2C
  green05 = "1E2F23"; # 1E2F23

  # Cyan
  cyan00 = "C2E2DB"; # C2E2DB
  cyan01 = "A8D9D2"; # A8D9D2
  cyan02 = "8FCFC9"; # 8FCFC9
  cyan03 = "75C6C1"; # 75C6C1
  cyan04 = "3D9290"; # 3D9290
  cyan05 = "29807D"; # 29807D

  # Blue
  blue00 = "81A2BE"; # 81A2BE
  blue01 = "5C81A6"; # 5C81A6
  blue02 = "4F6D8C"; # 4F6D8C
  blue03 = "3E5C7E"; # 3E5C7E
  blue04 = "2E4A71"; # 2E4A71
  blue05 = "1E3867"; # 1E3867

  # Purple
  purple00 = "B294BB"; # B294BB
  purple01 = "8F6C97"; # 8F6C97
}

#{
#
#  #bg = "#1a1b26";
#  #bg_dark = "#16161e";
#  #bg_highlight = "#292e42";
#  #blue = "#7aa2f7";
#  #blue0 = "#3d59a1";
#  #blue1 = "#2ac3de";
#  #blue2 = "#0db9d7";
#  #blue5 = "#89ddff";
#  #blue6 = "#b4f9f8";
#  #blue7 = "#394b70";
#  #comment = "#565f89";
#  #cyan = "#7dcfff";
#  #dark3 = "#545c7e";
#  #dark5 = "#737aa2";
#  #fg = "#c0caf5";
#  #fg_dark = "#a9b1d6";
#  #fg_gutter = "#3b4261";
#  #green = "#9ece6a";
#  #green1 = "#73daca";
#  #green2 = "#41a6b5";
#  #magenta = "#bb9af7";
#  #magenta2 = "#ff007c";
#  #orange = "#ff9e64";
#  #purple = "#9d7cd8";
#  #red = "#f7768e";
#  #red1 = "#db4b4b";
#  #teal = "#1abc9c";
#  #terminal_black = "#414868";
#  #yellow = "#e0af68";
#  #add = "#449dab";
#  #change = "#6183bb";
#  #delete = "#914c54";
#
#  colors = rec {
#    bg_darker = "#131415";
#    bg_dark = "#1a1c1d";
#    bg = "#242628";
#    bg_light = "#393b3c";
#    fg_darker = "#adb5bd";
#    fg_dark = "#ced4da";
#    fg = "#dee2e6";
#    fg_light = "#f8f9fa";
#    base08 = "#F07178";
#    base09 = "#FF8F40";
#    base0A = "#FFB454";
#    base0B = "#B8CC52";
#    base0C = "#95E6CB";
#    base0D = "#59C2FF";
#    base0E = "#D2A6FF";
#    base0F = "#E6B673";
#
#    idk00 = "#FF0000";
#    idk01 = "#FF8000";
#    idk02 = "#FFFF00";
#    idk03 = "#80FF00";
#    idk04 = "#00FF00";
#    idk05 = "#00FF80";
#    idk06 = "#00FFFF";
#    idk07 = "#0080FF";
#    idk08 = "#0000FF";
#    idk09 = "#8000FF";
#    idk0A = "#FF00FF";
#    idk0B = "#FF0080";
#
#    gray = gray00;
#    gray00 = "#a3a4a5";
#    gray01 = "#88898a";
#    gray02 = "#6e6f70";
#    gray03 = "#565758";
#    gray04 = "#3e3f40";
#    gray05 = "#28292a";
#    gray06 = "#131415";
#
#    white = white00;
#    white00 = "#f8f9fa";
#    white01 = "#e9ecef";
#    white02 = "#dee2e6";
#    white03 = "#ced4da";
#    white04 = "#adb5bd";
#    white05 = "#6c757d";
#
#    red = red00;
#    red00 = "#fe7272";
#    red01 = "#e95a58";
#    red02 = "#d44240";
#    red03 = "#bb2f2d";
#    red04 = "#9e211f";
#    red05 = "#821111";
#
#    orange00 = "#FF8C00";
#    orange01 = "#FF6B00";
#    orange02 = "#E85400";
#    orange03 = "#D9480F";
#
#    brown00 = "#A3685A";
#    brown01 = "#854442";
#
#    yellow00 = "#FFD900";
#    yellow01 = "#E6C000";
#    yellow02 = "#CCB200";
#    yellow03 = "#B39800";
#    yellow04 = "#997800";
#    yellow05 = "#7F5F00";
#
#    green00 = "#B5BD68";
#    green01 = "#768948";
#    green02 = "#3C5340";
#    green03 = "#324635";
#    green04 = "#283C2C";
#    green05 = "#1E2F23";
#
#    cyan00 = "#C2E2DB";
#    cyan01 = "#A8D9D2";
#    cyan02 = "#8FCFC9";
#    cyan03 = "#75C6C1";
#    cyan04 = "#3D9290";
#    cyan05 = "#29807D";
#
#    blue00 = "#81A2BE";
#    blue01 = "#5C81A6";
#    blue02 = "#4F6D8C";
#    blue03 = "#3E5C7E";
#    blue04 = "#2E4A71";
#    blue05 = "#1E3867";
#
#    purple00 = "#B294BB";
#    purple01 = "#8F6C97";
#  };
#  #000000
#  #0db9d7
#  #16161e
#  #1a1b26
#  #1abc9c
#  #1e2030
#  #1f2335
#  #222436
#  #24283b
#  #282833
#  #292e42
#  #2ac3de
#  #2d3149
#  #2f334d
#  #363b54
#  #394b70
#  #3b415c
#  #3b4261
#  #3d59a1
#  #3e68d7
#  #414868
#  #41a6b5
#  #444a73
#  #444b6a
#  #449dab
#  #4e5579
#  #4E5579
#  #4f4f5e
#  #4fd6be
#  #545c7e
#  #565f89
#  #6183bb
#  #61bdf2
#  #636da6
#  #65bcff
#  #6d91de
#  #737aa2
#  #73daca
#  #747ca1
#  #7aa2f7
#  #7ca1f2
#  #7dcfff
#  #7DCFFF
#  #828bb8
#  #82aaff
#  #86e1fc
#  #89ddff
#  #914c54
#  #9aa5ce
#  #9abdf5
#  #9D599D
#  #9d7cd8
#  #9ece6a
#  #a9b1d6
#  #b267e6
#  #b4f9f8
#  #b8db87
#  #ba3c97
#  #bb9af7
#  #c099ff
#  #c0caf5
#  #c0cefc
#  #c3e88d
#  #c53b53
#  #c8d3f5
#  #db4b4b
#  #DBC08A
#  #e0af68
#  #e26a75
#  #f7768e
#  #fc7b7b
#  #fca7ea
#  #ff0000
#  #ff007c
#  #ff757f
#  #ff966c
#  #ff9e64
#  #ffa300
#  #ffc777
#  #ffdb69
#  #ffffff
#}
