# Changelog

## 0.1.2

- Menu bar managers such as Thaw and Bartender can now move the icon. The status item has a
  fixed name that matches the one managers see; before, their requests to macOS were filed
  under a different name and ignored. The icon returns to its default position once after
  this update.

## 0.1.1

- The menu opens without taking focus from the app in front.
- With a signing certificate, the app owns its Keychain item, so macOS no longer asks for
  the login password when it starts. The build script re-creates the item only for unsigned
  builds.
- The bundle identifier is now `com.minorkey.flarebar`. Preferences saved under the old
  identifier (shortcut, colour levels, launch at login) are not carried over.

## 0.1.0

First version.

- Menu bar panel with accounts as cards and projects as rows, each with a status dot and
  its highest usage figure.
- Per project: usage against the account's Workers plan allowances, and Workers with their
  last deployment. Per account: the bill so far, split into plans and usage lines.
- Projects defined by name prefixes; several Cloudflare tokens and accounts.
- Settings with a page per account, a system-wide shortcut, adjustable yellow and red
  levels, and launch at login.
- Keyboard navigation in the menu.
