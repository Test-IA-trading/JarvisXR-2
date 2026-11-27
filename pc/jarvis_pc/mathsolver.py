"""Exact calculations and math read aloud, shared with the iPhone app.

Same rules as JarvisMathSolver.swift and JarvisSpokenMath.swift: arithmetic said in
French, integrals and derivatives of polynomials with sin, cos, e^x, 1/x and ln x, and
formulas turned into French words for the voice. Anything not read completely returns
None and goes to the brain."""
import math
import re
import unicodedata
from fractions import Fraction

SUP = ["⁰", "¹", "²", "³", "⁴", "⁵", "⁶", "⁷", "⁸", "⁹"]
NNBSP = "\u202f"


def rx(pattern, transform, text):
    def f(m):
        groups = [m.group(0)] + [(g if g is not None else "") for g in m.groups()]
        return transform(groups)
    return re.sub(pattern, f, text)


def rt(pattern, template, text):
    # Swift templates use $1; convert to Python \g<1>
    py = re.sub(r"\$(\d)", r"\\g<\1>", template)
    return re.sub(pattern, py, text)


def superscript(value):
    digits = "".join(SUP[int(c)] for c in str(abs(value)))
    return ("⁻" if value < 0 else "") + digits


# ---------------- JarvisSpokenMath ----------------

def wrap(part):
    t = part.strip(" ")
    single = re.match(r"^[0-9A-Za-zπ.,⁰¹²³⁴⁵⁶⁷⁸⁹^]+$", t) is not None
    return t if single else "(" + t + ")"


def plain_math(text):
    value = text
    if "\\" in value or "$" in value:
        for token in ["$$", "$", "\\(", "\\)", "\\[", "\\]", "\\left", "\\right", "\\displaystyle"]:
            value = value.replace(token, "")
        previous = None
        while previous != value:
            previous = value
            value = rx(r"\\[dt]?frac\{([^{}]*)\}\{([^{}]*)\}", lambda g: wrap(g[1]) + "/" + wrap(g[2]), value)
            value = rx(r"\\sqrt\{([^{}]*)\}", lambda g: "√" + wrap(g[1]), value)
            value = rx(r"\\(?:text|mathrm|mathit|operatorname)\{([^{}]*)\}", lambda g: g[1], value)
            value = rx(r"\^\{([^{}]*)\}", lambda g: "^" + wrap(g[1]), value)
            value = rx(r"_\{([^{}]*)\}", lambda g: "_" + g[1], value)
        symbols = [
            ("\\int", "∫"), ("\\cdot", "×"), ("\\times", "×"), ("\\div", "÷"), ("\\pi", "π"), ("\\infty", "∞"),
            ("\\leq", "≤"), ("\\geq", "≥"), ("\\neq", "≠"), ("\\le", "≤"), ("\\ge", "≥"), ("\\ne", "≠"),
            ("\\approx", "≈"), ("\\pm", "±"), ("\\sin", "sin"), ("\\cos", "cos"), ("\\tan", "tan"),
            ("\\ln", "ln"), ("\\log", "log"), ("\\exp", "exp"), ("\\,", " "), ("\\;", " "), ("\\!", ""), ("\\quad", " "),
        ]
        for latex, plain in symbols:
            value = value.replace(latex, plain)
        value = value.replace("{", "").replace("}", "")
        value = value.replace("\\", "")

    def sup(g):
        digits = g[2] if g[1] == "" else g[1]
        try:
            return superscript(int(digits))
        except ValueError:
            return g[0]
    value = rx(r"\^\((-?\d{1,2})\)|\^(-?\d{1,2})(?!\d|[.,]\d)", sup, value)
    return value


def plain_exp_char(c):
    if c in SUP:
        return str(SUP.index(c))
    if c == "⁻":
        return "-"
    if c == "ˣ":
        return "x"
    return ""


def exponent_words(e):
    if e == "2":
        return " au carré"
    if e == "3":
        return " au cube"
    if e.startswith("-"):
        return " puissance moins " + e[1:]
    return " puissance " + e


def speakable(text):
    value = text
    value = rx(r"\|([^|]{1,24})\|", lambda g: " valeur absolue de " + g[1], value)
    value = rx(r"[⁰¹²³⁴⁵⁶⁷⁸⁹⁻ˣ]+", lambda g: exponent_words("".join(plain_exp_char(c) for c in g[0])), value)
    value = rx(r"\^\s*\(?\s*(-?[0-9a-z]+)\s*\)?", lambda g: exponent_words(g[1]), value)
    symbols = [
        ("√", " racine carrée de "), ("∛", " racine cubique de "), ("∫", " intégrale de "), ("π", " pi "),
        ("∞", " l'infini "), ("≈", " égale environ "), ("≤", " inférieur ou égal à "), ("≥", " supérieur ou égal à "),
        ("≠", " différent de "), ("×", " fois "), ("·", " fois "), ("÷", " divisé par "), ("±", " plus ou moins "),
        ("′", " prime "), ("=", " égale "), ("−", " moins "), ("+", " plus "),
    ]
    for symbol, words in symbols:
        if symbol in value:
            value = value.replace(symbol, words)
    value = rt(r"([0-9a-zA-Z)])\s*\*\s*(?=[0-9a-zA-Z(])", "$1 fois ", value)

    def slash(g):
        if g[1] != "":
            return g[1]
        return (g[3] if g[2] == "" else g[2]) + " sur "
    value = rx(r"(\d+/\d+/\d+)|([0-9)]|carré|cube)\s*/\s*(?=[0-9a-zA-Z(])|([a-zA-Z])\s*/\s*(?=[0-9(])", slash, value)
    value = rt(r"(\b[a-zA-Z]|\d|\)|carré|cube)\s+-\s+(?=[0-9(]|[a-zA-Z]\b)", "$1 moins ", value)
    value = rt(r"(^|[=(]|égale)\s*-(?=\s?[0-9a-z(])", "$1 moins ", value)
    functions = [
        (r"\bsin\b\s*", "sinus de "), (r"\bcos\b\s*", "cosinus de "), (r"\btan\b\s*", "tangente de "),
        (r"\bln\b\s*", "logarithme népérien de "), (r"\bexp\b\s*", "exponentielle de "), (r"\blog\b\s*", "logarithme de "),
    ]
    for pattern, words in functions:
        value = rt(pattern, words, value)
    value = rt(r"\bd([xyzt])\b", "d $1", value)
    value = rt(r"(\d)([xyztn])\b", "$1 $2", value)
    value = rt(r"(\d)\.(\d)", "$1,$2", value)
    value = rt(r"[ \t]{2,}", " ", value)
    return value.strip(" \t")


# ---------------- JarvisMathSolver ----------------

def fold(text):
    nfd = unicodedata.normalize("NFD", text)
    return "".join(c for c in nfd if unicodedata.category(c) != "Mn").lower()


def exponent_character(c):
    return plain_exp_char(c)


def prepare(original):
    text = original.replace("’", "'")
    text = rx(r"[⁰¹²³⁴⁵⁶⁷⁸⁹⁻ˣ]+", lambda g: "^(" + "".join(exponent_character(c) for c in g[0]) + ")", text)
    symbols = [
        ("−", "-"), ("×", " * "), ("·", " * "), ("⋅", " * "), ("÷", " / "), ("√", " racine de "),
        ("∛", " racine cubique de "), ("π", " pi "), ("∫", " integrale "), ("=", " egale "),
        ("\u00a0", " "), ("\u202f", " "),
    ]
    for s, r in symbols:
        text = text.replace(s, r)
    text = fold(text)
    text = rt(r"(\d),(\d)", "$1.$2", text)
    previous = None
    while previous != text:
        previous = text
        text = rt(r"(\d) (\d{3})(?!\d)", "$1$2", text)
    text = rt(r"([a-z])-(?=[a-z])", "$1 ", text)
    text = rt(r"\b(l|d|j|m|n|s|t|c|qu)'", "$1' ", text)
    text = rt(r"[?!;:«»\"…]", " ", text)
    text = rt(r"(?<!\d)[.,]|[.,](?!\d)", " ", text)
    text = rt(r"\s+", " ", text).strip(" ")
    text = rt(r"\bpour\s?cents?\b", "%", text)
    text = numbers_from_words(text)
    return rt(r"(\d+) virgule (\d+)", "$1.$2", text)


NUMBER_WORDS = {
    "zero": 0, "un": 1, "une": 1, "deux": 2, "trois": 3, "quatre": 4, "cinq": 5, "six": 6, "sept": 7, "huit": 8, "neuf": 9,
    "dix": 10, "onze": 11, "douze": 12, "treize": 13, "quatorze": 14, "quinze": 15, "seize": 16,
    "vingt": 20, "vingts": 20, "trente": 30, "quarante": 40, "cinquante": 50, "soixante": 60,
    "cent": 100, "cents": 100, "mille": 1000, "million": 1000000, "millions": 1000000,
}
WORDS_AFTER_NUMBERS = {"plus", "moins", "fois", "divise", "divises", "multiplie", "multiplies", "sur", "puissance", "exposant",
                       "au", "x", "et", "pour", "virgule", "a"}


def numbers_from_words(text):
    words = text.split(" ") if text else []
    out = []
    i = 0
    while i < len(words):
        if words[i] not in NUMBER_WORDS:
            out.append(words[i])
            i += 1
            continue
        end = i
        run = []
        while end < len(words):
            w = words[end]
            if w in NUMBER_WORDS:
                run.append(w)
                end += 1
            elif w == "et" and run and end + 1 < len(words) and words[end + 1] in ("un", "une", "onze"):
                end += 1
            else:
                break
        if len(run) == 1 and run[0] in ("un", "une") and end < len(words) and words[end] not in WORDS_AFTER_NUMBERS:
            out.append(run[0])
            i = end
            continue
        out.append(str(value_of_number_words(run)))
        i = end
    return " ".join(out)


def value_of_number_words(words):
    total = 0
    current = 0
    previous = 0
    for w in words:
        v = NUMBER_WORDS.get(w, 0)
        if v == 100:
            current = (1 if current == 0 else current) * 100
        elif v >= 1000:
            total += (1 if current == 0 else current) * v
            current = 0
        elif v == 20 and previous == 4 and current % 100 >= 4:
            current += 76
        else:
            current += v
        previous = v
    return total + current


def is_number_token(t):
    if not t or not (t[0].isascii() and t[0].isdigit()):
        return False
    try:
        float(t)
        return True
    except ValueError:
        return False


def tokenize(text):
    tokens = []
    for m in re.finditer(r"\d+(?:\.\d+)?|[a-z']+|[+\-*/^()!%]|\S", text):
        t = m.group(0)
        if not re.match(r"^(?:\d+(?:\.\d+)?|[a-z']+|[+\-*/^()!%])$", t):
            return None
        tokens.append(t)
    return tokens


def grouped(digits):
    if len(digits) <= 4:
        return digits
    out = ""
    for off, c in enumerate(digits):
        if off > 0 and (len(digits) - off) % 3 == 0:
            out += NNBSP
        out += c
    return out


def written_number(token):
    parts = token.split(".")
    whole = grouped(parts[0])
    return whole + "," + parts[1] if len(parts) > 1 else whole


def decimal_text(value, decimals):
    text = "%.*f" % (decimals, value)
    if "." in text:
        text = text.rstrip("0")
        if text.endswith("."):
            text = text[:-1]
    if text == "-0":
        text = "0"
    return text.replace("-", "−").replace(".", ",")


def result_text(value):
    mag = abs(value)
    if mag < 1e15 and value == math.floor(value):
        digits = str(int(mag))
        neg = value < 0
        return (("−" if neg else "") + grouped(digits), ("moins " if neg else "") + digits, True)
    if mag >= 1e15 or mag < 1e-4:
        e = int(math.floor(math.log10(mag)))
        mant = value / (10 ** e)
        t = decimal_text(mant, 4) + " × 10" + superscript(e)
        return (t, t, False)
    integer_digits = max(1, int(math.floor(math.log10(mag))) + 1)
    decimals = max(0, 6 - integer_digits)
    display = decimal_text(value, decimals)
    spoken = decimal_text(value, min(decimals, 3))
    shown = float(display.replace(",", ".").replace("−", "-"))
    return (display, spoken, abs(shown - value) <= 1e-12 * max(1, mag))


def approximate(v):
    return (decimal_text(v, 4), decimal_text(v, 3))


def cap_first(s):
    return s[:1].upper() + s[1:] if s else s


ARITHMETIC_WORDS = [
    (r"\bmultiplie(?:s|r)? par\b", " * "),
    (r"\bdivise(?:s|r)? par\b", " / "),
    (r"\ba la puissance(?:\s+de)?\b", " ^ "),
    (r"\b(?:puissance|exposant)(?:\s+de)?\b", " ^ "),
    (r"\bau carree?\b", " ^ 2 "),
    (r"\bau cube\b", " ^ 3 "),
    (r"([0-9)])\s+carree?\b", "$1 ^ 2 "),
    (r"([0-9)])\s+cube\b", "$1 ^ 3 "),
    (r"\b(?:la\s+)?racine\s+cubique(?:\s+de)?\b", " cbrt "),
    (r"\b(?:la\s+)?racine(?:\s+carree?)?(?:\s+de)?\b", " sqrt "),
    (r"(?:\bpour\s?cents?|%)\s*(?:de\b|d')", " pourcentde "),
    (r"\bpour\s?cents?\b", " % "),
    (r"\bfactorielle\s+de\b", " fact "),
    (r"\bfactorielle\b", " ! "),
    (r"\bplus\b", " + "),
    (r"\bmoins\b", " - "),
    (r"\bfois\b", " * "),
]
FILLERS = set("""combien font fait ca calcule calculez calculer calcul le la les l' de d' du des resultat quel quelle est c'
egale egal egalent vaut valent donne donnent fais faites faire moi m' t' s' il te toi vous plait svp stp jarvis dis dites
peux peut pourrais tu me alors et un une exactement qu' que quoi ce cela ok hey eh""".split())
OPERATOR_TOKENS = {"+", "-", "*", "/", "^", "!", "%", "pourcentde", "sqrt", "cbrt", "fact"}


class Fail(Exception):
    def __init__(self, kind):
        self.kind = kind


class ExprParser:
    def __init__(self, tokens):
        self.t = tokens
        self.i = 0

    def at_end(self):
        return self.i >= len(self.t)

    def peek(self):
        return self.t[self.i] if self.i < len(self.t) else None

    def expression(self):
        left = self.term()
        if left is None:
            return None
        while self.peek() in ("+", "-"):
            op = self.peek()
            self.i += 1
            right = self.term()
            if right is None:
                return None
            left = ("bin", op, left, right)
        return left

    def term(self):
        left = self.unary()
        if left is None:
            return None
        while self.peek() is not None:
            op = self.peek()
            if op in ("*", "/", "pourcentde"):
                self.i += 1
                right = self.unary()
                if right is None:
                    return None
                left = ("bin", op, left, right)
            elif op in ("(", "pi", "sqrt", "cbrt"):
                right = self.unary()
                if right is None:
                    return None
                left = ("bin", "*", left, right)
            else:
                break
        return left

    def unary(self):
        if self.peek() == "-":
            self.i += 1
            inner = self.unary()
            return None if inner is None else ("neg", inner)
        if self.peek() == "+":
            self.i += 1
            return self.unary()
        return self.power()

    def power(self):
        base = self.postfix()
        if base is None:
            return None
        if self.peek() != "^":
            return base
        self.i += 1
        e = self.unary()
        return None if e is None else ("bin", "^", base, e)

    def postfix(self):
        v = self.primary()
        if v is None:
            return None
        while self.peek() in ("!", "%"):
            op = self.peek()
            self.i += 1
            v = ("fact", v) if op == "!" else ("pct", v)
        return v

    def primary(self):
        tok = self.peek()
        if tok is None:
            return None
        self.i += 1
        if is_number_token(tok):
            return ("num", float(tok), written_number(tok))
        if tok == "pi":
            return ("pi",)
        if tok == "(":
            inner = self.expression()
            if inner is None or self.peek() != ")":
                return None
            self.i += 1
            return ("group", inner)
        if tok in ("sqrt", "cbrt", "fact"):
            inner = self.unary()
            if inner is None:
                return None
            return ({"sqrt": "sqrt", "cbrt": "cbrt", "fact": "fact"}[tok], inner)
        return None


def evaluate(e):
    k = e[0]
    if k == "num":
        return e[1]
    if k == "pi":
        return math.pi
    if k == "neg":
        return -evaluate(e[1])
    if k == "group":
        return evaluate(e[1])
    if k == "sqrt":
        v = evaluate(e[1])
        if v < 0:
            raise Fail("negativeRoot")
        return math.sqrt(v)
    if k == "cbrt":
        v = evaluate(e[1])
        return math.copysign(abs(v) ** (1 / 3), v)
    if k == "fact":
        v = evaluate(e[1])
        if v < 0 or v != math.floor(v) or v > 170:
            raise Fail("undefined")
        return 1.0 if v < 2 else float(math.factorial(int(v)))
    if k == "pct":
        return evaluate(e[1]) / 100
    if k == "bin":
        op, a, b = e[1], evaluate(e[2]), evaluate(e[3])
        if op == "+":
            r = a + b
        elif op == "-":
            r = a - b
        elif op == "*":
            r = a * b
        elif op == "/":
            if b == 0:
                raise Fail("divisionByZero")
            r = a / b
        elif op == "^":
            try:
                r = a ** b
                if isinstance(r, complex):
                    raise Fail("undefined")
            except (OverflowError, ZeroDivisionError):
                raise Fail("undefined")
        elif op == "pourcentde":
            r = a / 100 * b
        else:
            raise Fail("undefined")
        if not math.isfinite(r):
            raise Fail("undefined")
        return r
    raise Fail("undefined")


def display_text(e):
    k = e[0]
    if k == "num":
        return e[2]
    if k == "pi":
        return "π"
    if k == "neg":
        return "−" + display_text(e[1])
    if k == "group":
        return "(" + display_text(e[1]) + ")"
    if k == "sqrt":
        return "√" + display_text(e[1])
    if k == "cbrt":
        return "∛" + display_text(e[1])
    if k == "fact":
        return display_text(e[1]) + "!"
    if k == "pct":
        return display_text(e[1]) + " %"
    op, a, b = e[1], e[2], e[3]
    if op == "+":
        return display_text(a) + " + " + display_text(b)
    if op == "-":
        return display_text(a) + " − " + display_text(b)
    if op == "*":
        return display_text(a) + " × " + display_text(b)
    if op == "/":
        return display_text(a) + " ÷ " + display_text(b)
    if op == "^":
        if b[0] == "num" and 0 <= b[1] < 100 and b[1] == math.floor(b[1]):
            return display_text(a) + superscript(int(b[1]))
        return display_text(a) + "^" + display_text(b)
    if op == "pourcentde":
        return display_text(a) + " % de " + display_text(b)
    return display_text(a) + " " + op + " " + display_text(b)


def spoken_text(e):
    k = e[0]
    if k == "num":
        return e[2].replace(NNBSP, "")
    if k == "pi":
        return "pi"
    if k == "neg":
        return "moins " + spoken_text(e[1])
    if k == "group":
        return spoken_text(e[1])
    if k == "sqrt":
        return "racine carrée de " + spoken_text(e[1])
    if k == "cbrt":
        return "racine cubique de " + spoken_text(e[1])
    if k == "fact":
        return spoken_text(e[1]) + " factorielle"
    if k == "pct":
        return spoken_text(e[1]) + " pour cent"
    op, a, b = e[1], e[2], e[3]
    if op == "+":
        return spoken_text(a) + " plus " + spoken_text(b)
    if op == "-":
        return spoken_text(a) + " moins " + spoken_text(b)
    if op == "*":
        return spoken_text(a) + " fois " + spoken_text(b)
    if op == "/":
        return spoken_text(a) + " divisé par " + spoken_text(b)
    if op == "^":
        if b[0] == "num" and b[1] == 2:
            return spoken_text(a) + " au carré"
        if b[0] == "num" and b[1] == 3:
            return spoken_text(a) + " au cube"
        return spoken_text(a) + " puissance " + spoken_text(b)
    if op == "pourcentde":
        return spoken_text(a) + " pour cent de " + spoken_text(b)
    return spoken_text(a) + " " + spoken_text(b)


def arithmetic(prepared):
    if not re.search(r"\d", prepared):
        return None
    text = prepared
    for p, r in ARITHMETIC_WORDS:
        text = rt(p, r, text)
    tokens = tokenize(text)
    if tokens is None:
        return None
    for i in range(len(tokens)):
        if tokens[i] not in ("sur", "x", "et"):
            continue
        if not (i > 0 and i + 1 < len(tokens)):
            continue
        before, after = tokens[i - 1], tokens[i + 1]
        left = is_number_token(before) or before in (")", "pi", "!", "%")
        right = is_number_token(after) or after in ("(", "pi", "sqrt", "cbrt", "-")
        if not (left and right):
            continue
        tokens[i] = "/" if tokens[i] == "sur" else "*" if tokens[i] == "x" else "+"
    tokens = [t for t in tokens if t not in FILLERS]
    if not any(t in OPERATOR_TOKENS for t in tokens):
        return None
    parser = ExprParser(tokens)
    expr = parser.expression()
    if expr is None or not parser.at_end():
        return None
    display = display_text(expr)
    spoken = cap_first(spoken_text(expr))
    try:
        value = evaluate(expr)
        res = result_text(value)
        if res[2]:
            return (f"{spoken} égale {res[1]}.", f"{display} = {res[0]}")
        return (f"{spoken} égale environ {res[1]}.", f"{display} ≈ {res[0]}")
    except Fail as f:
        if f.kind == "divisionByZero":
            return ("La division par zéro n'est pas définie.", f"{display} : la division par zéro n'est pas définie.")
        if f.kind == "negativeRoot":
            return ("La racine carrée d'un nombre négatif n'existe pas dans les nombres réels.", f"{display} : pas de racine carrée réelle d'un nombre négatif.")
        return ("Ce résultat est trop grand ou n'est pas défini.", f"{display} : résultat trop grand ou non défini.")


# calculus
INTEGRAL = r"\b(?:integrales?|integral|integrer|integre|integrez|primitives?)\b"
DERIVATIVE = r"\b(?:derivees?|derive|deriver|derivez)\b"
BOUND = r"((?:moins |-)?(?:\d+(?:\.\d+)?|pi))"


def has_calculus(text):
    return re.search(INTEGRAL, text) is not None or re.search(DERIVATIVE, text) is not None


def rational_decimal(text):
    parts = text.split(".")
    if len(parts) > 2 or len(parts[0]) > 9:
        return None
    try:
        whole = int(parts[0])
    except ValueError:
        return None
    if not parts[0].lstrip("-").isdigit() and not parts[0].isdigit():
        # Swift Int("x") fails; Python int would fail too
        pass
    if len(parts) == 1:
        return Fraction(whole)
    frac = parts[1]
    if not frac or len(frac) > 6 or not frac.isdigit():
        return None
    return Fraction(whole * 10 ** len(frac) + int(frac), 10 ** len(frac))


class Bound:
    def __init__(self, text):
        body = text.strip(" ")
        neg = False
        if body.startswith("moins "):
            neg = True
            body = body[6:]
        elif body.startswith("-"):
            neg = True
            body = body[1:]
        if body == "pi":
            self.value = -math.pi if neg else math.pi
            self.exact = None
            self.display = ("−" if neg else "") + "π"
            self.ok = True
            return
        r = rational_decimal(body)
        if r is None:
            self.ok = False
            return
        s = -r if neg else r
        self.value = float(s)
        self.exact = s
        self.display = ("−" if neg else "") + written_number(body)
        self.ok = True


FUNCTION_WORDS = [
    (r"\bmultiplie(?:s|r)? par\b", " * "),
    (r"\bdivise(?:s|r)? par\b", " / "),
    (r"\ba la puissance\b", " ^ "),
    (r"\b(?:puissance|exposant)\b", " ^ "),
    (r"\bau carree?\b", " ^ 2 "),
    (r"\bau cube\b", " ^ 3 "),
    (r"([0-9x)])\s+carree?\b", "$1 ^ 2 "),
    (r"([0-9x)])\s+cube\b", "$1 ^ 3 "),
    (r"\bplus\b", " + "),
    (r"\bmoins\b", " - "),
    (r"\bfois\b", " * "),
    (r"\bsur\b", " / "),
    (r"\b(?:sinus|sin)(?:\s+de)?\b", " sin "),
    (r"\b(?:cosinus|cos)(?:\s+de)?\b", " cos "),
    (r"\be\s*\^\s*\(?\s*x\s*\)?", " exp x "),
    (r"\b(?:exponentielle|exp)(?:\s+de)?\b", " exp "),
    (r"\b(?:logarithme neperien|logarithme|ln|log)(?:\s+de)?\b", " ln "),
]

ORDER = {"sin": (1, 0), "cos": (2, 0), "exp": (3, 0), "ln": (4, 0), "lnabs": (5, 0)}


def order(basis):
    if isinstance(basis, int):
        return (0, -basis)
    return ORDER[basis]


def multiply(a, b):
    c = a[0] * b[0]
    ba, bb = a[1], b[1]
    if isinstance(ba, int) and isinstance(bb, int):
        return (c, ba + bb)
    if ba == 0:
        return (c, bb)
    if bb == 0:
        return (c, ba)
    return None


def divide(a, b):
    if b[0] == 0:
        return None
    c = a[0] / b[0]
    ba, bb = a[1], b[1]
    if isinstance(ba, int) and isinstance(bb, int):
        return (c, ba - bb)
    if bb == 0:
        return (c, ba)
    return None


class TermParser:
    def __init__(self, tokens):
        self.t = tokens
        self.i = 0

    def at_end(self):
        return self.i >= len(self.t)

    def peek(self):
        return self.t[self.i] if self.i < len(self.t) else None

    def next(self):
        tok = self.peek()
        self.i += 1
        return tok

    def polynomial(self):
        terms = []
        neg = False
        if self.peek() in ("+", "-"):
            neg = self.next() == "-"
        first = self.term()
        if first is None:
            return None
        if neg:
            first = (-first[0], first[1])
        terms.append(first)
        while self.peek() in ("+", "-"):
            minus = self.next() == "-"
            t = self.term()
            if t is None:
                return None
            if minus:
                t = (-t[0], t[1])
            terms.append(t)
        return terms

    def term(self):
        term = self.factor()
        if term is None:
            return None
        while self.peek() is not None:
            tok = self.peek()
            if tok == "*":
                self.i += 1
                f = self.factor()
                term = None if f is None else multiply(term, f)
                if term is None:
                    return None
            elif tok == "/":
                self.i += 1
                f = self.factor()
                term = None if f is None else divide(term, f)
                if term is None:
                    return None
            elif tok == "x" or tok == "(" or tok in ("sin", "cos", "exp", "ln") or is_number_token(tok):
                f = self.factor()
                term = None if f is None else multiply(term, f)
                if term is None:
                    return None
            else:
                break
        return term

    def factor(self):
        tok = self.next()
        if tok is None:
            return None
        num = rational_decimal(tok) if re.match(r"^\d", tok) else None
        if num is not None:
            if self.peek() != "^":
                return (num, 0)
            self.i += 1
            e = self.exponent()
            if e is None or e < 0 or e > 12:
                return None
            return (num ** e, 0)
        if tok == "x":
            if self.peek() != "^":
                return (Fraction(1), 1)
            self.i += 1
            e = self.exponent()
            if e is None or abs(e) > 50:
                return None
            return (Fraction(1), e)
        if tok in ("sin", "cos", "exp", "ln"):
            opened = self.peek() == "("
            if opened:
                self.i += 1
            if self.next() != "x":
                return None
            if opened and self.next() != ")":
                return None
            return (Fraction(1), tok)
        if tok == "(":
            inner = self.polynomial()
            if inner is None or len(inner) != 1 or self.next() != ")":
                return None
            return inner[0]
        return None

    def exponent(self):
        opened = self.peek() == "("
        if opened:
            self.i += 1
        neg = False
        if self.peek() == "-":
            neg = True
            self.i += 1
        tok = self.next()
        if tok is None or not tok.isdigit():
            return None
        v = int(tok)
        if opened and self.next() != ")":
            return None
        return -v if neg else v


def combine(terms):
    sums = {}
    bases = []
    for c, b in terms:
        if b in sums:
            sums[b] += c
        else:
            sums[b] = c
            bases.append(b)
    out = [(sums[b], b) for b in bases if sums[b] != 0]
    return sorted(out, key=lambda t: order(t[1]))


def parse_function(raw):
    text = raw
    text = rt(r"^\s*(?:(?:de|d'|du|la|le|l'|des|cette|fonction|suivante)\s+)*", "", text)
    text = rt(r"^\s*f\s*(?:\(\s*x\s*\)|de x)\s*(?:egale\s*)?", "", text)
    text = rt(r"^\s*(?:(?:de|d'|du|la|le|l')\s+)*", "", text)
    for p, r in FUNCTION_WORDS:
        text = rt(p, r, text)
    tokens = tokenize(text)
    if not tokens:
        return None
    parser = TermParser(tokens)
    terms = parser.polynomial()
    if terms is None or not parser.at_end():
        return None
    return combine(terms)


def integral(terms):
    out = []
    for c, b in terms:
        if isinstance(b, int):
            if b == -1:
                out.append((c, "lnabs"))
            else:
                out.append((c / (b + 1), b + 1))
        elif b == "sin":
            out.append((-c, "cos"))
        elif b == "cos":
            out.append((c, "sin"))
        elif b == "exp":
            out.append((c, "exp"))
        else:
            return None
    return combine(out)


def derivative(terms):
    out = []
    for c, b in terms:
        if isinstance(b, int):
            if b == 0:
                continue
            out.append((c * b, b - 1))
        elif b == "sin":
            out.append((c, "cos"))
        elif b == "cos":
            out.append((-c, "sin"))
        elif b == "exp":
            out.append((c, "exp"))
        else:
            out.append((c, -1))
    return combine(out)


def value_at(terms, x):
    total = 0.0
    for c, b in terms:
        cf = float(c)
        if isinstance(b, int):
            if b < 0 and x == 0:
                return None
            total += cf * x ** b
        elif b == "sin":
            total += cf * math.sin(x)
        elif b == "cos":
            total += cf * math.cos(x)
        elif b == "exp":
            total += cf * math.exp(x)
        elif b == "ln":
            if x <= 0:
                return None
            total += cf * math.log(x)
        else:
            if x == 0:
                return None
            total += cf * math.log(abs(x))
    return total if math.isfinite(total) else None


def exact_definite(prim, a, b):
    total = Fraction(0)
    for c, basis in prim:
        if not isinstance(basis, int):
            return None
        if basis < 0 and (a == 0 or b == 0):
            return None
        total += c * (b ** basis - a ** basis)
    return total


def rtext(r):
    sign = "−" if r < 0 else ""
    top = abs(r.numerator)
    return f"{sign}{top}" if r.denominator == 1 else f"{sign}{top}/{r.denominator}"


def fmt_mag(c, basis):
    p, q = c.numerator, c.denominator

    def sym(s):
        lead = "" if p == 1 else str(p)
        return lead + s if q == 1 else lead + s + "/" + str(q)

    def fn(s):
        if p == 1 and q == 1:
            return s
        if q == 1:
            return f"{p} {s}"
        return f"({p}/{q}) {s}"
    if basis == 0 and isinstance(basis, int):
        return str(p) if q == 1 else f"{p}/{q}"
    if basis == 1 and isinstance(basis, int):
        return sym("x")
    if isinstance(basis, int) and basis > 1:
        return sym("x" + superscript(basis))
    if isinstance(basis, int):
        den = "x" if basis == -1 else "x" + superscript(-basis)
        return f"{p}/{den}" if q == 1 else f"{p}/({q}{den})"
    return fn({"sin": "sin x", "cos": "cos x", "exp": "eˣ", "ln": "ln x", "lnabs": "ln|x|"}[basis])


def fmt(terms):
    if not terms:
        return "0"
    text = ""
    for i, (c, b) in enumerate(terms):
        neg = c < 0
        body = fmt_mag(-c if neg else c, b)
        if i == 0:
            text = ("−" if neg else "") + body
        else:
            text += (" − " if neg else " + ") + body
    return text


def definite(terms, prim, function, prim_text, lower, upper):
    header = f"de {lower.display} à {upper.display} de {function}"
    low, high = min(lower.value, upper.value), max(lower.value, upper.value)
    singular = False
    for c, b in terms:
        if isinstance(b, int):
            if b < 0 and low <= 0 <= high:
                singular = True
        elif b in ("ln", "lnabs"):
            if low <= 0:
                singular = True
    if singular:
        return (f"L'intégrale {header} n'est pas définie : la fonction n'existe pas en 0, qui est dans l'intervalle.",
                f"∫ {header} dx : non définie, la fonction n'existe pas en 0.")
    if lower.exact is not None and upper.exact is not None:
        exact = exact_definite(prim, lower.exact, upper.exact)
        if exact is not None:
            if exact.denominator == 1:
                return (f"L'intégrale {header} vaut {rtext(exact)}.", f"∫ {header} dx = [{prim_text}] = {rtext(exact)}")
            ap = approximate(float(exact))
            return (f"L'intégrale {header} vaut {rtext(exact)}, soit environ {ap[1]}.",
                    f"∫ {header} dx = [{prim_text}] = {rtext(exact)} ≈ {ap[0]}")
    fb, fa = value_at(prim, upper.value), value_at(prim, lower.value)
    if fb is None or fa is None:
        return ("Je ne peux pas calculer cette intégrale sur cet intervalle.", f"∫ {header} dx : non calculable sur cet intervalle.")
    res = fb - fa
    if abs(res - round(res)) < 1e-9:
        whole = decimal_text(float(round(res)), 0)
        return (f"L'intégrale {header} vaut {whole}.", f"∫ {header} dx = [{prim_text}] = {whole}")
    ap = approximate(res)
    return (f"L'intégrale {header} vaut environ {ap[1]}.", f"∫ {header} dx = [{prim_text}] ≈ {ap[0]}")


def calculus(text):
    im = re.search(INTEGRAL, text)
    dm = re.search(DERIVATIVE, text)
    if im and not dm:
        is_integral, kw = True, im
    elif dm and not im:
        is_integral, kw = False, dm
    else:
        return None
    rest = text[kw.end():]
    rest = rt(r"\s*(?:s' il (?:te|vous) plait|svp|stp|jarvis)\s*$", "", rest)
    rest = rt(r"\s*par rapport (?:a|au) x\s*$", "", rest)
    rest = rt(r"\s*d\s*x\s*$", "", rest)
    rest = rest.strip(" ")
    lower = upper = None
    expression = rest
    if is_integral:
        leading = r"^(?:(?:de|d'|du|entre)\s+)?" + BOUND + r"\s+(?:a|et|jusqu'a)\s+" + BOUND + r"\s+(?:(?:de|d'|du)\s*)?(.+)$"
        trailing = r"^(.+?)\s+(?:de|entre)\s+" + BOUND + r"\s+(?:a|et|jusqu'a)\s+" + BOUND + r"$"
        m = re.search(leading, rest)
        if m and Bound(m.group(1)).ok and Bound(m.group(2)).ok:
            lower, upper, expression = Bound(m.group(1)), Bound(m.group(2)), m.group(3)
        else:
            m = re.search(trailing, rest)
            if m and Bound(m.group(2)).ok and Bound(m.group(3)).ok:
                lower, upper, expression = Bound(m.group(2)), Bound(m.group(3)), m.group(1)
    terms = parse_function(expression)
    if not terms:
        return None
    function = fmt(terms)
    if not is_integral:
        d = derivative(terms)
        if d is None:
            return None
        r = fmt(d)
        return (f"La dérivée de {function} est {r}.", f"Dérivée de {function} : {r}")
    prim = integral(terms)
    if prim is None:
        return None
    prim_text = fmt(prim)
    if lower is None:
        integrand = f"({function})" if len(terms) > 1 else function
        return (f"Une primitive de {function} est {prim_text} + C, où C est une constante.", f"∫ {integrand} dx = {prim_text} + C")
    return definite(terms, prim, function, prim_text, lower, upper)


def answer(original):
    text = prepare(original)
    if not text:
        return None
    if has_calculus(text):
        return calculus(text)
    return arithmetic(text)
