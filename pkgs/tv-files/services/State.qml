// Whether the browser overlay is visible, and which directory it's showing.
// A singleton (not a plain QtObject) so every QML file that imports the
// containing services/ directory sees the same instance.
pragma Singleton
import Quickshell

Singleton {
  property bool open: false
  property string currentPath: Theme.places.length > 0 ? Theme.places[0].path : ""

  // Jump back to the first configured place. Called on every open so the
  // browser never reappears three folders deep from last time.
  function reset(): void {
    currentPath = Theme.places.length > 0 ? Theme.places[0].path : currentPath;
  }
}
