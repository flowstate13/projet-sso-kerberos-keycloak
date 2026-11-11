"""Fournisseur de service SAML 2.0 pedagogique : les messages et les controles sont visibles."""
import base64
import os
from html import escape

from flask import Flask, redirect, request, session, url_for
from lxml import etree
from onelogin.saml2.auth import OneLogin_Saml2_Auth
from onelogin.saml2.constants import OneLogin_Saml2_Constants
from onelogin.saml2.idp_metadata_parser import OneLogin_Saml2_IdPMetadataParser
from onelogin.saml2.settings import OneLogin_Saml2_Settings
from onelogin.saml2.utils import OneLogin_Saml2_Utils

from commun import page, tableau

# Tolerance d'horloge reduite pour observer rapidement l'expiration.
OneLogin_Saml2_Constants.ALLOWED_CLOCK_DRIFT = 5

BASE = os.environ["SP_BASE"]
ENTITY_ID = BASE + "/saml/metadata"
AUTRE_SP = "http://autre-sp.example/saml/metadata"
LIENS = [("Accueil", "/"), ("Métadonnées", "/config"), ("Espace RH", "/rh"), ("Messages SAML", "/messages"), ("TP", "/tp")]
IDP = {}
MEMO = {}
CONSOMMES = set()
app = Flask(__name__)
app.secret_key = os.environ.get("SP_SECRET", "secret-du-tp")
app.config["SESSION_COOKIE_NAME"] = "sp_saml_session"


def charger_idp():
    """Projet : charge les metadonnees de l'IdP depuis Keycloak (IDP_METADATA_URL) si elles manquent."""
    url = os.environ.get("IDP_METADATA_URL")
    if IDP or not url:
        return
    try:
        donnees = OneLogin_Saml2_IdPMetadataParser.parse_remote(url, timeout=5)
        IDP.update(donnees["idp"])
    except Exception:
        pass


def vue(corps):
    return page("Portail RH - fournisseur de service SAML 2.0", LIENS, corps)


def reglages(entity_id=ENTITY_ID):
    return {"strict": True, "debug": False,
            "sp": {"entityId": entity_id,
                   "assertionConsumerService": {"url": BASE + "/saml/acs", "binding": OneLogin_Saml2_Constants.BINDING_HTTP_POST},
                   "NameIDFormat": OneLogin_Saml2_Constants.NAMEID_UNSPECIFIED},
            "idp": IDP or {"entityId": "inconnu", "singleSignOnService": {"url": "http://inconnu"}, "x509cert": ""},
            "security": {"wantAssertionsSigned": True, "wantMessagesSigned": False, "authnRequestsSigned": False,
                         "rejectUnsolicitedResponsesWithInResponseTo": True, "requestedAuthnContext": False,
                         "allowRepeatAttributeName": True}}


def req():
    return {"https": "off", "http_host": BASE.split("//")[1], "script_name": request.path,
            "get_data": request.args.copy(), "post_data": request.form.copy()}


def beau(xml):
    return etree.tostring(etree.fromstring(xml.encode() if isinstance(xml, str) else xml), pretty_print=True).decode()


def premier(racine, chemin, attr=None):
    ns = {"samlp": "urn:oasis:names:tc:SAML:2.0:protocol", "saml": "urn:oasis:names:tc:SAML:2.0:assertion"}
    r = racine.xpath(chemin, namespaces=ns)
    if not r:
        return "(absent)"
    return r[0].get(attr, "(absent)") if attr else (r[0].text or "")


def champs(xml):
    x = etree.fromstring(xml.encode())
    signe_a = bool(x.xpath("//*[local-name()='Assertion']/*[local-name()='Signature']"))
    signe_r = bool(x.xpath("/*/*[local-name()='Signature']"))
    return [("Response : Destination", premier(x, "/samlp:Response", "Destination")),
            ("Response : InResponseTo", premier(x, "/samlp:Response", "InResponseTo")),
            ("Response : Status", premier(x, "//samlp:StatusCode", "Value").split(":")[-1]),
            ("Issuer (IdP)", premier(x, "/samlp:Response/saml:Issuer")),
            ("Assertion : ID", premier(x, "//saml:Assertion", "ID")),
            ("Subject : NameID", premier(x, "//saml:Subject/saml:NameID")),
            ("Subject : Recipient", premier(x, "//saml:SubjectConfirmationData", "Recipient")),
            ("Conditions : NotBefore", premier(x, "//saml:Conditions", "NotBefore")),
            ("Conditions : NotOnOrAfter", premier(x, "//saml:Conditions", "NotOnOrAfter")),
            ("Conditions : Audience", premier(x, "//saml:Audience")),
            ("AuthnStatement : AuthnInstant", premier(x, "//saml:AuthnStatement", "AuthnInstant")),
            ("Signature de la Response", "oui" if signe_r else "non"),
            ("Signature de l'Assertion", "oui" if signe_a else "non")]


@app.get("/")
def accueil():
    charger_idp()
    etat = "chargées" if IDP else "NON chargées"
    return vue(f"""<h2>État du fournisseur de service</h2>
{tableau([("entityID du SP", ENTITY_ID), ("ACS (HTTP-POST)", BASE + "/saml/acs"), ("Métadonnées de l'IdP", etat), ("Session locale", session.get("nameid") or "aucune")])}
<a class=bouton href=/rh>Accéder à l'Espace RH</a> <a class="bouton gris" href=/deconnexion>Fermer la session locale</a>""")


@app.get("/saml/metadata")
def metadonnees():
    xml = OneLogin_Saml2_Settings(settings=reglages(), sp_validation_only=True).get_sp_metadata()
    return xml, 200, {"Content-Type": "application/xml", "Content-Disposition": "attachment; filename=sp-metadata.xml"}


@app.route("/config", methods=["GET", "POST"])
def config():
    corps = """<h2>1. Métadonnées du SP (à importer dans Keycloak)</h2>
<a class=bouton href=/saml/metadata>Télécharger sp-metadata.xml</a>
<h2>2. Métadonnées de l'IdP (à fournir au SP)</h2>
<form method=post enctype=multipart/form-data><input type=file name=fichier accept=.xml> <button>Charger</button></form>"""
    if request.method == "POST":
        try:
            donnees = OneLogin_Saml2_IdPMetadataParser.parse(request.files["fichier"].read().decode())
            IDP.clear()
            IDP.update(donnees["idp"])
            corps += "<div class=ok>Métadonnées de l'IdP chargées : confiance établie.</div>"
        except Exception as e:
            corps += f"<div class=ko>Fichier refusé : {escape(str(e))}</div>"
    if IDP:
        cert = IDP.get("x509cert", "")
        empreinte = OneLogin_Saml2_Utils.calculate_x509_fingerprint(OneLogin_Saml2_Utils.format_cert(cert), "sha256") if cert else "(aucun)"
        corps += "<h2>IdP de confiance</h2>" + tableau([("entityID", IDP.get("entityId")), ("Service SSO", IDP.get("singleSignOnService", {}).get("url")),
                                                       ("Binding SSO", IDP.get("singleSignOnService", {}).get("binding", "").split(":")[-1]), ("Empreinte SHA-256 du certificat", empreinte)])
    return vue(corps)


@app.get("/rh")
def rh():
    charger_idp()
    if not session.get("nameid"):
        if not IDP:
            return vue("<div class=ko>Métadonnées de l'IdP absentes : voir la page Métadonnées.</div>")
        return redirect(url_for("connexion"))
    attributs = [(k, ", ".join(v)) for k, v in session.get("attributs", {}).items()]
    return vue(f"""<div class=ok><b>Ressource protégée : accès accordé à {escape(session['nameid'])}</b> (session locale du SP créée après validation de l'assertion).</div>
<h2>Attributs reçus dans l'assertion</h2>{tableau(attributs or [("(aucun)", "")], ("Attribut", "Valeur"))}<a class=bouton href=/messages>Voir les messages SAML</a>""")


@app.get("/connexion")
def connexion():
    auth = OneLogin_Saml2_Auth(req(), reglages())
    url = auth.login(return_to=BASE + "/rh")
    MEMO["authn_xml"] = auth.get_last_request_xml()
    MEMO["authn_id"] = auth.get_last_request_id()
    return redirect(url)


def traiter(saml_b64, entity_id=ENTITY_ID):
    """Valide une reponse et renvoie (auth, erreurs)."""
    auth = OneLogin_Saml2_Auth({**req(), "script_name": "/saml/acs", "post_data": {"SAMLResponse": saml_b64}}, reglages(entity_id))
    auth.process_response(request_id=MEMO.get("authn_id"))
    return auth, auth.get_errors()


@app.post("/saml/acs")
def acs():
    if not IDP:
        return vue("<div class=ko>Métadonnées de l'IdP absentes.</div>"), 400
    saml_b64 = request.form.get("SAMLResponse", "")
    xml = base64.b64decode(saml_b64).decode()
    auth, erreurs = traiter(saml_b64)
    if erreurs:
        return vue(f"<div class=ko><b>Réponse SAML rejetée par le SP</b><br>{escape(auth.get_last_error_reason() or str(erreurs))}</div>{tableau(champs(xml))}"), 403
    ident = etree.fromstring(xml.encode()).xpath("//*[local-name()='Assertion']/@ID")[0]
    if ident in CONSOMMES:
        return vue(f"<div class=ko><b>Rejeu détecté : assertion {escape(ident)} déjà consommée.</b><br>Signature et délais sont valides, mais une assertion ne s'utilise qu'une fois.</div>"), 403
    CONSOMMES.add(ident)
    MEMO.update(reponse_xml=xml, reponse_b64=saml_b64)
    session["nameid"] = auth.get_nameid()
    session["attributs"] = auth.get_attributes()
    return redirect("/rh")


@app.get("/messages")
def messages():
    if not MEMO.get("authn_xml"):
        return vue("<div class=info>Aucun message : accedez d'abord à l'Espace RH.</div>")
    corps = "<h2>AuthnRequest envoyée à l'IdP (HTTP-Redirect)</h2><pre>" + escape(beau(MEMO["authn_xml"])) + "</pre>"
    if MEMO.get("reponse_xml"):
        corps += "<h2>Éléments à contrôler dans la Response (HTTP-POST)</h2>" + tableau(champs(MEMO["reponse_xml"]))
        corps += "<h2>Response complete</h2><pre>" + escape(beau(MEMO["reponse_xml"])) + "</pre>"
    return vue(corps)


@app.route("/tp", methods=["GET", "POST"])
def tp():
    if not MEMO.get("reponse_xml"):
        return vue("<div class=info>Connectez-vous d'abord à l'Espace RH pour obtenir une reponse SAML.</div>")
    xml = request.form.get("xml", MEMO["reponse_xml"])
    resultat = ""
    if request.method == "POST":
        entity = AUTRE_SP if request.form.get("autre") else ENTITY_ID
        auth, erreurs = traiter(base64.b64encode(xml.encode()).decode(), entity)
        if erreurs:
            resultat = f"<div class=ko><b>Rejetée</b> : {escape(auth.get_last_error_reason() or str(erreurs))}</div>"
        else:
            resultat = f"<div class=ok><b>Valide</b> : NameID = {escape(auth.get_nameid())}</div>"
    return vue(f"""<h2>Contrôler une reponse SAML</h2>
<p>La validation ci-dessous ne crée pas de session : elle montre seulement ce que le SP accepterait.</p>{resultat}
<form method=post><textarea name=xml rows=14>{escape(xml)}</textarea>
<p><label><input type=checkbox name=autre {"checked" if request.form.get("autre") else ""}> Valider comme un autre SP ({AUTRE_SP})</label></p>
<button>Valider</button></form>
<form action=/saml/acs method=post><input type=hidden name=SAMLResponse value="{MEMO['reponse_b64']}"><button class=gris>Rejouer la reponse d'origine vers l'ACS</button></form>""")


@app.get("/deconnexion")
def deconnexion():
    session.clear()
    return redirect("/")
