# MindKite Android brand assets

- `drawable/launch_background.xml`, `drawable-v21/launch_background.xml`, and `drawable-nodpi/launch_background.xml` paint the MindKite
  app background color behind a centered white icon pill and render the kite mark vector for pre-Android 12 splash screens.
- `values/` color resources provide the shared splash background and icon background colors.
- `values-v31/` styles opt in to Android 12+'s system splash screen API so the same colors and vector icon are used on modern
  devices when the OS draws the launch experience.
