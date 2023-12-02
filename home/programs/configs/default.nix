{ nix-colors, pkgs, lib, config, ... }:
{
  home.file."custom/configs/trillium.css".text = 
  ''
  :root {

    --red: #${config.colorScheme.colors.base20} !important;;
    --orange: #${config.colorScheme.colors.base22} !important;
    --yellow: #${config.colorScheme.colors.base24} !important;
    --green: #${config.colorScheme.colors.base26} !important;
    --teal: #${config.colorScheme.colors.base28} !important;
    --cyan: #${config.colorScheme.colors.base29} !important;
    --blue: #${config.colorScheme.colors.base2A} !important;
    --indigo: #${config.colorScheme.colors.base2C} !important;
    --purple: #${config.colorScheme.colors.base2E} !important;
    --pink: #${config.colorScheme.colors.base2F} !important;

    --white: #${config.colorScheme.colors.base07} !important;
    --gray: #${config.colorScheme.colors.base04} !important;
    --gray-dark: #${config.colorScheme.colors.base03} !important;
    --primary: #${config.colorScheme.colors.base0D} !important;
    --secondary: #${config.colorScheme.colors.base05} !important;
    --success: #${config.colorScheme.colors.base0B} !important;
    --info: #${config.colorScheme.colors.base2A} !important;
    --warning: #${config.colorScheme.colors.base24} !important;
    --danger: #${config.colorScheme.colors.base20} !important;
    --light: #${config.colorScheme.colors.base06} !important;
    --dark: #${config.colorScheme.colors.base01} !important;



    --theme-style: dark;

    --main-font-family: Helvetica;
    --main-font-size: normal;

    --tree-font-family: Helvetica;
    --tree-font-size: normal;

    --detail-font-family: Helvetica;
    --detail-font-size: normal;

    --monospace-font-family: 'Lucida Console', 'Courier New', Courier;
    --monospace-font-size: normal;

    --main-background-color: #${config.colorScheme.colors.base02};
    --main-text-color: #${config.colorScheme.colors.base06};
    --main-border-color: #${config.colorScheme.colors.base03};

    --accented-background-color: #${config.colorScheme.colors.base01};
    --more-accented-background-color: #${config.colorScheme.colors.base03};

    --button-background-color: transparent;
    --button-border-color: #${config.colorScheme.colors.base03};
    --button-text-color: currentColor;
    --button-border-radius: 0px;
    --button-disabled-background-color: #${config.colorScheme.colors.base01};
    --button-disabled-text-color: #${config.colorScheme.colors.base05};

    --primary-button-background-color: #${config.colorScheme.colors.base03};
    --primary-button-text-color: #${config.colorScheme.colors.base05};
    --primary-button-border-color: #${config.colorScheme.colors.base02};

    --muted-text-color: #${config.colorScheme.colors.base05};

    --input-text-color: #${config.colorScheme.colors.base07};
    --input-background-color: #${config.colorScheme.colors.base02};

    --hover-item-text-color: #${config.colorScheme.colors.base06};
    --hover-item-background-color: #${config.colorScheme.colors.base02};
    --hover-item-border-color: #${config.colorScheme.colors.base01};

    --active-item-text-color: #${config.colorScheme.colors.base06};
    --active-item-background-color: #${config.colorScheme.colors.base03};
    --active-item-border-color: #${config.colorScheme.colors.base02};

    --menu-text-color: #${config.colorScheme.colors.base06};
    --menu-background-color: #${config.colorScheme.colors.base02};

    --modal-background-color: #${config.colorScheme.colors.base01};
    --modal-backdrop-color: #${config.colorScheme.colors.base00};

    --left-pane-background-color: #${config.colorScheme.colors.base01};
    --left-pane-text-color: #${config.colorScheme.colors.base06};

    --launcher-pane-background-color: #${config.colorScheme.colors.base00};
    --launcher-pane-text-color: #${config.colorScheme.colors.base06};

    --active-tab-background-color: #${config.colorScheme.colors.base03};
    --active-tab-hover-background-color: #${config.colorScheme.colors.base04};
    --active-tab-text-color: #${config.colorScheme.colors.base0D};

    --inactive-tab-background-color: #${config.colorScheme.colors.base01};
    --inactive-tab-hover-background-color: #${config.colorScheme.colors.base03};
    --inactive-tab-text-color: #${config.colorScheme.colors.base05};

    --scrollbar-border-color: #${config.colorScheme.colors.base01};
    --tooltip-background-color: #${config.colorScheme.colors.base01};
    --link-color: #${config.colorScheme.colors.base0D};

    --mermaid-theme: dark;
    --ck-color-code-block-label-background: #${config.colorScheme.colors.base03};
  }

  # This is for mini code blocks
  .ck-content code {
    background-color: #${config.colorScheme.colors.base01} !important;
  }
  
  body .ck-content code {
    background-color: #${config.colorScheme.colors.base01} !important;
  }

  .ck.ck-editor__editable .ck-code_selected {
    background-color: #${config.colorScheme.colors.base03} !important;
  }

  body ::-webkit-calendar-picker-indicator {
    filter: invert(1);
  }

  body .CodeMirror {
    filter: invert(90%) hue-rotate(180deg);
  }

  .excalidraw.theme--dark {
    --theme-filter: invert(80%) hue-rotate(180deg) !important;
  }

  .gutter {
    width: 2px !important;
    background: #${config.colorScheme.colors.base00} !important; 
  }

  span.fancytree-custom-icon {
    color: #${config.colorScheme.colors.base0D} !important;
    background: none;
  }

  .tree-actions {
    background-color: #${config.colorScheme.colors.base01} !important;
  }

  span.fancytree-active .fancytree-title {
    font-weight: normal !important; 
  }

  span.fancytree-active {
    border: 0px !important;
    background-color: #${config.colorScheme.colors.base03} !important;
  }

  .tab-row-filler {
    background-color: #${config.colorScheme.colors.base02} !important;
  }

  .tab-row-widget .note-tab .note-tab-wrapper {
    border-radius: 0px !important;
  }

  .tab-row-widget .note-tab[active] .note-tab-wrapper {
    font-weight: normal !important;
    font-style: italic !important;
    border-radius: 0px !important;
  }

  .note-book-card {
    border-radius: 0px !important;
    background-color: #${config.colorScheme.colors.base01} !important;
  }

  button.tree-floating-button:hover {
    border: 0px !important;
    background-color: #${config.colorScheme.colors.base03} !important;
  }

  .ck-content pre {
    border: 1px solid #${config.colorScheme.colors.base00} !important;
    border-radius: 0px !important;
    background-color: #${config.colorScheme.colors.base01} !important;
  }

  div#launcher-pane .global-menu-button {
    filter: invert(0.5);
  }

  div#launcher-pane .global-menu-button:hover {
    filter: invert(0);
  }

  .note-new-tab {
    background-color: #${config.colorScheme.colors.base02} !important;
  }

  span.fancytree-node:hover {
    border: 0px !important;
    background-color: #${config.colorScheme.colors.base03} !important;
  }

  #right-pane {
    background-color: #${config.colorScheme.colors.base01} !important;
  }

  .dropdown-menu.show {
    background-color: #${config.colorScheme.colors.base03} !important;
  }

  .btn-primary.focus, .btn-primary:focus {
    box-shadow: none !important;
  }

  .title-bar-buttons {
    visibility: hidden !important;
    width: 0 !important;
  }
  .tab-row-widget .tab-row-widget-container {
    height: 90% !important;
  }

.ck-content ul ul {
  border-left: 2px solid #${config.colorScheme.colors.base04} !important;
}

  .bx.tree-item-button {
    background-color: #${config.colorScheme.colors.base01} !important;
    position: absolute !important;
    right: 10px !important;
  }

  '';
}
