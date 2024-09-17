{ theme }: ''
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



''
