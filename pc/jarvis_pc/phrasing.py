"""Free phrasing → the plain wording Jarvis's commands know, so the user need not learn
one sentence per command:

    « Est-ce que tu pourrais m'ouvrir YouTube, s'il te plaît ? »  → « ouvre-moi YouTube ? »
    « J'aimerais que tu appelles Paul »                           → « appelle Paul »
    « Tu peux me dire ce qu'est l'arrêt Blanco ? »                → « qu'est-ce que l'arrêt Blanco ? »

Only the start of the sentence is rewritten (politeness is dropped anywhere); the rest
keeps the user's own words, accents and capitals. When nothing is recognised, the text
comes back unchanged. The iPhone applies the same rules (JarvisPhrasing.swift)."""
from __future__ import annotations

import re

# Infinitive → imperative (« tu peux ouvrir… » → « ouvre… »).
INFINITIVES = {
    "ouvrir": "ouvre", "lancer": "lance", "démarrer": "démarre", "demarrer": "demarre", "appeler": "appelle",
    "téléphoner": "téléphone", "telephoner": "telephone", "rappeler": "rappelle", "envoyer": "envoie",
    "écrire": "écris", "ecrire": "ecris", "dire": "dis", "mettre": "mets", "remettre": "remets", "montrer": "montre",
    "afficher": "affiche", "chercher": "cherche", "rechercher": "recherche", "trouver": "trouve", "jouer": "joue",
    "lire": "lis", "relire": "relis", "prendre": "prends", "noter": "note", "calculer": "calcule", "donner": "donne",
    "faire": "fais", "régler": "règle", "regler": "regle", "programmer": "programme", "allumer": "allume",
    "éteindre": "éteins", "eteindre": "eteins", "fermer": "ferme", "arrêter": "arrête", "arreter": "arrete",
    "supprimer": "supprime", "effacer": "efface", "ajouter": "ajoute", "créer": "crée", "creer": "cree",
    "enregistrer": "enregistre", "traduire": "traduis", "convertir": "convertis", "compter": "compte",
    "expliquer": "explique", "raconter": "raconte", "parler": "parle", "aller": "va", "passer": "passe",
    "regarder": "regarde", "vérifier": "vérifie", "verifier": "verifie", "annuler": "annule", "reprendre": "reprends",
    "préparer": "prépare", "preparer": "prepare", "répéter": "répète", "repeter": "repete", "prévenir": "préviens",
    "prevenir": "previens", "demander": "demande", "indiquer": "indique", "couper": "coupe", "activer": "active",
    "désactiver": "désactive", "desactiver": "desactive", "baisser": "baisse", "monter": "monte",
    "augmenter": "augmente", "résumer": "résume", "resumer": "resume", "définir": "définis", "definir": "definis",
    "souvenir": "souviens", "rappeller": "rappelle",
}
# Second person subjunctive → imperative (« j'aimerais que tu appelles… » → « appelle… »).
SUBJUNCTIVES = {
    "ouvres": "ouvre", "lances": "lance", "démarres": "démarre", "demarres": "demarre", "appelles": "appelle",
    "téléphones": "téléphone", "telephones": "telephone", "rappelles": "rappelle", "envoies": "envoie",
    "écrives": "écris", "ecrives": "ecris", "dises": "dis", "mettes": "mets", "montres": "montre",
    "affiches": "affiche", "cherches": "cherche", "recherches": "recherche", "trouves": "trouve", "joues": "joue",
    "lises": "lis", "prennes": "prends", "notes": "note", "calcules": "calcule", "donnes": "donne", "fasses": "fais",
    "règles": "règle", "programmes": "programme", "allumes": "allume", "éteignes": "éteins", "eteignes": "eteins",
    "fermes": "ferme", "arrêtes": "arrête", "arretes": "arrete", "supprimes": "supprime", "effaces": "efface",
    "ajoutes": "ajoute", "crées": "crée", "enregistres": "enregistre", "traduises": "traduis", "expliques": "explique",
    "racontes": "raconte", "parles": "parle", "ailles": "va", "passes": "passe", "regardes": "regarde",
    "vérifies": "vérifie", "verifies": "verifie", "annules": "annule", "prépares": "prépare", "répètes": "répète",
    "préviennes": "préviens", "demandes": "demande", "indiques": "indique", "coupes": "coupe", "actives": "active",
    "désactives": "désactive", "baisses": "baisse", "résumes": "résume", "souviennes": "souviens",
}
# Verbs that only carry the question: « je voudrais savoir quelle heure il est ».
DROPPED_VERBS = {"savoir", "connaître", "connaitre"}

ASKING = r"(?:quel|quelle|quels|quelles|qui|combien|comment|pourquoi|où|ou|quand|si|s'|ce que|ce qu'|ce qui|est-ce|est ce|c'est|qu'est)"

POLITENESS = re.compile(r"[\s,]*\b(?:s'il (?:te|vous) pla[iî]t|stp|svp|please)\b[\s,]*", re.IGNORECASE)
TRAILING_THANKS = re.compile(r"[\s,]+merci(?: beaucoup| bien)?\s*([.!?]*)\s*$", re.IGNORECASE)
POSSESSIVE = r"(?!(?:mon|ma|mes|ton|ta|tes|votre|vos|notre|nos)\b)"

START_RULES = [
    # « Jarvis, … », « Dis Jarvis, … » (the routers know it, but the hedges come after it).
    (re.compile(r"^(?:(?:dis|hey|ok|okay|eh)\s+)?jarvis\b[\s,.:;!?]*", re.IGNORECASE), ""),
    (re.compile(r"^(?:alors|bon|bah|ben|euh+|heu+|hum+|écoute|écoutez|ecoute|ecoutez|dis donc|tiens)\b[\s,.:;!?]+", re.IGNORECASE), ""),
    # « dis-moi quel temps il fait » → « quel temps il fait »
    (re.compile(r"^(?:dis|dites)[- ]moi\s+(?=" + ASKING + r")", re.IGNORECASE), ""),
    # « tu sais quelle heure il est ? » → « quelle heure il est ? »
    (re.compile(r"^(?:est[- ]ce (?:que |qu'))?(?:tu sais|vous savez|sais[- ]tu|savez[- ]vous)\s+(?=" + ASKING + r")", re.IGNORECASE), ""),
    # Questions about a subject, in the wording Wikipédia's rule knows.
    (re.compile(r"^(?:ce qu'est|ce que sont)\s+" + POSSESSIVE, re.IGNORECASE), "qu'est-ce que "),
    (re.compile(r"^(?:qu'est[- ]ce que c'est|ce que c'est)(?:\s+que|\s+qu')?[\s,]+" + POSSESSIVE + r"(?=\S)", re.IGNORECASE), "qu'est-ce que "),
    (re.compile(r"^(?:ça|ca) veut dire quoi\s+", re.IGNORECASE), "que veut dire "),
    (re.compile(r"^qui c'est\s+", re.IGNORECASE), "qui est "),
    (re.compile(r"^(?:tu connais|connais[- ]tu|vous connaissez|connaissez[- ]vous)\s+(?!(?:mon|ma|mes|quel|quelle|qui|combien|comment|pourquoi)\b)", re.IGNORECASE),
     "parle-moi de "),
    (re.compile(r"^(?:que|qu'est[- ]ce que tu) sais[- ]?(?:tu)? (?:de|du|des|sur)\s+(?!moi\b)", re.IGNORECASE), "parle-moi de "),
    # Same commands, other words.
    (re.compile(r"^(?:va|allez|rends[- ]toi) sur\s+", re.IGNORECASE), "ouvre "),
    (re.compile(r"^(?:préviens|previens|informe|avertis) (?!moi\b)(\S+(?: \S+)?) (que|qu')", re.IGNORECASE), r"dis à \1 \2"),
    (re.compile(r"^(?:fais savoir|fait savoir|réponds|reponds) (?:à|a) ", re.IGNORECASE), "dis à "),
    (re.compile(r"^(?:envoie|envoies|envoyer|écris|ecris)(?:[- ](?:lui|leur))? un (?:texto|sms|imessage|petit message|petit mot|mot)\b", re.IGNORECASE), "envoie un message"),
    (re.compile(r"^envoie (?:à|a) (?=\S)", re.IGNORECASE), "envoie un message à "),
    (re.compile(r"^(?:passe|fais|lance)(?:[- ]moi)? un (?:coup de fil|coup de téléphone|coup de telephone|appel) (?:à|a|au) ", re.IGNORECASE), "appelle "),
]

HEDGE = re.compile(
    r"^(?:est[- ]ce (?:que |qu'))?"
    r"(?:(?:tu|vous) (?:peux|pourrais|pouvez|pourriez|veux bien|voudrais bien|voulez bien|voudriez bien|saurais|sauriez|dois|devrais)"
    r"|(?:peux|pourrais|veux|voudrais|saurais)[- ]tu|(?:pouvez|pourriez|voulez|voudriez|sauriez)[- ]vous"
    r"|(?:c'est|ce serait|ça serait|ca serait|il est|est-il|serait-il) possible (?:de |d')"
    r"|(?:je voudrais|je voudrai|j'aimerais|j'aimerai|je veux|j'ai envie)(?: bien)?(?: que (?:tu|vous))?"
    r"|(?:il faudrait|faudrait|il faut|il faudra|faut)(?: que (?:tu|vous))?"
    r"|j'ai besoin (?:que (?:tu|vous)|de|d')"
    r"|merci (?:de|d'))"
    r"[\s,]*(?:juste |vite |rapidement |simplement |bien |encore )?"
    r"(?:(me |m'|te |t'|nous )\s*)?"
    r"([a-zàâäçéèêëîïôöûùüÿœ]+)",
    re.IGNORECASE,
)


def _imperative(verb: str, pronoun: str) -> str | None:
    lowered = verb.lower()
    if lowered in DROPPED_VERBS and not pronoun:
        return ""
    imperative = INFINITIVES.get(lowered) or SUBJUNCTIVES.get(lowered)
    if imperative is None:
        return None
    pronoun = pronoun.strip().lower()
    if imperative == "souviens":
        # « tu peux te souvenir que… » → « souviens-toi que… »
        return "souviens-toi" if pronoun in ("te", "t'") else None
    if pronoun in ("me", "m'"):
        return imperative + "-moi"
    if pronoun == "nous":
        return imperative + "-nous"
    if pronoun in ("te", "t'"):
        return None
    return imperative


def _rewrite_hedge(text: str) -> str:
    match = HEDGE.match(text)
    if not match:
        return text
    imperative = _imperative(match.group(2), match.group(1) or "")
    if imperative is None:
        return text
    rest = text[match.end():].lstrip(" ,")
    return f"{imperative} {rest}".strip() if imperative else rest


def _without_thanks(text: str) -> str:
    """« Ouvre YouTube, merci ! » → « Ouvre YouTube ! »; « Non merci » stays."""
    match = TRAILING_THANKS.search(text)
    if not match or len(text[: match.start()].split()) < 2:
        return text
    return text[: match.start()] + (" " + match.group(1) if match.group(1) else "")


def rewrite(text: str) -> str:
    """The request in the plain wording of the commands, or `text` itself."""
    original = " ".join(text.replace("’", "'").split())
    value = POLITENESS.sub(" ", original)
    value = _without_thanks(" ".join(value.split()))
    value = " ".join(value.split())
    for _ in range(5):
        before = value
        for pattern, replacement in START_RULES:
            value = pattern.sub(replacement, value, count=1).lstrip(" ,")
        value = _rewrite_hedge(value)
        if value == before:
            break
    value = value.strip(" ,")
    return value if value.strip(" .,;:!?") else original
