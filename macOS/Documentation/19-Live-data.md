# Live time, date and weather

Iris receives a fresh local clock reading with every chat request, including the current weekday, date, time, IANA time zone, UTC offset and UTC instant. It uses the Mac's clock, not training knowledge or a network clock service. Named-city world-clock questions resolve through macOS's time-zone database, including daylight-saving changes. Ambiguous abbreviations such as IST are not guessed.

Weather questions such as “What's the weather in Tokyo tomorrow?” fetch Open-Meteo geocoding and forecast data before the selected chat model writes an answer. This works with OpenAI, Gemini and LM Studio. The request status shows Checking live weather. Weather data has a dedicated context section and is not lost when user attachments are truncated.

## Settings

Settings → Live data shows a ticking local clock and provides:
- An option to enable or disable weather lookups.
- City search and explicit selection of a default weather city.
- Removal of the saved city.
- Celsius/km/h or Fahrenheit/mph units.
- A source link and a clear description of supported live facts.

No GPS permission or IP location lookup is used. Users can name a city directly without saving it. If a city is missing, ambiguous or cannot be found, Iris asks for a clearer place rather than inventing weather. Successful weather locations are remembered in the current conversation's in-memory context for short follow-ups such as “What about tomorrow?”

## Data and boundaries

The weather adapter requests modelled current conditions, temperature, feels-like temperature, humidity, precipitation and wind, plus seven daily forecasts with highs/lows, rain chance, sunrise and sunset. Forecasts and current model estimates are distinguished from measured observations. Readings include the place, time zone, validity time, fetch time and units. A weather source link is appended to a successful weather answer if the model omits it.

Weather is cached for at most five minutes per location/unit choice; the clock is regenerated per request. Current data more than three hours from the Mac's clock is rejected. Requests use bounded fixed HTTPS endpoints, 12-second timeouts, response-size limits, cancellation checks and validated coordinates. Only city names and weather coordinates go to Open-Meteo; chat text, files and credentials are not sent to the weather service.

English weather/world-clock questions are recognized before the model call. This is a bounded live-data adapter, not general web browsing. Historical weather, severe-weather alerts, news, stocks and prices are not connected. The model is explicitly instructed to disclose unavailable live data instead of substituting typical climate or training knowledge.

Open-Meteo's public endpoint is used for this personal build. Its free service is for non-commercial use; distribution as a commercial product requires the appropriate service arrangement. Attribution is included in settings and weather responses.

## Verification

The native Debug build succeeds. All eight new live-data tests pass independently, covering time zones/DST, question routing, city lookup, request units, weather timestamps/sources, caching, follow-up context, ambiguous locations and offline failures. A live public Berlin check returned valid geocoding and a seven-day forecast using the exact endpoint parameters. No paid model or voice call was used.

Full-package regression runs encountered unrelated attachment-fixture failures caused by macOS reporting ENOSPC (disk full). Iris's duplicate and obsolete generated build caches were removed, and the installer now excludes .build caches; the full suite still encountered temp-file disk errors. No user source material or personal files were removed. This limitation is not reported as a passing full-suite run.

Sources:
- https://open-meteo.com/en/docs
- https://open-meteo.com/en/docs/geocoding-api
- https://open-meteo.com/en/pricing
