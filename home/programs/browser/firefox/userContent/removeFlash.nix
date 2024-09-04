{ theme }:
''
  .tabbrowser-tabbox {
      background-color: #${theme.base02} !important;
  }

  @-moz-document plain-text-document(), media-document(all) {
    @media (prefers-color-scheme: dark) {
      :root {
        background-color: #${theme.base02} !important;
        foreground-color: #${theme.base07} !important;
      }
      body:not([style*="background"], [class], [id]) {
        background-color: transparent !important;
      }
    }
  }

  /* remove flash */
  @-moz-document url("about:home"),url("about:blank"),url("about:newtab"),url("about:privatebrowsing"){
    body{background-color: #${theme.base02} !important }
  }

  @-moz-document url("about:preferences#home"){
    body{background-color: #${theme.base02} !important }
  }
''
