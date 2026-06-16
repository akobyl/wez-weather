# wez-weather

A tiny [WezTerm](https://wezterm.org/) plugin that shows current temperature
and conditions in your status bar, with a [Nerd Font](https://www.nerdfonts.com/)
icon. Backed entirely by the free [Open-Meteo](https://open-meteo.com/) API —
no API key, no signup.

```
 72°F
```

## Features

- Free, keyless weather API (Open-Meteo)
- Accepts a city name, a US 5-digit zip code, or explicit `"lat,lon"`
- Nerd Font icon per condition (clear, cloudy, rain, snow, fog, thunderstorm, ...)
- Refreshes on a configurable interval (default: every 10 minutes)
- Configurable units: Fahrenheit or Celsius

## Requirements

- `curl` available on `$PATH`
- A [Nerd Font](https://www.nerdfonts.com/) configured in WezTerm so the
  weather icons render correctly

## Installation

```lua
local wezterm = require("wezterm")
local weather = wezterm.plugin.require("https://github.com/akobyl/wez-weather")

weather.setup({
  location = "Boston, MA", -- city name, "lat,lon", or US zip code
  units = "fahrenheit",    -- "fahrenheit" | "celsius"
  update_interval = 600,   -- seconds between refreshes
})
```

Then add `weather.component` to any status bar / tabline section. For example,
with [tabline.wez](https://github.com/michaelbrusegard/tabline.wez):

```lua
local tabline = wezterm.plugin.require("https://github.com/michaelbrusegard/tabline.wez")

tabline.setup({
  sections = {
    tabline_z = { weather.component, "domain" },
  },
})
tabline.apply_to_config(config)
```

Or with WezTerm's built-in `update-status` event and `format-tab-title` /
right-status, call `weather.component(window)` from your own handler.

## Configuration

| Option            | Type     | Default      | Description                                      |
|--------------------|----------|--------------|---------------------------------------------------|
| `location`         | string   | `"New York"` | City name, US zip code, or `"lat,lon"`            |
| `units`             | string   | `"fahrenheit"` | `"fahrenheit"` or `"celsius"`                   |
| `update_interval`   | number   | `600`        | Seconds between API refreshes                     |

Geocoding (turning `location` into coordinates) happens once and is cached for
the life of the WezTerm process; only the weather fetch repeats on
`update_interval`.

## How it works

- If `location` looks like `"lat,lon"`, it's used directly.
- If `location` is a 5-digit number, it's resolved via the free
  [Zippopotam.us](https://www.zippopotam.us/) API (US zip codes only).
- Otherwise, `location` is resolved via Open-Meteo's free geocoding API.
- Current temperature + [WMO weather code](https://open-meteo.com/en/docs) are
  then fetched from Open-Meteo's forecast API and mapped to a Nerd Font icon.

## License

MIT
