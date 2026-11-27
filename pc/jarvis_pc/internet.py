"""Internet answers from free services that need no account or key: Open-Meteo for the
weather, Wikipedia and DuckDuckGo's results (and the pages they point to) for « Qui est… ? »,
franceinfo's RSS feed for the news. Only the city or the question is sent; the client names
itself generically."""
from __future__ import annotations

import html
import json
import re
import urllib.parse
import urllib.request
import xml.etree.ElementTree as ElementTree
from html.parser import HTMLParser

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
    """(title, the first sentences of the article's introduction) for the best match, or None
    (nothing found, or a disambiguation page). One request, as on the iPhone."""
    search = urllib.parse.urlencode({
        "action": "query", "format": "json", "formatversion": 2, "generator": "search", "gsrsearch": query, "gsrlimit": 1,
        "prop": "extracts|pageprops", "ppprop": "disambiguation", "exintro": 1, "explaintext": 1,
        "exsentences": max(1, min(sentences, 10)), "redirects": 1,
    })
    pages = _json("https://fr.wikipedia.org/w/api.php?" + search).get("query", {}).get("pages", [])
    if not pages:
        return None
    page = min(pages, key=lambda p: p.get("index", 0))
    if "disambiguation" in (page.get("pageprops") or {}):
        return None
    extract = " ".join((page.get("extract") or "").split())
    if not extract:
        return None
    return page.get("title", query), extract


def english_wikipedia(french_title: str, sentences: int = 4) -> tuple[str, str] | None:
    """(title, introduction) of the English article on the same subject: other writers, a second
    opinion that needs no account. None when there is none."""
    links = urllib.parse.urlencode({"action": "query", "format": "json", "formatversion": 2, "titles": french_title,
                                    "prop": "langlinks", "lllang": "en"})
    pages = _json("https://fr.wikipedia.org/w/api.php?" + links).get("query", {}).get("pages", [])
    title = next((link["title"] for page in pages for link in page.get("langlinks", [])), None)
    if not title:
        return None
    query = urllib.parse.urlencode({"action": "query", "format": "json", "formatversion": 2, "titles": title, "prop": "extracts",
                                    "exintro": 1, "explaintext": 1, "exsentences": max(1, min(sentences, 10)), "redirects": 1})
    pages = _json("https://en.wikipedia.org/w/api.php?" + query).get("query", {}).get("pages", [])
    extract = " ".join((pages[0].get("extract") or "").split()) if pages else ""
    return (title, extract) if extract else None


def _site(url: str) -> str:
    host = urllib.parse.urlsplit(url).hostname or ""
    return host[4:] if host.startswith("www.") else host


def web_search(query: str, limit: int = 4) -> list[tuple[str, str, str]]:
    """(site, url, snippet) of DuckDuckGo's first results, without ads. Only the subject is sent.
    Empty when DuckDuckGo asks to prove a human is there: that check is never worked around."""
    page = _get("https://html.duckduckgo.com/html/?" + urllib.parse.urlencode({"q": query, "kl": "fr-fr"})).decode("utf-8", "replace")
    results = []
    for block in page.split('class="result__a"')[1:]:
        link = re.search(r'href="([^"]+)"', block)
        target = urllib.parse.parse_qs(urllib.parse.urlsplit(html.unescape(link.group(1))).query).get("uddg", [""])[0] if link else ""
        snippet = re.search(r'class="result__snippet"[^>]*>(.*?)</a>', block, re.S)
        if not target.startswith("https://") or not snippet:
            continue
        text = " ".join(html.unescape(re.sub(r"<[^>]+>", "", snippet.group(1))).split())
        if text:
            results.append((_site(target), target, text))
        if len(results) >= limit:
            break
    return results


class _Paragraphs(HTMLParser):
    """The text of a page's <p> paragraphs, without scripts, menus or footers."""
    SKIPPED = {"script", "style", "nav", "footer", "header", "aside", "noscript"}

    def __init__(self):
        super().__init__()
        self.paragraphs, self._current, self._depth, self._skip = [], [], 0, 0

    def handle_starttag(self, tag, attrs):
        if tag in self.SKIPPED:
            self._skip += 1
        elif tag == "p":
            self._depth += 1

    def handle_endtag(self, tag):
        if tag in self.SKIPPED and self._skip:
            self._skip -= 1
        elif tag == "p" and self._depth:
            self._depth -= 1
            text = " ".join("".join(self._current).split())
            if len(text) > 40:
                self.paragraphs.append(text)
            self._current = []

    def handle_data(self, data):
        if self._depth and not self._skip:
            self._current.append(data)


def page_text(url: str, timeout: float = 5, max_bytes: int = 800_000) -> str:
    """The paragraphs of an HTTPS web page, as plain text ("" for anything that is not HTML)."""
    if not url.startswith("https://"):
        return ""
    request = urllib.request.Request(url, headers={"User-Agent": USER_AGENT, "Accept-Language": "fr"})
    with urllib.request.urlopen(request, timeout=timeout) as response:
        if "html" not in (response.headers.get_content_type() or ""):
            return ""
        raw = response.read(max_bytes)
        charset = response.headers.get_content_charset() or "utf-8"
    parser = _Paragraphs()
    parser.feed(raw.decode(charset, "replace"))
    return " ".join(parser.paragraphs)


def news(limit: int = 5) -> list[str]:
    root = ElementTree.fromstring(_get("https://www.francetvinfo.fr/titres.rss"))
    titles = [item.findtext("title", "").strip() for item in root.iter("item")]
    return [title for title in titles if title][:limit]
