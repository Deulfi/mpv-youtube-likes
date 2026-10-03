-- youtube-likes.lua
--
-- Display YouTube video likes, dislikes, and view count
-- Shows information in OSD when a YouTube video starts playing
--
-- Primary data source: the JSON mpv's builtin ytdl hook captured while
-- loading the file (user-data/mpv/ytdl/json-subprocess-result) - the
-- yt-dlp run mpv already performed, so no extra request.
-- Fallback: the hook does not run for local files, so for downloads the
-- script runs yt-dlp itself using the video id from the filename or the
-- PURL tag.

local mp = require "mp"
local msg = require "mp.msg"
local utils = require "mp.utils"

-- ==================== Options ====================

local opts = {
    -- Show likes info automatically when video starts
    show_on_start = true,

    -- Fetch video data ourselves for local files (the ytdl hook only
    -- covers streamed URLs)
    show_for_local_files = true,

    -- Duration to show the OSD message (in seconds)
    osd_duration = 5,

    -- Include view count in display
    show_views = true,

    -- Include upload date in display
    show_date = true,

    -- Include title in display
    show_title = true,

    -- Include channel name in display
    show_channel = true,

    -- Format for displaying numbers (true = 1.2M, false = 1,234,567)
    compact_numbers = true,

    -- Show likes info in button
    text_in_button = true,

    -- Icon for button use 👍 or any from https://fonts.google.com/icons?icon.platform=web&icon.set=Material+Icons&icon.style=Rounded
    icon_for_button = "",
}
(require "mp.options").read_options(opts, "youtube-likes")

-- ==================== State ====================

local video_data = nil
local osd_visible = nil
local osd_timer = nil
local uosc_present = false
local ytdl_path = nil

-- ==================== Helpers ====================

-- Find the yt-dlp executable (parts lifted from the builtin ytdl hook):
-- an absolute path when yt-dlp sits in the config dir, else the bare PATH
-- name; both spawn reliably. Cached after the first lookup.
local function find_ytdl_path()
    if ytdl_path then return ytdl_path end
    local platform_is_windows = (package.config:sub(1, 1) == "\\")
    local paths_to_search = { "yt-dlp", "yt-dlp_x86", "youtube-dl" }

    for _, path in pairs(paths_to_search) do
        local exesuf = platform_is_windows and ".exe" or ""
        local ytdl_cmd = mp.find_config_file(path .. exesuf)
        if ytdl_cmd then
            msg.verbose("Found youtube-dl at: " .. ytdl_cmd)
            return ytdl_cmd
        end
    end

    -- Fallback to yt-dlp in PATH
    ytdl_path = "yt-dlp"
    return ytdl_path
end

-- Format a number using the configured style (compact 1.2M or 1,234,567)
local function format_number(num)
    if not num or num == 0 then
        return "0"
    end

    if not opts.compact_numbers then
        -- Add commas for thousands separator
        local formatted = tostring(num)
        local k
        while true do
            formatted, k = string.gsub(formatted, "^(-?%d+)(%d%d%d)", '%1,%2')
            if k == 0 then break end
        end
        return formatted
    end

    -- Compact format (1.2M, 3.4K, etc.)
    if num >= 1000000 then
        return string.format("%.1fM", num / 1000000)
    elseif num >= 1000 then
        return string.format("%.1fK", num / 1000)
    else
        return tostring(num)
    end
end

-- Send a uosc set-button command for the Likes button
local function set_likes_button(data)
    mp.commandv('script-message-to', 'uosc', 'set-button', 'Likes_Button', utils.format_json(data))
end

-- ==================== Display ====================

-- Show the likes info in the OSD; toggles off if it is already visible
local function show_likes_info()
    -- If OSD is currently visible, hide it
    if osd_visible then
        if osd_timer then
            mp.cancel_timer(osd_timer, true)
            osd_timer = nil
        end
        mp.osd_message("", 0)
        osd_visible = false
        return
    end
    if not video_data then
        mp.osd_message("No video data available", 2)
        return
    end

    local lines = {}
    local title = video_data.title or "Unknown Title"

    -- Add title (truncate if too long)
    if string.len(title) > 80 then
        title = string.sub(title, 1, 57) .. "..."
    end
    if opts.show_title then
        table.insert(lines, "📺 " .. title)
    end

    -- Add likes/dislikes
    local likes = video_data.like_count
    local dislikes = video_data.dislike_count

    if likes then
        local like_str = "👍 " .. format_number(likes)
        if dislikes and dislikes > 0 then
            like_str = like_str .. "  👎 " .. format_number(dislikes)
        end
        table.insert(lines, like_str)
    end

    -- Add view count
    if opts.show_views and video_data.view_count then
        table.insert(lines, "👁 " .. format_number(video_data.view_count) .. " views")
    end

    -- Add upload date
    if opts.show_date and video_data.upload_date then
        local date_str = video_data.upload_date
        -- Convert YYYYMMDD to YYYY-MM-DD
        if string.len(date_str) == 8 then
            date_str = string.sub(date_str, 1, 4) .. "-" ..
                      string.sub(date_str, 5, 6) .. "-" ..
                      string.sub(date_str, 7, 8)
        end
        table.insert(lines, "📅 " .. date_str)
    end

    -- Add channel name
    if video_data.uploader and opts.show_channel then
        table.insert(lines, "📺 " .. video_data.uploader)
    end

    local message = table.concat(lines, "\n")
    mp.osd_message(message, opts.osd_duration)
    msg.info("Video info: " .. string.gsub(message, "\n", " | "))
    osd_visible = true
    -- Reset the flag when the OSD auto-expires so a later manual trigger
    -- shows the info instead of treating it as already visible.
    osd_timer = mp.add_timeout(opts.osd_duration, function()
        osd_visible = false
        osd_timer = nil
    end)
end

-- ==================== Data processing ====================

-- Store the yt-dlp JSON in video_data, show the OSD, and update the button
local function process_ytdl_data(ytdl_data)
    if not ytdl_data then msg.debug("No yt-dlp data") return end
    msg.debug("Processing yt-dlp data")

    video_data = {
        title = ytdl_data.title,
        like_count = ytdl_data.like_count,
        dislike_count = ytdl_data.dislike_count,
        view_count = ytdl_data.view_count,
        upload_date = ytdl_data.upload_date,
        uploader = ytdl_data.uploader or ytdl_data.channel,
        duration = ytdl_data.duration,
    }

    msg.verbose("Extracted video data: likes=" .. tostring(video_data.like_count) ..
                ", views=" .. tostring(video_data.view_count))

    if opts.show_on_start then
        show_likes_info()
    end

    if uosc_present then
        local has_icon = opts.icon_for_button and opts.icon_for_button ~= ""
        local likes_text = has_icon and format_number(video_data.like_count) or ("👍" .. format_number(video_data.like_count))

        local tooltip = likes_text
        if video_data.dislike_count and video_data.dislike_count > 0 then
            tooltip = tooltip .. " 👎" .. format_number(video_data.dislike_count)
        end
        tooltip = tooltip .. " 👁" .. format_number(video_data.view_count)

        if not opts.text_in_button and not has_icon then
            opts.icon_for_button = "thumb_up"
        end

        set_likes_button({
            icon = opts.icon_for_button or "",
            badge = opts.text_in_button and likes_text or nil,
            tooltip = tooltip,
            command = "script-message show-youtube-likes",
            hide = false,
        })
    end
end

-- ==================== yt-dlp data sources ====================

-- Extract the JSON mpv's builtin ytdl hook captured for the current file.
-- The hook runs yt-dlp during file load, stores the subprocess result in
-- the user-data property and deletes it when the file ends, so a present
-- value always belongs to the file currently loading.
local function get_hook_data()
    local result = mp.get_property_native("user-data/mpv/ytdl/json-subprocess-result")
    if not result or result.status ~= 0 or not result.stdout then
        return nil
    end
    local json_data, err = utils.parse_json(result.stdout)
    if not json_data then
        msg.error("Failed to parse ytdl hook JSON: " .. (err or "unknown error"))
        return nil
    end
    return json_data
end

-- Extract the YouTube ID from a local file's filename
local function extract_youtube_id_from_filename(filepath)
    local id = filepath:match("%[([%w-_]+)%]")
    if id and #id == 11 then
        msg.info("Found YouTube ID. Fetching data. This may take a while...")
        return id
    end
    return nil
end

-- Fetch video data ourselves (fallback when the hook didn't capture data
-- for this file, e.g. local downloads). Mirrors the builtin ytdl hook:
-- resolves yt-dlp the same way and reuses the user's ytdl-raw-options
-- (proxy, cookies, dislike plugin, ...).
local function fetch_video_data_for_local(youtube_id, purl)
    local yt_dlp_path = find_ytdl_path()

    -- purl is the original URL stored in the file metadata; the watch URL
    -- is the fallback target
    local target = purl or ("https://www.youtube.com/watch?v=" .. youtube_id)

    local args = {yt_dlp_path, "--dump-json", "--no-download", "--no-sponsorblock"}
    for param, arg in pairs(mp.get_property_native("options/ytdl-raw-options")) do
        table.insert(args, "--" .. param)
        if arg ~= "" or param == "proxy" then
            table.insert(args, arg)
        end
    end
    table.insert(args, target)

    local fetch_file = mp.get_property("path")
    local result = mp.command_native{
        name = "subprocess",
        capture_stdout = true,
        playback_only = false,
        args = args
    }
    -- The fetch blocks this thread; if the user skipped to a different file
    -- in the meantime, don't display stale data for the old one. A nil path
    -- means mpv is already unloading (not a skip), so we still apply the data.
    local current_file = mp.get_property("path")
    if current_file and current_file ~= fetch_file then
        msg.info("File changed during fetch; discarding data")
        return
    end
    if result.status == 0 and result.stdout then
        local json_data = utils.parse_json(result.stdout)
        if json_data then
            process_ytdl_data(json_data)
        else
            msg.error("Failed to parse yt-dlp JSON output")
        end
    else
        msg.error("Failed to fetch video data: " .. (result.stderr or result.error_string or "unknown error"))
    end
end

-- ==================== Events ====================

-- Reset state when a new file starts
mp.register_event("start-file", function()
    video_data = nil
    -- Hide the button; it would otherwise persist from a previous YouTube file
    set_likes_button({icon = "", hide = true})
end)

-- file-loaded: primary path - use the data the ytdl hook already captured
-- for this file (streaming). Fallback - the hook didn't run for it (local
-- download): fetch it ourselves from the id in the filename or PURL.
mp.register_event("file-loaded", function()
    local hook_data = get_hook_data()
    if hook_data then
        msg.info("Using ytdl hook data")
        process_ytdl_data(hook_data)
        return
    end

    -- For offline videos, try to extract the YouTube ID from filename or PURL
    local filepath = mp.get_property("path", "")

    if filepath and not filepath:match("^https?://") and opts.show_for_local_files then
        local youtube_id = extract_youtube_id_from_filename(filepath)
        if youtube_id then msg.info("Found YouTube ID in filename: " .. youtube_id) end
        local purl = mp.get_property("metadata/by-key/PURL")
        if purl then msg.info("Found PURL in the Video: " .. purl) end

        if youtube_id or purl then
            fetch_video_data_for_local(youtube_id, purl)
        end
    end
end)

-- ==================== Script API ====================

-- Manual trigger (input binding / uosc button)
mp.register_script_message("show-youtube-likes", show_likes_info)

-- Provide the current counts to other scripts
mp.register_script_message("get-video-likes", function()
    if video_data and video_data.like_count then
        mp.commandv("script-message", "video-likes-result",
                   tostring(video_data.like_count),
                   tostring(video_data.dislike_count or 0),
                   tostring(video_data.view_count or 0))
    else
        mp.commandv("script-message", "video-likes-result", "0", "0", "0")
    end
end)

-- Learn whether uosc is present (only then is the button shown)
mp.register_script_message('uosc-version', function(version)
    uosc_present = true
end)

-- ==================== Init ====================

msg.info("Video info script loaded.")
-- Start with the button hidden
set_likes_button({icon = "", hide = true})
