{
  inputs,
  lib,
  pkgs,
  theme,
  ...
}: let
  # Unified function to configure Noctalia plugins from flake inputs
  # Returns: { configFiles, settings } - derived from a single plugin list
  mkNoctaliaPlugins = plugins: {
    # xdg.configFile entries (symlinks for all plugin files)
    configFiles = lib.foldl' (acc: plugin:
      acc
      // (let
        pluginSrc = "${plugin.src}/${plugin.name}";
        pluginFiles = builtins.readDir pluginSrc;
      in
        lib.mapAttrs' (fileName: _: {
          name = "noctalia/plugins/${plugin.name}/${fileName}";
          value.source = "${pluginSrc}/${fileName}";
        })
        pluginFiles)) {}
    plugins;

    settings = lib.listToAttrs (map (plugin: {
        name = plugin.name;
        value = plugin.settings or {};
      })
      plugins);
  };

  # Shared opacity for all noctalia layer surfaces.
  # Lower = more glass visible through the surface. Must be > 0 for hyprglass to activate.
  layerOpacity = 0.55;

  noctaliaPlugins = mkNoctaliaPlugins [
    {
      name = "weekly-calendar";
      src = inputs.noctalia-plugins;
      settings = {};
    }
    {
      name = "clipper";
      src = inputs.noctalia-plugins;
      settings = {
        enableTodoIntegration = false;
        pincardsEnabled = true;
        notecardsEnabled = true;
        showCloseButton = true;
      };
    }
    {
      name = "screen-shot";
      src = pkgs.callPackage ../../pkgs/noctalia/screen-shot/default.nix {};
      settings = {};
    }
    {
      name = "audio-recorder";
      src = pkgs.callPackage ../../pkgs/noctalia/audio-recorder/default.nix {};
      settings = {};
    }
    {
      name = "bluetooth";
      src = pkgs.callPackage ../../pkgs/noctalia/bluetooth/default.nix {};
      settings = {};
    }
  ];
  initialColorsJson = builtins.toJSON {
    mSurface = "#${theme.dark.base00}";
    mSurfaceVariant = "#${theme.dark.base01}";
    mHover = "#${theme.dark.base02}";
    mOutline = "#${theme.dark.base03}";
    mOnSurfaceVariant = "#${theme.dark.base04}";
    mOnSurface = "#${theme.dark.base05}";
    mOnHover = "#${theme.dark.base06}";
    mPrimary = "#${theme.dark.base0C}";
    mSecondary = "#${theme.dark.base0D}";
    mTertiary = "#${theme.dark.base0E}";
    mError = "#${theme.dark.base08}";
    mOnPrimary = "#${theme.dark.base00}";
    mOnSecondary = "#${theme.dark.base00}";
    mOnTertiary = "#${theme.dark.base00}";
    mOnError = "#${theme.dark.base00}";
    mShadow = "#000000";
  };
in {
  imports = [inputs.noctalia.homeModules.default];

  # Seed a mutable colors.json so noctalia can overwrite it at runtime
  # (the noctalia module's managed symlink is disabled below)
  home.activation.noctaliaColors = lib.hm.dag.entryAfter ["writeBoundary"] ''
    colors_file="$HOME/.config/noctalia/colors.json"
    mkdir -p "$(dirname "$colors_file")"
    if [ ! -f "$colors_file" ] || [ -L "$colors_file" ]; then
      rm -f "$colors_file"
      echo '${initialColorsJson}' > "$colors_file"
    fi
  '';

  home.packages = with pkgs; [
    ffmpeg-full
    hicolor-icon-theme
    papirus-icon-theme
    wl-clipboard # clipboard (clipper + screen-shot)
    grim # screenshot capture (screen-shot)
    slurp # region selection (screen-shot)
    wl-screenrec # region recorder (screen-shot)
    dragon-drop # drag-and-drop after recording (screen-shot)
  ];

  services.cliphist.enable = true;

  xdg.configFile =
    {
      # Make colors.json mutable so noctalia can overwrite it at runtime
      # (needed for useWallpaperColors to regenerate the palette on wallpaper change)
      "noctalia/colors.json".enable = lib.mkForce false;
    }
    // noctaliaPlugins.configFiles;

  # Provide fallback icon for ActiveWindow when no app is focused
  xdg.dataFile."icons/hicolor/scalable/apps/user-desktop.svg".text = ''
    <svg xmlns="http://www.w3.org/2000/svg" width="24" height="24" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2" stroke-linecap="round" stroke-linejoin="round">
      <rect x="3" y="4" width="18" height="16" rx="2" ry="2" />
      <line x1="3" y1="8" x2="21" y2="8" />
      <line x1="7" y1="6" x2="7.01" y2="6" />
      <line x1="11" y1="6" x2="11.01" y2="6" />
    </svg>
  '';

  programs.noctalia-shell = {
    enable = lib.mkDefault true;
    systemd.enable = lib.mkDefault true;
    package = lib.mkForce (inputs.noctalia.packages.${pkgs.stdenv.hostPlatform.system}.default.override {
      calendarSupport = true;
    });

    # Material 3 colors derived from your base16 theme
    colors = {
      mSurface = "#${theme.dark.base00}"; # Background
      mSurfaceVariant = "#${theme.dark.base01}"; # Alt background
      mHover = "#${theme.dark.base02}"; # Hover state bg
      mOutline = "#${theme.dark.base03}"; # Borders
      mOnSurfaceVariant = "#${theme.dark.base04}"; # Dim text
      mOnSurface = "#${theme.dark.base05}"; # Main text
      mOnHover = "#${theme.dark.base06}"; # Hover text
      mPrimary = "#${theme.dark.base0C}"; # Blue - primary accent
      mSecondary = "#${theme.dark.base0D}"; # Cyan - secondary accent
      mTertiary = "#${theme.dark.base0E}"; # Purple - tertiary accent
      mError = "#${theme.dark.base08}"; # Red - errors
      mOnPrimary = "#${theme.dark.base00}"; # Text on primary
      mOnSecondary = "#${theme.dark.base00}"; # Text on secondary
      mOnTertiary = "#${theme.dark.base00}"; # Text on tertiary
      mOnError = "#${theme.dark.base00}"; # Text on error
      mShadow = "#000000"; # Shadow color
    };

    pluginSettings = noctaliaPlugins.settings;

    settings = lib.mkDefault {
      settingsVersion = 0;
      bar = {
        position = "left";
        barType = "simple";
        monitors = [];
        density = "spacious";
        showOutline = false;
        showCapsule = true;
        capsuleOpacity = layerOpacity;
        capsuleColorKey = "none";
        backgroundOpacity = layerOpacity;
        useSeparateOpacity = true;
        floating = false;
        marginVertical = 4;
        marginHorizontal = 4;
        frameThickness = 8;
        frameRadius = 12;
        outerCorners = true;
        hideOnOverview = false;
        displayMode = "always_visible";
        autoHideDelay = 50;
        autoShowDelay = 150;
        widgets = {
          left = [
            {
              id = "Launcher";
            }
            {
              id = "Clock";
            }
            {
              id = "SystemMonitor";
            }
            {
              id = "ActiveWindow";
            }
            {
              id = "MediaMini";
            }
          ];
          center = [
            {
              id = "Workspace";
            }
          ];
          right = [
            {
              id = "Tray";
            }
            {
              id = "plugin:screen-shot";
            }
            {
              id = "plugin:clipper";
            }
            {
              id = "plugin:weekly-calendar";
            }
            {
              id = "plugin:audio-recorder";
            }
            {
              id = "plugin:bluetooth";
            }
            {
              id = "NotificationHistory";
            }
            {
              id = "Battery";
            }
            {
              id = "Volume";
            }
            {
              id = "Brightness";
            }
            {
              id = "ControlCenter";
            }
          ];
        };
        screenOverrides = [
          {
            name = "DP-4";
            widgets = {
              left = [
                {id = "Launcher";}
                {id = "ActiveWindow";}
              ];
              center = [
                {id = "Workspace";}
              ];
              right = [
                {id = "Tray";}
                {id = "Volume";}
                {id = "ControlCenter";}
              ];
            };
          }
        ];
      };
      general = {
        avatarImage = "";
        dimmerOpacity = 0.0;
        showScreenCorners = false;
        forceBlackScreenCorners = false;
        scaleRatio = 1;
        radiusRatio = 1;
        iRadiusRatio = 1;
        boxRadiusRatio = 1;
        screenRadiusRatio = 1;
        animationSpeed = 1;
        animationDisabled = false;
        compactLockScreen = false;
        lockScreenAnimations = true;
        lockScreenBlur = 0.6;
        lockScreenTint = 0.3;
        lockScreenMonitors = ["eDP-1"];
        lockOnSuspend = true;
        showSessionButtonsOnLockScreen = true;
        showHibernateOnLockScreen = false;
        enableShadows = false;
        shadowDirection = "left";
        shadowOffsetX = 0;
        shadowOffsetY = -3;
        language = "";
        allowPanelsOnScreenWithoutBar = true;
        showChangelogOnStartup = true;
        telemetryEnabled = false;
        enableLockScreenCountdown = true;
        lockScreenCountdownDuration = 10000;
        autoStartAuth = false;
        allowPasswordWithFprintd = true;
        clockStyle = "custom";
        clockFormat = "hh\nmm";
      };
      ui = {
        fontDefault = "";
        fontFixed = "";
        fontDefaultScale = 1;
        fontFixedScale = 1;
        tooltipsEnabled = true;
        panelBackgroundOpacity = layerOpacity;
        panelsAttachedToBar = true;
        settingsPanelMode = "attached";
        wifiDetailsViewMode = "grid";
        bluetoothDetailsViewMode = "grid";
        networkPanelView = "wifi";
        bluetoothHideUnnamedDevices = false;
        boxBorderEnabled = false;
      };
      location = {
        name = "Berlin";
        weatherEnabled = true;
        weatherShowEffects = true;
        useFahrenheit = false;
        use12hourFormat = false;
        showWeekNumberInCalendar = false;
        showCalendarEvents = true;
        showCalendarWeather = true;
        analogClockInCalendar = false;
        firstDayOfWeek = -1;
        hideWeatherTimezone = false;
        hideWeatherCityName = false;
      };
      calendar = {
        cards = [
          {
            enabled = true;
            id = "calendar-header-card";
          }
          {
            enabled = true;
            id = "calendar-month-card";
          }
          {
            enabled = true;
            id = "weather-card";
          }
        ];
      };
      wallpaper = {
        enabled = true;
        overviewEnabled = false;
        directory = "";
        monitorDirectories = [];
        enableMultiMonitorDirectories = false;
        showHiddenFiles = false;
        viewMode = "single";
        setWallpaperOnAllMonitors = false;
        fillMode = "crop";
        fillColor = "#000000";
        useSolidColor = false;
        solidColor = "#1a1a2e";
        automationEnabled = false;
        wallpaperChangeMode = "random";
        randomIntervalSec = 300;
        transitionDuration = 50;
        transitionType = "wipe";
        transitionEdgeSmoothness = 0.25;
        panelPosition = "follow_bar";
        hideWallpaperFilenames = false;
        useWallhaven = false;
        wallhavenQuery = "";
        wallhavenSorting = "relevance";
        wallhavenOrder = "desc";
        wallhavenCategories = "111";
        wallhavenPurity = "100";
        wallhavenRatios = "";
        wallhavenApiKey = "";
        wallhavenResolutionMode = "atleast";
        wallhavenResolutionWidth = "";
        wallhavenResolutionHeight = "";
        sortOrder = "name";
      };
      appLauncher = {
        enableClipboardHistory = false;
        autoPasteClipboard = false;
        enableClipPreview = true;
        clipboardWrapText = true;
        clipboardWatchTextCommand = "wl-paste --type text --watch cliphist store";
        clipboardWatchImageCommand = "wl-paste --type image --watch cliphist store";
        position = "center";
        pinnedApps = [];
        useApp2Unit = false;
        sortByMostUsed = true;
        terminalCommand = "alacritty -e";
        customLaunchPrefixEnabled = false;
        customLaunchPrefix = "";
        viewMode = "list";
        showCategories = true;
        iconMode = "tabler";
        showIconBackground = false;
        enableSettingsSearch = true;
        enableWindowsSearch = true;
        ignoreMouseInput = false;
        screenshotAnnotationTool = "";
      };
      controlCenter = {
        position = "close_to_bar_button";
        diskPath = "/";
        shortcuts = {
          left = [
            {
              id = "Network";
            }
            {
              id = "Bluetooth";
            }
            {
              id = "WallpaperSelector";
            }
            {
              id = "NoctaliaPerformance";
            }
          ];
          right = [
            {
              id = "Notifications";
            }
            {
              id = "PowerProfile";
            }
            {
              id = "KeepAwake";
            }
            {
              id = "NightLight";
            }
          ];
        };
        cards = [
          {
            enabled = true;
            id = "profile-card";
          }
          {
            enabled = true;
            id = "shortcuts-card";
          }
          {
            enabled = true;
            id = "audio-card";
          }
          {
            enabled = false;
            id = "brightness-card";
          }
          {
            enabled = true;
            id = "weather-card";
          }
          {
            enabled = true;
            id = "media-sysmon-card";
          }
        ];
      };
      systemMonitor = {
        cpuWarningThreshold = 80;
        cpuCriticalThreshold = 90;
        tempWarningThreshold = 80;
        tempCriticalThreshold = 90;
        gpuWarningThreshold = 80;
        gpuCriticalThreshold = 90;
        memWarningThreshold = 80;
        memCriticalThreshold = 90;
        swapWarningThreshold = 80;
        swapCriticalThreshold = 90;
        diskWarningThreshold = 80;
        diskCriticalThreshold = 90;
        diskAvailWarningThreshold = 20;
        diskAvailCriticalThreshold = 10;
        batteryWarningThreshold = 20;
        batteryCriticalThreshold = 5;
        cpuPollingInterval = 1000;
        gpuPollingInterval = 3000;
        enableDgpuMonitoring = false;
        memPollingInterval = 1000;
        diskPollingInterval = 30000;
        networkPollingInterval = 1000;
        loadAvgPollingInterval = 3000;
        useCustomColors = false;
        warningColor = "";
        criticalColor = "";
        externalMonitor = "resources || missioncenter || jdsystemmonitor || corestats || system-monitoring-center || gnome-system-monitor || plasma-systemmonitor || mate-system-monitor || ukui-system-monitor || deepin-system-monitor || pantheon-system-monitor";
      };
      dock = {
        enabled = false;
        position = "bottom";
        displayMode = "auto_hide";
        backgroundOpacity = layerOpacity;
        floatingRatio = 1;
        size = 1;
        onlySameOutput = true;
        monitors = [];
        pinnedApps = [];
        colorizeIcons = false;
        pinnedStatic = false;
        inactiveIndicators = false;
        deadOpacity = 0.6;
        animationSpeed = 1;
      };
      network = {
        wifiEnabled = true;
        bluetoothRssiPollingEnabled = false;
        bluetoothRssiPollIntervalMs = 10000;
        wifiDetailsViewMode = "grid";
        bluetoothDetailsViewMode = "grid";
        bluetoothHideUnnamedDevices = false;
      };
      sessionMenu = {
        enableCountdown = true;
        countdownDuration = 10000;
        position = "center";
        showHeader = true;
        largeButtonsStyle = true;
        largeButtonsLayout = "single-row";
        showNumberLabels = true;
        powerOptions = [
          {
            action = "lock";
            enabled = true;
          }
          {
            action = "suspend";
            enabled = true;
          }
          {
            action = "hibernate";
            enabled = true;
          }
          {
            action = "reboot";
            enabled = true;
          }
          {
            action = "logout";
            enabled = true;
          }
          {
            action = "shutdown";
            enabled = true;
          }
        ];
      };
      notifications = {
        enabled = true;
        monitors = [];
        location = "top_right";
        overlayLayer = true;
        backgroundOpacity = layerOpacity;
        respectExpireTimeout = false;
        lowUrgencyDuration = 3;
        normalUrgencyDuration = 8;
        criticalUrgencyDuration = 15;
        saveToHistory = {
          low = true;
          normal = true;
          critical = true;
        };
        sounds = {
          enabled = false;
          volume = 0.5;
          separateSounds = false;
          criticalSoundFile = "";
          normalSoundFile = "";
          lowSoundFile = "";
          excludedApps = "discord,firefox,chrome,chromium,edge";
        };
        enableMediaToast = false;

        # wtype tool for keyboard emulation, makes noise, if enabled:
        enableKeyboardLayoutToast = false;
        enableBatteryToast = true;
      };
      osd = {
        enabled = true;
        location = "top_right";
        autoHideMs = 2000;
        overlayLayer = true;
        backgroundOpacity = layerOpacity;
        enabledTypes = [
          0
          1
          2
        ];
        monitors = [];
      };
      audio = {
        volumeStep = 5;
        volumeOverdrive = false;
        cavaFrameRate = 30;
        visualizerType = "linear";
        mprisBlacklist = [];
        preferredPlayer = "";
        volumeFeedback = false;
      };
      brightness = {
        brightnessStep = 5;
        enforceMinimum = true;
        enableDdcSupport = false;
      };
      colorSchemes = {
        useWallpaperColors = false; # we write colors.json directly from the workspace daemon
        predefinedScheme = "";
        darkMode = true;
        schedulingMode = "off";
        manualSunrise = "06:30";
        manualSunset = "18:30";
        generationMethod = "tonal-spot";
        monitorForColors = "";
      };
      templates = {
        activeTemplates = [];
        enableUserTheming = false;
      };
      nightLight = {
        enabled = false;
        forced = false;
        autoSchedule = true;
        nightTemp = "4000";
        dayTemp = "6500";
        manualSunrise = "06:30";
        manualSunset = "18:30";
      };
      hooks = {
        enabled = false;
        wallpaperChange = "";
        darkModeChange = "";
        screenLock = "";
        screenUnlock = "";
        performanceModeEnabled = "";
        performanceModeDisabled = "";
        startup = "";
        session = "";
      };
      # This MUST be imperitive
      # plugins = {
      #   version = 1;
      #   sources = [];
      #   states = {
      #     screen-recorder = {
      #       enabled = true;
      #       sourceUrl = "";
      #     };
      #     coffee = {
      #       enabled = true;
      #       sourceUrl = "";
      #     };
      #     audio-recorder = {
      #       enabled = true;
      #       sourceUrl = "";
      #     };
      #   };
      # };
      desktopWidgets = {
        enabled = false;
        gridSnap = false;
        monitorWidgets = [];
      };
    };
  };
}
