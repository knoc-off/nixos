{pkgs, ...}:
{
  extraPlugins =  [ pkgs.vimExtraPlugins.focus-nvim ];


  # Then add the configuration
  extraConfigLua = ''
    require('focus').setup({
      enable = true,
      commands = true,
      autoresize = {
        enable = true,
        width = 0,
        height = 0,
        minwidth = 0,
        minheight = 0,
        height_quickfix = 10,
      },
      split = {
        bufnew = false,
        tmux = false,
      },
      ui = {
        number = false,
        relativenumber = false,
        hybridnumber = false,
        absolutenumber_unfocussed = false,
        cursorline = true,
        cursorcolumn = false,
        colorcolumn = {
          enable = false,
          list = '+1',
        },
        signcolumn = true,
        winhighlight = false,
      }
    })
  '';


  plugins.mini = {
    modules = {
      animate = {
        cursor = {
          enable = false;
        };
        resize = {
          enable = true;
          timing = {
            __raw = ''
              function(_, n)
                return 200 / n
              end
            '';
          };
          subresize = {
            __raw = ''
              (function()
                local function ease_out(from, to, coef)
                  return math.floor(from + (to - from) * (1 - (1 - coef) ^ 2))
                end

                return function(sizes_from, sizes_to)
                  if #vim.tbl_keys(sizes_from) == 1 then
                    return {}
                  end

                  local n_steps = 0
                  for win_id, dims_from in pairs(sizes_from) do
                    local height_absdiff = math.abs(sizes_to[win_id].height - dims_from.height)
                    local width_absdiff = math.abs(sizes_to[win_id].width - dims_from.width)
                    n_steps = math.max(n_steps, height_absdiff, width_absdiff)
                  end
                  if n_steps <= 1 then
                    return {}
                  end

                  local res = {}
                  for i = 1, n_steps do
                    local coef = i / n_steps
                    local sub_res = {}
                    for win_id, dims_from in pairs(sizes_from) do
                      sub_res[win_id] = {
                        height = ease_out(dims_from.height, sizes_to[win_id].height, coef),
                        width = ease_out(dims_from.width, sizes_to[win_id].width, coef),
                      }
                    end
                    res[i] = sub_res
                  end

                  return res
                end
              end)()
            '';
          };
        };
        scroll = {
          enable = true;
        };
        open = {
          enable = false;
        };
        close = {
          enable = true;
          winconfig = {
            __raw = "require('mini.animate').gen_winconfig.wipe()";
          };
          winblend = {
            __raw = "require('mini.animate').gen_winblend.linear({ from = 40, to = 100 })";
          };
          timing = {
            __raw = "require('mini.animate').gen_timing.quartic({ easing = 'out', duration = 400, unit = 'total' })";
          };
        };
      };
    };
  };
}






