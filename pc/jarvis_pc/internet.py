"""Internet answers from free services that need no account or key: Open-Meteo for the
weather, Wikipedia for « Qui est… ? », franceinfo's RSS feed for the news. Only the city
or the question is sent; the client names itself generically."""
from __future__ import annotations

import json
import re
import urllib.parse
import urllib.request
import xml.etree.ElementTree as ElementTree

USER_AGENT = "JarvisPC/1.0 (assistant personnel local)"

WEATHER_CODES = {
    0: "ciel dégagé", 1: "ciel plutôt dégagé", 2: "partiellement nuageux", 3: "ciel couvert",
    45: "brouillard", 48: "brouillard givrant", 51: "bruine légère", 53: "bruine", 55: "bruine dense",
    56: "bruine verglaçante", 57: "bruine verglaçante dense", 61: "pluie faible", 63: "pluie", 65: "forte pluie",
    66: "pluie verglaçante", 67: "forte pluie verglaçante", 71: "neige faible", 73: "neige", 75: "forte neige",
    77: "grains de neige", 80: "averses", 81: "averses", 82: "fortes averses", 85: "averses de neige",
    86: "fortes averses de neige", 95: "orage", 96: "orage avec grêle", 99: "orage avec forte grêle",
}


def _get(url: str, timeout: float = 8) -> bytes:
    request = urllib.request.Request(url, headers={"User-Agent": USER_AGENT})
    with urllib.request.urlopen(request, timeout=timeout) as response:
        return response.read()


def _json(url: str) -> dict | list:
    return json.loads(_get(url).decode("utf-8"))


def geocode(city: str) -> dict | None:
    query = urllib.parse.urlencode({"name": city, "count": 1, "language": "fr", "format": "json"})
    results = _json("https://geocoding-api.open-meteo.com/v1/search?" + query).get("results") or []
    if not results:
        return None
    place = results[0]
    return {"name": place.get("name", city), "latitude": place["latitude"], "longitude": place["longitude"], "country": place.get("country", "")}


def weather(city: str, tomorrow: bool = False) -> str:
    place = geocode(city)
    if place is None:
        return f"Je ne trouve pas la ville « {city} »."
    query = urllib.parse.urlencode({
        "latitude": place["latitude"], "longitude": place["longitude"],
        "current": "temperature_2m,apparent_temperature,weather_code,wind_speed_10m",
        "daily": "weather_code,temperature_2m_max,temperature_2m_min,precipitation_probability_max",
        "timezone": "auto", "forecast_days": 3,
    })
    data = _json("https://api.open-meteo.com/v1/forecast?" + query)
    daily = data["daily"]
    day = 1 if tomorrow else 0
    low = round(daily["temperature_2m_min"][day])
    high = round(daily["temperature_2m_max"][day])
    rain = daily["precipitation_probability_max"][day]
    sky = WEATHER_CODES.get(daily["weather_code"][day], "temps variable")
    rain_text = f", {rain} % de risque de pluie" if rain is not None else ""
    if tomorrow:
        return f"Demain à {place['name']} : {sky}, entre {low} et {high} degrés{rain_text}."
    current = data["current"]
    now_sky = WEATHER_CODES.get(current["weather_code"], sky)
    return (f"À {place['name']}, il fait {round(current['temperature_2m'])} degrés, {now_sky}. "
            f"Aujourd'hui, entre {low} et {high} degrés{rain_text}.")


def wikipedia(query: str, sentences: int = 2) -> tuple[str, str] | None:
    """(title, the first sentences of the article) for the best match, or None."""
    search = urllib.parse.urlencode({"action": "query", "list": "search", "srsearch": query, "srlimit": 1, "format": "json"})
    hits = _json("https://fr.wikipedia.org/w/api.php?" + search).get("query", {}).get("search", [])
    if not hits:
        return None
    title = hits[0]["title"]
    summary = _json("https://fr.wikipedia.org/api/rest_v1/page/summary/" + urllib.parse.quote(title.replace(" ", "_")))
    extract = (summary.get("extract") or "").strip()
    if not extract:
        return None
    parts = re.split(r"(?<=[.!?])\s+", extract)
    return title, " ".join(parts[:sentences])


def news(limit: int = 5) -> list[str]:
    root = ElementTree.fromstring(_get("https://www.francetvinfo.fr/titres.rss"))
    titles = [item.findtext("title", "").strip() for item in root.iter("item")]
    return [title for title in titles if title][:limit]
