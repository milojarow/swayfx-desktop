#!/usr/bin/env python
"""Script for the Waybar weather module using wttr.in."""

import getopt
import json
import locale
import sys
import urllib.parse
import requests
import configparser
from os import path, environ
from datetime import datetime
from pathlib import Path

# Weather code mapping to emoji icons
# Based on wttr.in weather codes: https://github.com/chubin/wttr.in/blob/master/lib/constants.py
WEATHER_CODES = {
    "113": "☀️",   # Clear/Sunny
    "116": "⛅",   # Partly Cloudy
    "119": "☁️",   # Cloudy
    "122": "☁️",   # Overcast
    "143": "🌫️",  # Mist
    "176": "🌦️",  # Patchy rain nearby
    "179": "🌨️",  # Patchy snow nearby
    "182": "🌧️",  # Patchy sleet nearby
    "185": "🌧️",  # Patchy freezing drizzle nearby
    "200": "⛈️",   # Thundery outbreaks nearby
    "227": "🌨️",  # Blowing snow
    "230": "🌨️",  # Blizzard
    "248": "🌫️",  # Fog
    "260": "🌫️",  # Freezing fog
    "263": "🌦️",  # Patchy light drizzle
    "266": "🌦️",  # Light drizzle
    "281": "🌧️",  # Freezing drizzle
    "284": "🌧️",  # Heavy freezing drizzle
    "293": "🌦️",  # Patchy light rain
    "296": "🌦️",  # Light rain
    "299": "🌧️",  # Moderate rain at times
    "302": "🌧️",  # Moderate rain
    "305": "🌧️",  # Heavy rain at times
    "308": "🌧️",  # Heavy rain
    "311": "🌧️",  # Light freezing rain
    "314": "🌧️",  # Moderate or heavy freezing rain
    "317": "🌨️",  # Light sleet
    "320": "🌨️",  # Moderate or heavy sleet
    "323": "🌨️",  # Patchy light snow
    "326": "🌨️",  # Light snow
    "329": "🌨️",  # Patchy moderate snow
    "332": "🌨️",  # Moderate snow
    "335": "🌨️",  # Patchy heavy snow
    "338": "🌨️",  # Heavy snow
    "350": "🌧️",  # Ice pellets
    "353": "🌦️",  # Light rain shower
    "356": "🌧️",  # Moderate or heavy rain shower
    "359": "🌧️",  # Torrential rain shower
    "362": "🌨️",  # Light sleet showers
    "365": "🌨️",  # Moderate or heavy sleet showers
    "368": "🌨️",  # Light snow showers
    "371": "🌨️",  # Moderate or heavy snow showers
    "374": "🌧️",  # Light showers of ice pellets
    "377": "🌧️",  # Moderate or heavy showers of ice pellets
    "386": "⛈️",   # Patchy light rain in area with thunder
    "389": "⛈️",   # Moderate or heavy rain in area with thunder
    "392": "⛈️",   # Patchy light snow in area with thunder
    "395": "⛈️",   # Moderate or heavy snow in area with thunder
}

# Cache configuration
CACHE_FILE = Path.home() / ".cache" / "weather_data.json"
CACHE_MAX_AGE_HOURS = 24

config_path = path.join(
    environ.get('APPDATA') or
    environ.get('XDG_CONFIG_HOME') or
    path.join(environ['HOME'], '.config'),
    "weather.cfg"
)

config = configparser.ConfigParser()
config.read(config_path)

# Set default locale
locale.setlocale(locale.LC_ALL, "")
current_locale, _ = locale.getlocale(locale.LC_NUMERIC)

# Read config or use defaults
city = config.get('DEFAULT', 'city', fallback='')
temperature = config.get('DEFAULT', 'temperature', fallback='C')
distance = config.get('DEFAULT', 'distance', fallback='km')

# Override with US defaults if applicable
if current_locale == "en_US":
    temperature = temperature or "F"
    distance = distance or "miles"

# Parse command line arguments
argument_list = sys.argv[1:]
options = "t:c:d:"
long_options = ["temperature=", "city=", "distance="]

try:
    args, values = getopt.getopt(argument_list, options, long_options)

    for current_argument, current_value in args:
        if current_argument in ("-t", "--temperature"):
            temperature = current_value[0].upper()
            if temperature not in ("C", "F"):
                msg = "temperature unit is neither (C)elsius, nor (F)ahrenheit"
                raise RuntimeError(msg, temperature)
        elif current_argument in ("-d", "--distance"):
            distance = current_value.lower()
            if distance not in ("km", "miles"):
                msg = "distance unit is neither km, nor miles"
                raise RuntimeError(msg)
        elif current_argument in ("-c", "--city"):
            city = current_value
except getopt.error as err:
    print(str(err))
    sys.exit(1)

def save_cache(data):
    """Save weather data to cache file."""
    cache_data = {
        "timestamp": datetime.now().isoformat(),
        "data": data
    }
    try:
        CACHE_FILE.parent.mkdir(parents=True, exist_ok=True)
        with open(CACHE_FILE, 'w') as f:
            json.dump(cache_data, f)
    except Exception:
        pass  # Fail silently if can't write cache

def load_cache():
    """Load cached weather data if still valid."""
    try:
        if not CACHE_FILE.exists():
            return None

        with open(CACHE_FILE, 'r') as f:
            cache_data = json.load(f)

        # Check cache age
        cached_time = datetime.fromisoformat(cache_data['timestamp'])
        age_hours = (datetime.now() - cached_time).total_seconds() / 3600

        if age_hours > CACHE_MAX_AGE_HOURS:
            return None  # Cache too old

        # Add staleness indicator
        data = cache_data['data'].copy()
        if age_hours > 6:
            data['text'] = "⟳ " + data['text']
            data['tooltip'] = f"⚠️ Cached data ({int(age_hours)}h old)\n\n{data['tooltip']}"
        elif age_hours > 2:
            data['text'] = "⟳ " + data['text']

        return data
    except Exception:
        return None  # Invalid cache

# Build wttr.in URL
# If no city specified, wttr.in will auto-detect based on IP
url = f"https://wttr.in/{urllib.parse.quote(city) if city else ''}?format=j1"

try:
    response = requests.get(url, timeout=30)
    response.raise_for_status()
    data = response.json()

    # Extract current condition
    current = data['current_condition'][0]

    # Get temperature in correct unit
    temp = current['temp_C'] if temperature == 'C' else current['temp_F']
    temp_unit = '°C' if temperature == 'C' else '°F'

    # Get weather icon from code
    weather_code = current['weatherCode']
    icon = WEATHER_CODES.get(weather_code, "🌡️")

    # Get weather description
    weather_desc = current['weatherDesc'][0]['value']

    # Get location info
    location = data['nearest_area'][0]
    area_name = location['areaName'][0]['value']
    country = location['country'][0]['value']

    # Get wind info
    if distance == "km":
        wind_speed = current['windspeedKmph']
        wind_unit = "km/h"
    else:
        wind_speed = current['windspeedMiles']
        wind_unit = "mph"

    wind_dir = current['winddir16Point']
    humidity = current['humidity']
    feels_like = current['FeelsLikeC'] if temperature == 'C' else current['FeelsLikeF']

    # Format output for waybar
    output = {
        "text": f"{icon} {temp}{temp_unit}",
        "tooltip": f"{area_name}, {country}\n{weather_desc}\nFeels like: {feels_like}{temp_unit}\nWind: {wind_speed} {wind_unit} {wind_dir}\nHumidity: {humidity}%",
        "class": "weather"
    }

    save_cache(output)
    print(json.dumps(output))

except (requests.exceptions.RequestException, KeyError, ValueError) as err:
    # Try to use cached data first
    cached_data = load_cache()

    if cached_data:
        # Return cached data
        print(json.dumps(cached_data))
        sys.exit(0)  # Exit with success - waybar should keep showing cached data
    else:
        # No cache available, show N/A
        output = {
            "text": "🌡️ N/A",
            "tooltip": f"Weather data unavailable\nError: {str(err)}",
            "class": "weather-error"
        }
        print(json.dumps(output))
        sys.exit(0)  # Exit with success - waybar should keep showing error state
