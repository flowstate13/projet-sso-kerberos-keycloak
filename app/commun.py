"""Mise en page commune des applications pedagogiques du TP4."""
import base64
import json
from html import escape

CSS = """
body{font-family:Segoe UI,Arial,sans-serif;margin:0;color:#141414;background:#fff}
header{border-bottom:2px solid #F3702B;padding:14px 28px;display:flex;gap:18px;align-items:baseline}
header b{font-size:20px} header a{color:#141414;text-decoration:none;font-size:14px}
header a:hover{color:#F3702B}
main{padding:18px 28px;max-width:1100px}
h2{font-size:18px;border-left:6px solid #F3702B;padding-left:10px;margin-top:26px}
table{border-collapse:collapse;width:100%;font-size:14px;margin:8px 0}
th{background:#F3702B;text-align:left;padding:6px 10px}
td{padding:6px 10px;border-bottom:1px solid #eee;vertical-align:top;word-break:break-word}
tr:nth-child(even) td{background:#F6F6F6}
pre,textarea{font-family:Consolas,monospace;font-size:12.5px;background:#F6F6F6;border:1px solid #ddd;padding:10px;
 white-space:pre-wrap;word-break:break-all;width:100%;box-sizing:border-box}
button,.bouton{background:#F3702B;border:0;color:#141414;font-weight:600;padding:8px 14px;cursor:pointer;
 text-decoration:none;display:inline-block;font-size:14px;margin:3px 6px 3px 0}
button.gris,.bouton.gris{background:#e4e4e4}
.ok{border-left:6px solid #1a8f3c;background:#eaf7ee;padding:10px 14px;margin:10px 0}
.ko{border-left:6px solid #c62828;background:#fdecea;padding:10px 14px;margin:10px 0}
.info{border-left:6px solid #999;background:#F6F6F6;padding:10px 14px;margin:10px 0}
label{margin-right:16px;font-size:14px}
"""


def page(titre, liens, corps):
    menu = "".join(f'<a href="{u}">{escape(t)}</a>' for t, u in liens)
    return (f"<!doctype html><html lang=fr><meta charset=utf-8><title>{escape(titre)}</title>"
            f"<style>{CSS}</style><header><b>{escape(titre)}</b>{menu}</header><main>{corps}</main></html>")


def tableau(lignes, entetes=("Champ", "Valeur")):
    t = f"<table><tr><th>{escape(entetes[0])}</th><th>{escape(entetes[1])}</th></tr>"
    for a, b in lignes:
        t += f"<tr><td>{escape(str(a))}</td><td>{escape(str(b))}</td></tr>"
    return t + "</table>"


def b64url_json(partie):
    return json.loads(base64.urlsafe_b64decode(partie + "=" * (-len(partie) % 4)))


def decoder_jwt(jeton):
    """Lecture sans verification : uniquement pour afficher le contenu."""
    entete, charge, _ = jeton.split(".")
    return b64url_json(entete), b64url_json(charge)
