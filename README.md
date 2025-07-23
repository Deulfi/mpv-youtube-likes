# YouTube Likes (and Dislikes) Script for mpv

Mpv script that displays YouTube video information including likes, (dislikes), view count, upload date, and channel name in an OSD message.

## How it works

The script monitors mpv's yt-dlp integration to extract video metadata when YouTube videos are loaded. It automatically formats and displays the information via OSD overlay and optionally creates a button in uosc for manual toggling.

## Installation

1. Copy `youtube-likes.lua` to your mpv scripts directory
2. Copy `youtube-likes.conf` to your script-opts directory

### Optional: For dislikes support

You need the yt-dlp-ReturnYoutubeDislike plugin from pukkandan:

1. Download from <https://github.com/pukkandan/yt-dlp-returnyoutubedislike>
2. For portable Windows installation:

```
└── yt-dlp.exe
└── yt-dlp-plugins\
    └── ReturnYoutubeDislike\
        └── yt_dlp_plugins\
            └── postprocessor\
                └── ryd.py
```

3. Add to your `yt-dlp.conf`:

```
--use-postprocessor ReturnYoutubeDislike:when=pre_process
```

**OR** add to your `mpv.conf`:

```
ytdl-raw-options=use-postprocessor=ReturnYoutubeDislike:when=pre_process
```

## Usage

### Manual trigger

Add to your `input.conf`:

```
l script-message show-youtube-likes
```

### uosc integration

Add to your `uosc.conf` controls (gaps need to be added manually):

```
controls=...,<stream>button:Likes_Button,...
```

## Configuration

Edit `script-opts/youtube-likes.conf`:

- `show_on_start=no` - Auto-display when video starts
- `osd_duration=5` - How long to show OSD (seconds)
- `show_views=yes` - Include view count
- `show_date=yes` - Include upload date
- `show_title=yes` - Include video title
- `show_channel=yes` - Include channel name
- `compact_numbers=yes` - Use 1.2M format instead of 1,234,567

## Requirements

- mpv with yt-dlp support
- Optional: uosc for button interface
- Optional: yt-dlp-ReturnYoutubeDislike plugin for dislike counts
