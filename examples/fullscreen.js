const w = cs.window.create('Demo', 800, 600)

// Please note this is a dedicated full screen mode so you won't have
// the usual alt tab and window shortcuts provided by your operating system.
// If you didn't handle user inputs in your app, you'll need to force quit the current app:
// On macos that is: option + command + escape
// On windows that is: ctrl + alt + delete
w.setFullscreenMode()
// w.setPseudoFullscreenMode()
// w.setWindowedMode()