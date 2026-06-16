--- wez-weather: a small WezTerm plugin that shows current temperature + conditions
--- in the status bar, with a nerd font icon. Backed by the free Open-Meteo API
--- (no API key required).
---
--- Usage:
---   local weather = wezterm.plugin.require("https://github.com/akobyl/wez-weather")
---   weather.setup({
---     location = "Boston, MA",   -- city name, "lat,lon", or US 5-digit zip code
---     units = "fahrenheit",      -- "fahrenheit" | "celsius"
---     update_interval = 600,     -- seconds between refreshes (default 600 = 10 min)
---   })
---
---   tabline.setup({
---     sections = {
---       tabline_z = { weather.component, "domain" },
---     },
---   })

local wezterm = require("wezterm")

local M = {}

local config = {
	location = "New York",
	units = "fahrenheit",
	update_interval = 600,
}

local state = {
	lat = nil,
	lon = nil,
	geocode_failed = false,
	text = "",
	last_fetch = 0,
}

-- WMO weather codes (used by Open-Meteo) -> { icon, label }
local WEATHER_CODES = {
	[0] = { icon = "md_weather_sunny", label = "Clear" },
	[1] = { icon = "md_weather_sunny", label = "Mainly clear" },
	[2] = { icon = "md_weather_partly_cloudy", label = "Partly cloudy" },
	[3] = { icon = "md_weather_cloudy", label = "Overcast" },
	[45] = { icon = "md_weather_fog", label = "Fog" },
	[48] = { icon = "md_weather_fog", label = "Freezing fog" },
	[51] = { icon = "md_weather_rainy", label = "Light drizzle" },
	[53] = { icon = "md_weather_rainy", label = "Drizzle" },
	[55] = { icon = "md_weather_pouring", label = "Dense drizzle" },
	[56] = { icon = "md_weather_snowy_rainy", label = "Freezing drizzle" },
	[57] = { icon = "md_weather_snowy_rainy", label = "Freezing drizzle" },
	[61] = { icon = "md_weather_rainy", label = "Light rain" },
	[63] = { icon = "md_weather_rainy", label = "Rain" },
	[65] = { icon = "md_weather_pouring", label = "Heavy rain" },
	[66] = { icon = "md_weather_snowy_rainy", label = "Freezing rain" },
	[67] = { icon = "md_weather_snowy_rainy", label = "Freezing rain" },
	[71] = { icon = "md_weather_snowy", label = "Light snow" },
	[73] = { icon = "md_weather_snowy", label = "Snow" },
	[75] = { icon = "md_weather_snowy_heavy", label = "Heavy snow" },
	[77] = { icon = "md_weather_snowy", label = "Snow grains" },
	[80] = { icon = "md_weather_rainy", label = "Rain showers" },
	[81] = { icon = "md_weather_pouring", label = "Rain showers" },
	[82] = { icon = "md_weather_pouring", label = "Violent rain showers" },
	[85] = { icon = "md_weather_snowy", label = "Snow showers" },
	[86] = { icon = "md_weather_snowy_heavy", label = "Snow showers" },
	[95] = { icon = "md_weather_lightning", label = "Thunderstorm" },
	[96] = { icon = "md_weather_lightning_rainy", label = "Thunderstorm w/ hail" },
	[99] = { icon = "md_weather_lightning_rainy", label = "Thunderstorm w/ hail" },
}

local function icon_for_code(code)
	local entry = WEATHER_CODES[code]
	if not entry then
		return wezterm.nerdfonts.md_weather_cloudy_alert, "Unknown"
	end
	return wezterm.nerdfonts[entry.icon] or wezterm.nerdfonts.md_weather_cloudy_alert, entry.label
end

local function urlencode(str)
	return (str:gsub("[^%w%-%_%.%~]", function(c)
		return string.format("%%%02X", string.byte(c))
	end))
end

local function http_get_json(url)
	local ok, stdout = wezterm.run_child_process({ "curl", "-s", "--max-time", "5", url })
	if not ok or not stdout or stdout == "" then
		return nil
	end
	local success, data = pcall(wezterm.json_parse, stdout)
	if not success then
		return nil
	end
	return data
end

local function is_us_zip(loc)
	return loc:match("^%d%d%d%d%d$") ~= nil
end

local function is_lat_lon(loc)
	local lat, lon = loc:match("^%s*(-?%d+%.?%d*)%s*,%s*(-?%d+%.?%d*)%s*$")
	return lat, lon
end

-- Resolve config.location into lat/lon, trying (in order): explicit "lat,lon",
-- US zip code (via the free Zippopotam.us API), or city name (via Open-Meteo's
-- free geocoding API).
local function geocode(location)
	local lat, lon = is_lat_lon(location)
	if lat and lon then
		return tonumber(lat), tonumber(lon)
	end

	if is_us_zip(location) then
		local data = http_get_json("https://api.zippopotam.us/us/" .. location)
		local place = data and data.places and data.places[1]
		if place then
			return tonumber(place["latitude"]), tonumber(place["longitude"])
		end
		return nil
	end

	local url = "https://geocoding-api.open-meteo.com/v1/search?count=1&name=" .. urlencode(location)
	local data = http_get_json(url)
	local result = data and data.results and data.results[1]
	if result then
		return result.latitude, result.longitude
	end
	return nil
end

local function normalize_units(units)
	units = tostring(units or "fahrenheit"):lower()
	if units == "f" or units == "fahrenheit" then
		return "fahrenheit"
	end
	if units == "c" or units == "celsius" then
		return "celsius"
	end
	return "fahrenheit"
end

local function fetch_weather(lat, lon, units)
	local url = string.format(
		"https://api.open-meteo.com/v1/forecast?latitude=%s&longitude=%s&current=temperature_2m,weather_code&temperature_unit=%s",
		lat,
		lon,
		units
	)
	local data = http_get_json(url)
	if not data or not data.current then
		return nil
	end
	return data.current.temperature_2m, data.current.weather_code
end

local function ensure_location()
	if state.lat and state.lon then
		return
	end
	if state.geocode_failed then
		return
	end
	local lat, lon = geocode(config.location)
	if lat and lon then
		state.lat, state.lon = lat, lon
	else
		state.geocode_failed = true
		wezterm.log_warn("wez-weather: failed to resolve location '" .. tostring(config.location) .. "'")
	end
end

local function refresh()
	ensure_location()
	if not state.lat or not state.lon then
		state.text = wezterm.nerdfonts.md_weather_cloudy_alert .. " --"
		return
	end

	local temp, code = fetch_weather(state.lat, state.lon, config.units)
	if not temp then
		-- Keep the last known-good text on a transient failure.
		if state.text == "" then
			state.text = wezterm.nerdfonts.md_weather_cloudy_alert .. " --"
		end
		return
	end

	local icon = icon_for_code(code)
	local unit_symbol = config.units == "celsius" and "°C" or "°F"
	state.text = string.format("%s %.0f%s", icon, temp, unit_symbol)
end

--- Configure the plugin. Call this once, before adding `M.component` to a
--- tabline/status bar section.
---@param opts? { location?: string, units?: string, update_interval?: number }
function M.setup(opts)
	opts = opts or {}
	if opts.location then
		config.location = opts.location
	end
	config.units = normalize_units(opts.units or config.units)
	if opts.update_interval then
		config.update_interval = opts.update_interval
	end

	-- Force re-geocoding and an immediate refresh on (re)configure.
	state.lat, state.lon, state.geocode_failed = nil, nil, false
	state.last_fetch = 0
end

--- A function suitable for use directly as a tabline.wez (or any window-status)
--- component: `tabline_z = { weather.component }`. Refreshes from the network
--- at most once every `update_interval` seconds; otherwise returns the cached
--- string immediately.
---@param window any
---@return string
function M.component(window)
	local now = wezterm.time.now():seconds()
	if now - state.last_fetch >= config.update_interval then
		state.last_fetch = now
		refresh()
	end
	return state.text
end

return M
