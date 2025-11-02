-- youtube-likes.lua
--
-- Display YouTube video likes, dislikes, and view count
-- Shows information in OSD when a YouTube video starts playing

local mp = require "mp"
local msg = require "mp.msg"
local utils = require "mp.utils"
local script_name = mp.get_script_name()

local opts = {
    -- Show likes info automatically when video starts
    show_on_start = true,

    -- Tries to get data for local Files
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

local video_data = nil
local osd_visible = nil
local uosc_present = false
local ytdl_path = nil

-- For local Files part

-- Find yt-dlp executable path (parts lifted from ytdl_hook)
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


-- Extract YouTube ID from filename for offline videos
local function extract_youtube_id_from_filename(filepath)
    local id = filepath:match("%[([%w-_]+)%]")
    if id and #id == 11 then
        msg.info("Found YouTube ID. Fetching data. This may take a while...")
        return id
    end
    return nil 
end

-- Fetch video data using YouTube ID
local function fetch_video_data_for_local(youtube_id, purl)
    local yt_dlp_path = find_ytdl_path()
    local url = "https://www.youtube.com/watch?v=" .. youtube_id

    local args = {yt_dlp_path, "--dump-json", "--no-download", "--no-sponsorblock", purl or url}
    
    local result = mp.command_native{
        name = "subprocess",
        capture_stdout = true,
        playback_only = false,
        args = args
    }
    
    if result.stdout then
        local json_data = utils.parse_json(result.stdout)
        if json_data then
            process_ytdl_data(json_data)
        end
    else
        msg.error("Failed to fetch video data: " .. (result.stderr or "unknown error"))
    end
end

-- Clear data when file changes
mp.register_event("file-loaded", function()
    -- For offline videos, try to extract YouTube ID from filename or PURL
    local filepath = mp.get_property("path", "")

    if filepath and not filepath:match("^https?://") and opts.show_for_local_files then

        local youtube_id = extract_youtube_id_from_filename(filepath)
        if youtube_id then msg.info("Found YouTube ID in filename: " .. youtube_id) end
        local purl = mp.get_property("metadata/by-key/PURL")
        if purl then msg.info("Found PURL in the Video: ".. purl) end

        if youtube_id or purl then
            fetch_video_data_for_local(youtube_id, purl)
        end
    end

end)

-- Rest

-- Format large numbers in a compact way
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

-- Display the likes information
local function show_likes_info()
    -- If OSD is currently visible, hide it
    if osd_visible then
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
        local like_str = "👍 " .. likes
        if dislikes and dislikes > 0 then
            like_str = like_str .. "  👎 " .. dislikes
        end
        table.insert(lines, like_str)
    end
    
    -- Add view count
    if opts.show_views and video_data.view_count then
        table.insert(lines, "👁 " .. video_data.view_count .. " views")
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
end

-- Process the JSON data from yt-dlp
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
        -- Small delay to ensure video has started
        --mp.add_timeout(1.0, function() show_likes_info(video_data) end)
        -- no delay since we use file-loaded event now
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

        mp.commandv('script-message-to', 'uosc', 'set-button', 'Likes_Button', utils.format_json({
            icon = opts.icon_for_button or "",
            badge = opts.text_in_button and likes_text or nil,
            tooltip = tooltip,
            command = "script-message show-youtube-likes",
            hide = false,
        }))
    end
end

-- Monitor for yt-dlp JSON data
mp.observe_property('user-data/mpv/ytdl/json-subprocess-result', 'native', function(_, ytdl_result)
    if not ytdl_result then return end
    
    if ytdl_result.status ~= 0 or not ytdl_result.stdout then
        msg.warn("Failed to get yt-dlp data")
        return
    end
    
    local json_data, err = utils.parse_json(ytdl_result.stdout)
    if not json_data then
        msg.error("Failed to parse yt-dlp JSON: " .. (err or "unknown error"))
        return
    end
    
    msg.info("Proceeding with yt-dlp data")
    process_ytdl_data(json_data)
end)

-- Clear data when file changes
mp.register_event("start-file", function()
    video_data = nil
    -- hide button in case of youtube video -> local file, button would still show up.
    mp.commandv('script-message-to', 'uosc', 'set-button', 'Likes_Button', utils.format_json({icon = "", hide = true}))
end)

mp.register_script_message("show-youtube-likes", show_likes_info)


-- Script message interface for other scripts
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

msg.info("Video info script loaded.")
-- Init Button in invisible state.
mp.commandv('script-message-to', 'uosc', 'set-button', 'Likes_Button', utils.format_json({icon = "", hide = true}))
mp.register_script_message('uosc-version', function(version)
    uosc_present = true
  end)

  --TODO: says no data available but button shows the data.Button is also with icon.