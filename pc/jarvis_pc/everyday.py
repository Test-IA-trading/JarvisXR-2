"""Unit conversions and date questions, shared with the iPhone app (same rules as
JarvisEverydayAnswers.swift): exact, and without a network."""
from datetime import date, timedelta

from . import mathsolver as mp

U = [
    ("longueur", 0.001, "millimètre", "millimètres", "mm", ["mm", "millimetre", "millimetres"]),
    ("longueur", 0.01, "centimètre", "centimètres", "cm", ["cm", "centimetre", "centimetres"]),
    ("longueur", 1, "mètre", "mètres", "m", ["m", "metre", "metres"]),
    ("longueur", 1000, "kilomètre", "kilomètres", "km", ["km", "kilometre", "kilometres"]),
    ("longueur", 0.0254, "pouce", "pouces", "in", ["pouce", "pouces", "inch", "inches"]),
    ("longueur", 0.3048, "pied", "pieds", "ft", ["pied", "pieds", "foot", "feet", "ft"]),
    ("longueur", 0.9144, "yard", "yards", "yd", ["yard", "yards"]),
    ("longueur", 1609.344, "mile", "miles", "mi", ["mile", "miles"]),
    ("longueur", 1852, "mille marin", "milles marins", "NM", ["mille marin", "milles marins", "mille nautique", "milles nautiques"]),
    ("masse", 0.000001, "milligramme", "milligrammes", "mg", ["mg", "milligramme", "milligrammes"]),
    ("masse", 0.001, "gramme", "grammes", "g", ["g", "gramme", "grammes"]),
    ("masse", 1, "kilogramme", "kilogrammes", "kg", ["kg", "kilo", "kilos", "kilogramme", "kilogrammes"]),
    ("masse", 1000, "tonne", "tonnes", "t", ["tonne", "tonnes"]),
    ("masse", 0.45359237, "livre", "livres", "lb", ["livre", "livres", "lb", "lbs", "pound", "pounds"]),
    ("masse", 0.028349523125, "once", "onces", "oz", ["once", "onces", "oz"]),
    ("volume", 0.001, "millilitre", "millilitres", "ml", ["ml", "millilitre", "millilitres"]),
    ("volume", 0.01, "centilitre", "centilitres", "cl", ["cl", "centilitre", "centilitres"]),
    ("volume", 1, "litre", "litres", "L", ["l", "litre", "litres"]),
    ("volume", 1000, "mètre cube", "mètres cubes", "m³", ["metre cube", "metres cubes", "m^(3)", "m3"]),
    ("volume", 3.785411784, "gallon", "gallons", "gal", ["gallon", "gallons"]),
    ("temps", 1, "seconde", "secondes", "s", ["s", "seconde", "secondes"]),
    ("temps", 60, "minute", "minutes", "min", ["min", "minute", "minutes"]),
    ("temps", 3600, "heure", "heures", "h", ["h", "heure", "heures"]),
    ("temps", 86400, "jour", "jours", "j", ["jour", "jours"]),
    ("temps", 604800, "semaine", "semaines", "sem.", ["semaine", "semaines"]),
    ("temps", 31557600, "an", "ans", "an", ["an", "ans", "annee", "annees"]),
    ("vitesse", 1 / 3.6, "kilomètre par heure", "kilomètres par heure", "km/h", ["km/h", "kmh", "kilometre par heure", "kilometres par heure", "kilometre heure", "kilometres heure"]),
    ("vitesse", 1, "mètre par seconde", "mètres par seconde", "m/s", ["m/s", "metre par seconde", "metres par seconde"]),
    ("vitesse", 0.44704, "mile par heure", "miles par heure", "mph", ["mph", "mile par heure", "miles par heure", "miles heure"]),
    ("vitesse", 1852.0 / 3600.0, "nœud", "nœuds", "kn", ["noeud", "noeuds"]),
    ("surface", 1, "mètre carré", "mètres carrés", "m²", ["metre carre", "metres carres", "m^(2)", "m2"]),
    ("surface", 1_000_000, "kilomètre carré", "kilomètres carrés", "km²", ["kilometre carre", "kilometres carres", "km^(2)", "km2"]),
    ("surface", 100, "are", "ares", "a", ["are", "ares"]),
    ("surface", 10_000, "hectare", "hectares", "ha", ["hectare", "hectares", "ha"]),
    ("surface", 4046.8564224, "acre", "acres", "ac", ["acre", "acres"]),
    ("données", 1, "octet", "octets", "o", ["octet", "octets"]),
    ("données", 1e3, "kilooctet", "kilooctets", "ko", ["ko", "kilooctet", "kilooctets", "kilo octet", "kilo octets"]),
    ("données", 1e6, "mégaoctet", "mégaoctets", "Mo", ["mo", "megaoctet", "megaoctets", "mega octet", "mega octets"]),
    ("données", 1e9, "gigaoctet", "gigaoctets", "Go", ["go", "gigaoctet", "gigaoctets", "giga octet", "giga octets"]),
    ("données", 1e12, "téraoctet", "téraoctets", "To", ["to", "teraoctet", "teraoctets", "tera octet", "tera octets"]),
    ("température", 1, "degré Celsius", "degrés Celsius", "°C", ["degre celsius", "degres celsius", "celsius", "°c", "degre", "degres"]),
    ("température", 1, "degré Fahrenheit", "degrés Fahrenheit", "°F", ["degre fahrenheit", "degres fahrenheit", "fahrenheit", "°f"]),
    ("température", 1, "kelvin", "kelvins", "K", ["kelvin", "kelvins"]),
]
FILLERS = set("""convertis convertir convertit convertissez conversion combien font fait ca de d' en vers dans pour y a t il est c'
egale s' te vous plait svp stp jarvis les des le la l' un une quel quelle nombre donne moi dis peux tu me m' fais font-ils ok alors
exactement environ valent vaut equivalent egalent""".split())
ALIAS = sorted([(a.split(" "), i) for i, u in enumerate(U) for a in u[5]], key=lambda e: -len(e[0]))


def convert(v, f, t):
    if f[0] != "température":
        return v * f[1] / t[1]
    c = (v - 32) * 5 / 9 if f[4] == "°F" else v - 273.15 if f[4] == "K" else v
    return c * 9 / 5 + 32 if t[4] == "°F" else c + 273.15 if t[4] == "K" else c


def spoken_value(v):
    m = abs(v)
    d = 0 if m >= 1000 else 1 if m >= 100 else 2 if m >= 1 else 4
    return mp.decimal_text(v, d)


def convert_answer(original):
    text = mp.prepare(original)
    text = mp.rt(r"(\d)([a-z°])", "$1 $2", text)
    tokens = text.split(" ") if text else []
    if not any(mp.is_number_token(t) or t in ("un", "une") for t in tokens):
        return None
    mentions = []
    i = 0
    while i < len(tokens):
        match = next((e for e in ALIAS if i + len(e[0]) <= len(tokens) and tokens[i:i + len(e[0])] == e[0]), None)
        if match:
            mentions.append((match[1], i, i + len(match[0])))
            i += len(match[0])
        else:
            i += 1
    if len(mentions) != 2:
        return None

    def amount(pos):
        if pos < 1:
            return None
        t = tokens[pos - 1]
        if mp.is_number_token(t):
            v, w = float(t), mp.written_number(t)
        elif t in ("un", "une"):
            v, w = 1.0, "1"
        else:
            return None
        length = 1
        if pos >= 2 and tokens[pos - 2] in ("moins", "-"):
            v, w, length = -v, "−" + w, 2
        return v, w, length
    a = amount(mentions[0][1])
    if a:
        src, tgt, q = mentions[0], mentions[1], a
    else:
        a = amount(mentions[1][1])
        if not a:
            return None
        src, tgt, q = mentions[1], mentions[0], a
    f, t = U[src[0]], U[tgt[0]]
    if f[0] != t[0] or src[0] == tgt[0]:
        return None
    used = set(range(src[1], src[2])) | set(range(tgt[1], tgt[2])) | {src[1] - o for o in range(1, q[2] + 1)}
    for p, tok in enumerate(tokens):
        if p not in used and tok not in FILLERS:
            return None
    r = convert(q[0], f, t)
    fname = f[3] if abs(q[0]) >= 2 else f[2]
    tname = t[3] if abs(r) >= 2 else t[2]
    verb = "font" if abs(q[0]) >= 2 else "fait"
    fl = fname if f[0] == "temps" else f[4]
    tl = tname if t[0] == "temps" else t[4]
    return (f"{q[1]} {fname} {verb} {spoken_value(r)} {tname}.", f"{q[1]} {fl} = {mp.decimal_text(r, 4)} {tl}")


MONTHS = ["janvier", "fevrier", "mars", "avril", "mai", "juin", "juillet", "aout", "septembre", "octobre", "novembre", "decembre"]
MONTH_NAMES = ["janvier", "février", "mars", "avril", "mai", "juin", "juillet", "août", "septembre", "octobre", "novembre", "décembre"]
WEEKDAYS = ["lundi", "mardi", "mercredi", "jeudi", "vendredi", "samedi", "dimanche"]  # Python weekday()
NAMED = [
    (["noel"], 12, 25, "Noël"), (["jour", "de", "l'", "an"], 1, 1, "Le jour de l'an"), (["nouvel", "an"], 1, 1, "Le nouvel an"),
    (["saint", "valentin"], 2, 14, "La Saint-Valentin"), (["halloween"], 10, 31, "Halloween"), (["toussaint"], 11, 1, "La Toussaint"),
    (["fete", "nationale"], 7, 14, "La fête nationale"), (["fete", "du", "travail"], 5, 1, "La fête du Travail"),
    (["armistice"], 11, 11, "L'armistice"), (["reveillon"], 12, 31, "Le réveillon"),
]


def full(d):
    return f"{WEEKDAYS[d.weekday()]} {'1er' if d.day == 1 else d.day} {MONTH_NAMES[d.month - 1]} {d.year}"


def add_months(d, n):
    m = d.month - 1 + n
    y = d.year + m // 12
    m = m % 12 + 1
    import calendar
    day = min(d.day, calendar.monthrange(y, m)[1])
    return date(y, m, day)


def offset_question(tokens):
    for i in range(len(tokens)):
        fut = tokens[i] == "dans"
        past = i + 2 < len(tokens) and tokens[i:i + 3] == ["il", "y", "a"]
        if not (fut or past):
            continue
        ni = i + 1 if fut else i + 3
        if ni + 1 >= len(tokens) or not mp.is_number_token(tokens[ni]) or not tokens[ni].isdigit():
            continue
        v = int(tokens[ni])
        u = tokens[ni + 1]
        if u in ("jour", "jours"):
            comp, word = "day", "jours" if v > 1 else "jour"
        elif u in ("semaine", "semaines"):
            comp, word = "week", "semaines" if v > 1 else "semaine"
        elif u == "mois":
            comp, word = "month", "mois"
        elif u in ("an", "ans", "annee", "annees"):
            comp, word = "year", "ans" if v > 1 else "an"
        else:
            continue
        return comp, v if fut else -v, f"{v} {word}"
    return None


def date_mention(tokens, today):
    def resolve(m, d, y):
        try:
            if y:
                return date(y, m, d)
            this = date(today.year, m, d)
            return this if this >= today else date(today.year + 1, m, d)
        except ValueError:
            return None

    def year_after(i):
        if i < len(tokens) and len(tokens[i]) == 4 and tokens[i].isdigit() and 1600 <= int(tokens[i]) <= 2400:
            return int(tokens[i])
        return None
    for words, m, d, name in NAMED:
        for s in range(len(tokens)):
            if s + len(words) <= len(tokens) and tokens[s:s + len(words)] == words:
                dt = resolve(m, d, year_after(s + len(words)))
                return (dt, name) if dt else None
    for i, tok in enumerate(tokens):
        if tok in MONTHS and i >= 1:
            dt_tok = tokens[i - 1]
            if dt_tok in ("1er", "premier"):
                d = 1
            elif dt_tok.isdigit() and 1 <= int(dt_tok) <= 31:
                d = int(dt_tok)
            else:
                continue
            y = year_after(i + 1)
            dt = resolve(MONTHS.index(tok) + 1, d, y)
            if not dt:
                return None
            return dt, f"Le {'1er' if d == 1 else d} {MONTH_NAMES[MONTHS.index(tok)]}{' ' + str(y) if y else ''}"
    return None


def date_answer(original, today):
    text = mp.prepare(original)
    tokens = text.split(" ") if text else []
    padded = f" {text} "

    def has(p):
        return f" {p} " in padded
    off = offset_question(tokens)
    if off and (has("quel jour") or has("quelle date") or has("serons") or has("sera") or has("etions") or has("etait")):
        comp, v, phrase = off
        if comp == "day":
            d = today + timedelta(days=v)
        elif comp == "week":
            d = today + timedelta(weeks=v)
        elif comp == "month":
            d = add_months(today, v)
        else:
            d = add_months(today, 12 * v)
        w = full(d)
        if v >= 0:
            return (f"Dans {phrase}, nous serons le {w}.", f"Dans {phrase} : {w}")
        return (f"Il y a {phrase}, nous étions le {w}.", f"Il y a {phrase} : {w}")
    tgt = date_mention(tokens, today)
    if not tgt:
        return None
    dt, name = tgt
    days = (dt - today).days
    w = full(dt)
    if has("combien de jours"):
        if days == 0:
            return (f"{name}, c'est aujourd'hui !", f"{name} : aujourd'hui, {w}")
        if days == 1:
            return (f"{name}, c'est demain, le {w}.", f"{name} : demain, {w}")
        if days > 1:
            return (f"{name} est dans {days} jours, le {w}.", f"{name} : dans {days} jours, {w}")
        return (f"{name} était il y a {-days} jours, le {w}.", f"{name} : il y a {-days} jours, {w}")
    if has("quel jour") or has("tombe") or has("tombera") or has("tombait"):
        verb = "tombait" if days < 0 else "tombe" if days == 0 else "tombera"
        return (f"{name} {verb} un {WEEKDAYS[dt.weekday()]} : le {w}.", f"{name} : {w}")
    return None
