MacPaper
========

A native macOS app that turns video files into looping animated wallpapers.

It encodes MP4/MOV/M4V to HEVC, then plays the result in a desktop-level window behind your icons. Keep the app running while the wallpaper is active.

Build
-----
Requires macOS 14+ and Swift (Xcode or Command Line Tools).

    chmod +x Scripts/package-app.sh
    ./Scripts/package-app.sh
    open MacPaper.app

Use
---
1. Drop a video or File > Open Video
2. Pick quality (Battery / Balanced / High) and fill vs letterbox
3. Convert & Apply
4. Pause, resume, or stop from the window or the menu bar extra

Converted files live in ~/Library/Application Support/MacPaper/Wallpapers
