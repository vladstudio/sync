# Sync

macOS menu bar app for file synchronization via rclone. Swift 6, macOS 15+.

## Build

```
make build      # swift build -c release
make package    # build + create .app bundle in build/
make install    # package + copy to /Applications
./build.sh      # build, install, and launch
```

## Structure

```
Sources/Sync/
  Models/       SyncConfig, AppSettings
  Services/     RcloneService, SyncManager (includes ConfigStore, FileWatcher)
  Views/        MenuBarView, ManageSyncsView, EditSyncView, LogView, SettingsView
  SyncApp.swift
Resources/      Info.plist, AppIcon.icns, MenuBarIcon*.png
```

## Notes

- No dependencies — uses only Apple frameworks (SwiftUI, Combine, Observation)
- Configs stored as JSON in `~/Library/Application Support/Sync/`
- rclone must be installed separately (`brew install rclone`)
