#!/usr/bin/env python3
"""Prepara dati e immagini del gioco a partire dal materiale originale.

Fonti (non nel repository):
  --tts      cartella Mods del modulo Tabletop Simulator (Images, Models, Workshop)
  --carte    cartella con le scansioni italiane ("carte italiano")
  --ritagli  cartella con i ritagli delle scansioni (generati da tools/ritaglia_carte.py)

Usa i testi trascritti in tools/testi/*.json (italiano e inglese di ogni carta) e
i dati del modulo TTS (tools/testi/tts_data.json: sistemi, adiacenze, unità, leader).

Produce:
  assets/data/mondo.json   sistemi, unità, leader, tracciato del tempo
  assets/data/carte.json   tutte le carte del gioco base e dell'Ascesa dell'Impero
  assets/board/…           tabellone
  assets/cards/…           immagini delle carte
  assets/leaders/…         ritratti dei leader (dalle sagome del TTS)
  assets/models/…          modelli 3D delle unità e dei leader
  assets/tokens/…          segnalini e icone
"""
import argparse, glob, json, os, re, shutil
from PIL import Image, ImageOps

Image.MAX_IMAGE_PIXELS = None
QUI = os.path.dirname(os.path.abspath(__file__))
REPO = os.path.dirname(QUI)
TESTI = os.path.join(QUI, "testi")
A = os.path.join(REPO, "assets")


def jl(n):
    return json.load(open(os.path.join(TESTI, n), encoding="utf-8"))


def slug(s):
    return re.sub(r"[^a-z0-9]+", "_", s.lower().replace("'", "")).strip("_")


def img_tts(tts, suffix):
    f = [x for x in glob.glob(os.path.join(tts, "Images", "*")) if suffix in os.path.basename(x)]
    return f[0] if f else None


def model_tts(tts, suffix):
    f = [x for x in glob.glob(os.path.join(tts, "Models", "*.obj")) if suffix in os.path.basename(x)]
    return f[0] if f else None


# ---------------------------------------------------------------- mondo

NOMI_IT = {}  # i pianeti hanno lo stesso nome in italiano

def fai_mondo(tts):
    T = jl("tts_data.json")
    fit = jl("boardfit.json")
    L = T["Locations"]
    sist = {}
    adj = {k: set(v["Adjacents"]) - {k} for k, v in L.items() if v["Type"] == "System"}
    for a in list(adj):
        for b in list(adj[a]):
            adj.setdefault(b, set()).add(a)
    W, H = 6454.0, 3227.0
    for k, v in L.items():
        if v["Type"] != "System":
            continue
        x, _, z = v["MarkerSpot"]
        u = fit["cx"][0] * x + fit["cx"][1] * z + fit["cx"][2]
        w = fit["cy"][0] * x + fit["cy"][1] * z + fit["cy"][2]
        sist[k] = {
            "nome": k.title().replace("Ii", "II"),
            "regione": v["Region"],
            "popolato": v["SubType"] == "Populous",
            "icone": list(v["Build"]["Icons"]) if v["SubType"] == "Populous" else [],
            "coda": v["Build"]["Queue"],
            "adiacenti": sorted(adj[k]),
            "pos": [round(u / 1400.0, 4), round(w / 700.0, 4)],
        }
    sist["CORUSCANT"]["icone"] = ["OT"]
    unita = {}
    for n, u in T["Units"].items():
        if u["Box"] not in ("Base", "RotE"):
            continue
        unita[n] = {
            "fazione": "R" if u["Faction"] == "Rebel" else "I",
            "teatro": "spazio" if u["Theater"] == "Space" else "terra",
            "tipo": u["SubType"] or u["Type"],
            "trasporto": u["Transport"],
            "serve_trasporto": bool(u["NeedsTransport"]),
            "immobile": bool(u["Immobile"]),
            "struttura": u["Type"] == "Structure",
            "neri": u["BlackDice"], "rossi": u["RedDice"], "verdi": u["GreenDice"],
            "salute": u["Health"] if u["Health"] < 999 else 0,
            "colore_salute": {"Red": "rosso", "Black": "nero", "Green": "verde"}.get(u["HealthColor"], ""),
            "icona": u["Build"],
            "massimo": u["Max"],
            "set": "base" if u["Box"] == "Base" else "rote",
        }
    leader = {}
    for n, l in T["LeaderInfo"].items():
        if l["Game"] not in ("Base", "RotE"):
            continue
        leader[n] = {
            "fazione": "R" if l["Faction"] == "Rebel" else "I",
            "ruolo": l["Type"],
            "iniziale": l["Starting"],
            "spazio": l["SpaceTactic"], "terra": l["GroundTactic"],
            "abilita": {"diplomazia": l["Diplomacy"], "intel": l["Intel"], "opspec": l["SpecOps"], "logistica": l["Logistics"]},
            "minori": {"diplomazia": l["MinorDiplomacy"], "intel": l["MinorIntel"], "opspec": l["MinorSpecOps"], "logistica": l["MinorLogistics"]},
            "set": "base" if l["Game"] == "Base" else "rote",
        }
    mondo = {"sistemi": sist, "unita": unita, "leader": leader,
             "reclutamento": [2, 3, 4, 5], "costruzione": [2, 4, 6, 8, 10, 12, 14, 16]}
    json.dump(mondo, open(os.path.join(A, "data", "mondo.json"), "w", encoding="utf-8"), ensure_ascii=False, indent=1)
    return mondo


# ---------------------------------------------------------------- carte

SKILL = {"diplomazia": "diplomazia", "intel": "intel", "logistica": "logistica", "opspec": "opspec"}


def carta_img(c, out_dir, ritagli, tts_cards, size):
    """Immagine della carta: il ritaglio italiano se c'è, altrimenti la carta del TTS."""
    if c.get("crop"):
        src = os.path.join(ritagli, c["crop"])
    else:
        src = os.path.join(tts_cards, c["tts"])
    return src


def salva(src, dst, h, trim=True):
    im = Image.open(src).convert("RGB")
    if trim:
        # toglie il bordo bianco del ritaglio
        g = ImageOps.invert(im.convert("L")).point(lambda p: 255 if p > 40 else 0)
        bb = g.getbbox()
        if bb:
            im = im.crop(bb)
    w = round(im.width * h / im.height)
    im = im.resize((w, h), Image.LANCZOS)
    im.save(dst, quality=86, optimize=True)


def fai_carte(ritagli, tts_cards, scrivi_img=True):
    carte = []
    usati = {}

    def nuovo_id(base):
        usati[base] = usati.get(base, 0) + 1
        return base if usati[base] == 1 else "%s#%d" % (base, usati[base])

    def aggiungi(c, kind, fazione, set_, extra):
        cid = slug(c["name_en"])
        if set_ == "rote" and kind in ("missione", "azione") and cid in ("sabotage", "construct_super_star_destroyer", "good_intel", "son_of_skywalker"):
            cid = cid + "_rote"
        if kind == "tattica":
            cid = ("ts_" if c["theater"] == "spazio" else "tt_") + cid
        if kind == "tattica_av":
            cid = ("av_" + fazione.lower() + "_") + cid
        if kind == "obiettivo":
            cid = "ob_" + cid
        inst = nuovo_id(cid)
        fn = inst.replace("#", "_") + ".jpg"
        d = {"id": inst, "base": cid, "tipo": kind, "fazione": fazione, "set": set_,
             "nome": c["name_it"].upper() if kind not in ("obiettivo",) else c["name_it"],
             "testo": c["text_it"], "nome_en": c["name_en"], "testo_en": c["text_en"],
             "img": "res://assets/cards/" + fn, "scansione": bool(c.get("crop"))}
        d.update(extra)
        carte.append(d)
        if scrivi_img:
            src = carta_img(c, None, ritagli, tts_cards, None)
            h = 520 if kind in ("missione", "obiettivo") else 460
            salva(src, os.path.join(A, "cards", fn), h, trim=bool(c.get("crop")))

    for f, fz in (("missioni_imp_base.json", "I"), ("missioni_reb_base.json", "R")):
        for c in jl(f):
            aggiungi(c, "missione", fz, "base", {
                "abilita": c["skill"], "livello": c["level"], "ritratto": c.get("portrait"),
                "iniziale": bool(c.get("starting")), "progetto": bool(c.get("project")),
                "risolvi": bool(c.get("resolve")), "vader": False})
    for c in jl("missioni_rote.json"):
        fz = "I" if c["faction"] == "imp" else "R"
        aggiungi(c, "missione", fz, "rote", {
            "abilita": c["skill"], "livello": c["level"], "ritratto": c.get("portrait"),
            "iniziale": bool(c.get("starting")), "progetto": bool(c.get("project")),
            "risolvi": bool(c.get("resolve")), "vader": bool(c.get("vader_icon"))})
    for f, set_ in (("azioni_base.json", "base"), ("azioni_rote.json", "rote")):
        for c in jl(f):
            fz = c.get("faction", "")
            fz = "I" if fz in ("imp", "Imperial") else "R"
            aggiungi(c, "azione", fz, set_, {
                "iniziale": bool(c.get("starting")), "momento": c.get("timing_it", ""),
                "momento_en": c.get("timing_en", ""), "leader": c.get("leaders", []), "anello": c.get("ring")})
    for f, set_ in (("obiettivi_base.json", "base"), ("obiettivi_rote.json", "rote")):
        for c in jl(f):
            rep = c["reputation"]
            if isinstance(rep, str) and not rep.isdigit():
                rep = 0 if rep.startswith("-") else -1
            aggiungi(c, "obiettivo", "R", set_, {
                "stadio": c["stage"], "reputazione": int(rep), "momento": c.get("timing_it", ""),
                "momento_en": c.get("timing_en", "")})
    for c in jl("tattiche_base.json"):
        aggiungi(c, "tattica", "", "base", {"teatro": c["theater"], "speciale": bool(c.get("special_cost"))})
    for c in jl("tattiche_avanzate_rote.json"):
        fz = "I" if c["faction"] == "Imperial" else "R"
        aggiungi(c, "tattica_av", fz, "rote", {
            "teatro": c["theater"], "sopra": c["top_it"], "sotto": c["bottom_it"],
            "sopra_unita": c.get("top_unit"), "sotto_unita": c.get("bottom_unit")})
    json.dump(carte, open(os.path.join(A, "data", "carte.json"), "w", encoding="utf-8"), ensure_ascii=False, indent=1)
    return carte


def fai_sonde(ritagli, tts_cards, scrivi_img=True):
    """Carte sonda: abbina i ritagli italiani alle carte TTS per somiglianza dell'immagine."""
    import numpy as np
    sel = jl("carte_tts.json")
    probes = [c for c in sel if c["tags"].startswith("ProbeCard")]
    def vec(p):
        im = Image.open(p).convert("L").resize((24, 36))
        a = np.asarray(im, dtype=float)
        a = (a - a.mean()) / (a.std() + 1e-6)
        return a.ravel()
    crops = sorted(glob.glob(os.path.join(ritagli, "Carte_Sonda_*.png")))
    tv = {c["name"]: vec(os.path.join(tts_cards, c["file"])) for c in probes}
    out = {}
    for cp in crops:
        im = Image.open(cp).convert("RGB")
        g = ImageOps.invert(im.convert("L")).point(lambda p: 255 if p > 40 else 0)
        bb = g.getbbox()
        if bb:
            im = im.crop(bb)
        tmp = "/tmp/_sonda.png"
        im.save(tmp)
        v = vec(tmp)
        best = max(tv, key=lambda n: float(np.dot(tv[n], v)) if n not in out else -1e9)
        out[best] = cp
    res = []
    for c in probes:
        nm = c["name"]
        tag = "R" if "Rebel" in c["tags"] else ("I" if "Imperial" in c["tags"] else "")
        fn = "sonda_" + slug(nm) + ".jpg"
        if scrivi_img:
            src = out.get(nm) or os.path.join(tts_cards, c["file"])
            salva(src, os.path.join(A, "cards", fn), 360, trim=nm in out)
        res.append({"sistema": nm, "lealta_iniziale": tag, "img": "res://assets/cards/" + fn})
    json.dump(res, open(os.path.join(A, "data", "sonde.json"), "w", encoding="utf-8"), ensure_ascii=False, indent=1)
    return res


# ---------------------------------------------------------------- immagini varie

def fai_tabellone(tts):
    src = img_tts(tts, "44D37DD4CCE902FD2082C88A42DF61")
    im = Image.open(src).convert("RGB")
    im.resize((4096, 2048), Image.LANCZOS).save(os.path.join(A, "board", "tabellone.jpg"), quality=88, optimize=True)


def fai_leader(tts, mondo):
    M = jl("modelli_tts.json")
    for nome, m in M.items():
        if m["kind"] != "leader" or nome not in mondo["leader"]:
            continue
        src = img_tts(tts, m["diff"][-30:])
        im = Image.open(src).convert("RGB")
        W, H = im.size
        # la sagoma anteriore occupa la metà sinistra in basso, capovolta
        fr = im.crop((0, int(H * 0.37), int(W * 0.47), H)).rotate(180)
        fr.save(os.path.join(A, "leaders", slug(nome) + ".jpg"), quality=88)
        # texture per il modello 3D (ridotta)
        im.resize((512, 512), Image.LANCZOS).save(os.path.join(A, "leaders", slug(nome) + "_tex.jpg"), quality=85)


def _copia_obj(src, dst):
    """Copia un modello OBJ senza i riferimenti ai materiali (la texture la mette il gioco)."""
    with open(src, encoding="utf-8", errors="ignore") as fi, open(dst, "w", encoding="utf-8") as fo:
        for riga in fi:
            if riga.startswith("mtllib") or riga.startswith("usemtl"):
                continue
            fo.write(riga)


def fai_modelli(tts):
    M = jl("modelli_tts.json")
    info = {}
    for nome, m in M.items():
        if m["kind"] == "leader":
            continue
        ob = model_tts(tts, m["mesh"][-30:])
        tx = img_tts(tts, m["diff"][-30:]) if m["diff"] else None
        if not ob:
            print("manca il modello di", nome)
            continue
        base = slug(nome)
        _copia_obj(ob, os.path.join(A, "models", base + ".obj"))
        if tx:
            im = Image.open(tx).convert("RGB")
            if im.width > 1024:
                im = im.resize((1024, 1024 * im.height // im.width), Image.LANCZOS)
            im.save(os.path.join(A, "models", base + ".jpg"), quality=88)
        info[nome] = {"mesh": "res://assets/models/%s.obj" % base,
                      "tex": "res://assets/models/%s.jpg" % base if tx else "", "scala_tts": m["scale"]}
    # sagoma dei leader (uguale per tutti, cambia solo la texture)
    for nome, m in M.items():
        if m["kind"] == "leader":
            fz = "reb" if "46E2CCFCAABB7014564E" in m["mesh"] else "imp"
            dst = os.path.join(A, "models", "sagoma_%s.obj" % fz)
            if not os.path.exists(dst):
                _copia_obj(model_tts(tts, m["mesh"][-30:]), dst)
    json.dump(info, open(os.path.join(A, "data", "modelli.json"), "w"), indent=1)


TOKENS = {
    "tempo": "2445C485C4FE1BB09990D731340984", "reputazione": "A2D11D08996ECCAFA35D53B1FB1716",
    "sabotaggio": "9F2DC658BF27FB84048DB46E5E6013", "distrutto": "354BFCE5DB501B78530359CAC4C26A",
    "lealta_ribelle": "3FBA94CA9B0E1EE53717CADDC521B3", "lealta_imperiale": "5E76483E8EB1ACEE396946686568E4",
    "sondato": "6F2A01873255EF6B58BCCC682B8CA6", "danno": "6C99937E06FCFAADB5CAB955B96F8E",
    "anello_catturato": "4C04AFAB6915CA938EC07D2E5EB307", "anello_grafite": "0F0A2FFB4BF637BC99769DBADD955A",
    "anello_lato_oscuro": "E942F6575A8A460C4948179F584C43", "anello_taglia": "736D8F481C9DF77E118346769F5078",
    "anello_r2d2": "EB128A080A61ADE337166A41E6B154", "anello_c3po": "BDA870E076C0E6462FF0D1D64E5248",
    "anello_falcon": "6A0CF7D2655E05C0C9512D109CEBBA", "anello_yoda": "3E4470E66FAA71E7B6D5701C775534",
    "anello_k2so": "19AA50CB893391559D2DE1A2B217FD",
    "u_rebel_trooper": "F0FCFA54CE222814402648F0455230", "u_airspeeder": "5EDE17EA436974B12374744EA7990C",
    "u_shield_generator": "572F64541A321F1E201957F8A59E0F", "u_x_wing": "704783906FAA8351493F7C5D6B57BD",
    "u_corellian_corvette": "A0C22F383FABDBA5E3A8208B67BEFA", "u_mon_cala_cruiser": "67D19C0ADA16FEF81840DF190B2965",
    "u_stormtrooper": "C17728EDEC8CF2F13CBF55BBFEAA2A", "u_at_st": "27D94D2F863B3D5D14B048B00F84C0",
    "u_at_at": "03C83A29391A6F17AE16B92D30EC3C", "u_tie_fighter": "96F073F9DDAEBA763DDABD8EE17AFC",
    "u_assault_carrier": "A14EC15364312D3C644C002B037ECF", "u_star_destroyer": "301462845ACB96B0BF528D264AEC3B",
    "segnalino_bersaglio_1": "016B8590094E65D7C31E8ED8780BD8", "segnalino_bersaglio_2": "C7C1022ACB24526402B1EC1BE5A514",
    "segnalino_bersaglio_3": "BE8EA0A9E104738CA7AA48DF337E15", "segnalino_bersaglio_4": "FE797F229B0279E41628E39652F78F",
}


def fai_segnalini(tts):
    for nome, s in TOKENS.items():
        src = img_tts(tts, s)
        if not src:
            print("manca", nome)
            continue
        im = Image.open(src).convert("RGBA")
        if im.width > 256:
            im.thumbnail((256, 256), Image.LANCZOS)
        im.save(os.path.join(A, "tokens", nome + ".png"), optimize=True)


if __name__ == "__main__":
    ap = argparse.ArgumentParser()
    ap.add_argument("--tts", required=True)
    ap.add_argument("--ritagli", required=True)
    ap.add_argument("--tts-carte", required=True, help="carte del TTS già ritagliate (una per file)")
    ap.add_argument("--solo-dati", action="store_true")
    a = ap.parse_args()
    for d in ("data", "cards", "board", "leaders", "models", "tokens"):
        os.makedirs(os.path.join(A, d), exist_ok=True)
    mondo = fai_mondo(a.tts)
    carte = fai_carte(a.ritagli, a.tts_carte, not a.solo_dati)
    sonde = fai_sonde(a.ritagli, a.tts_carte, not a.solo_dati)
    if not a.solo_dati:
        fai_tabellone(a.tts)
        fai_leader(a.tts, mondo)
        fai_modelli(a.tts)
        fai_segnalini(a.tts)
    print(len(mondo["sistemi"]), "sistemi,", len(carte), "carte,", len(sonde), "sonde")
