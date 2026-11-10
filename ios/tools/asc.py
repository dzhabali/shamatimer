#!/usr/bin/env python3
"""Мини-клиент App Store Connect API для ручной подписи ShamaTimer (без устройств в аккаунте).

Ключ — ~/.appstoreconnect/AuthKey_<KEY_ID>.p8 (в репо не класть: репо публичное).
  python3 asc.py get /v1/bundleIds
  python3 asc.py setup-bundle           # bundle id + HealthKit + Time Sensitive
  python3 asc.py setup-bundle com.maxdzhabali.vajra Vajra APP_GROUPS   # любой другой bundle id
  python3 asc.py create-cert <csr.pem>  # Apple Distribution → печатает base64 сертификата
  python3 asc.py create-profile <certId> [bundleId "Profile name"]  # IOS_APP_STORE → uuid + base64
  python3 asc.py whats-new <bundleId> <build> "текст"   # «Что нового» билда в TestFlight (ждёт обработку до 60 мин)
Нужны PyJWT + cryptography.
"""
import json
import os
import sys
import time
import urllib.error
import urllib.request

import jwt

KEY_ID = os.environ.get('ASC_KEY_ID', 'GTFY4P5UPP')
ISSUER = os.environ.get('ASC_ISSUER_ID', '74224bd7-bbf9-4a2f-a400-0ed839c272bb')
BUNDLE = 'com.maxdzhabali.shamatimer'
PROFILE_NAME = 'ShamaTimer App Store'
API = 'https://api.appstoreconnect.apple.com'


def token():
    key = open(os.path.expanduser('~/.appstoreconnect/AuthKey_%s.p8' % KEY_ID)).read()
    now = int(time.time())
    return jwt.encode({'iss': ISSUER, 'iat': now, 'exp': now + 1100, 'aud': 'appstoreconnect-v1'},
                      key, algorithm='ES256', headers={'kid': KEY_ID, 'typ': 'JWT'})


def call(method, path, body=None):
    req = urllib.request.Request(API + path, method=method,
                                 data=json.dumps(body).encode() if body is not None else None,
                                 headers={'Authorization': 'Bearer ' + token(), 'Content-Type': 'application/json'})
    try:
        with urllib.request.urlopen(req, timeout=60) as r:
            raw = r.read()
            return r.status, json.loads(raw) if raw else {}
    except urllib.error.HTTPError as e:
        raw = e.read()
        return e.code, json.loads(raw) if raw else {}


def bundle_id(ident=BUNDLE):
    st, js = call('GET', '/v1/bundleIds?filter[identifier]=%s&limit=5' % ident)
    for b in js.get('data', []):
        if b['attributes']['identifier'] == ident:
            return b['id']
    return None


def setup_bundle(ident=BUNDLE, name='ShamaTimer', caps=('HEALTHKIT', 'USERNOTIFICATIONS_TIMESENSITIVE')):
    bid = bundle_id(ident)
    if not bid:
        st, js = call('POST', '/v1/bundleIds', {'data': {'type': 'bundleIds', 'attributes': {
            'identifier': ident, 'name': name, 'platform': 'IOS'}}})
        print('create bundleId', st, json.dumps(js)[:300])
        bid = js['data']['id']
    st, js = call('GET', '/v1/bundleIds/%s/bundleIdCapabilities' % bid)
    have = {c['attributes']['capabilityType'] for c in js.get('data', [])}
    for cap in caps:
        if cap in have:
            continue
        st, js = call('POST', '/v1/bundleIdCapabilities', {'data': {
            'type': 'bundleIdCapabilities', 'attributes': {'capabilityType': cap},
            'relationships': {'bundleId': {'data': {'type': 'bundleIds', 'id': bid}}}}})
        print('capability', cap, st, '' if st < 300 else json.dumps(js)[:300])
    print('bundleId', bid)


def create_cert(csr_path):
    csr = open(csr_path).read()
    st, js = call('POST', '/v1/certificates', {'data': {'type': 'certificates', 'attributes': {
        'certificateType': 'DISTRIBUTION', 'csrContent': csr}}})
    if st >= 300:
        sys.exit('cert %s %s' % (st, json.dumps(js)[:500]))
    a = js['data']['attributes']
    print(js['data']['id'], a['certificateContent'])


def dist_certs():
    """Все действующие сертификаты Apple Distribution аккаунта (у MacBook и у mini — свои)."""
    st, js = call('GET', '/v1/certificates?filter[certificateType]=DISTRIBUTION&limit=50')
    now = time.strftime('%Y-%m-%dT%H:%M:%S', time.gmtime())
    return [c['id'] for c in js.get('data', []) if (c['attributes'].get('expirationDate') or '9') > now]


def create_profile(cert_id, ident=BUNDLE, profile_name=PROFILE_NAME):
    """Профиль App Store под ВСЕ действующие сертификаты Distribution, не только под cert_id. До 10.11.2026 профиль
    пересоздавался с одним сертификатом: собрать приложение могла только та машина, чей он, — когда mini была
    офлайн (24.10–07.11.2026), Shama, Ваджру, Drumsong и Lists нельзя было перезалить с MacBook.
    Новый файл профиля нужно положить на обе машины (в обе папки профилей), старый с тем же именем — убрать."""
    bid = bundle_id(ident)
    certs = [cert_id] + [c for c in dist_certs() if c != cert_id]
    st, js = call('GET', '/v1/profiles?filter[name]=%s' % urllib.request.quote(profile_name))
    for p in js.get('data', []):
        call('DELETE', '/v1/profiles/' + p['id'])          # пересоздать с текущими сертификатами
    st, js = call('POST', '/v1/profiles', {'data': {'type': 'profiles', 'attributes': {
        'name': profile_name, 'profileType': 'IOS_APP_STORE'}, 'relationships': {
        'bundleId': {'data': {'type': 'bundleIds', 'id': bid}},
        'certificates': {'data': [{'type': 'certificates', 'id': c} for c in certs]}}}})
    if st >= 300:
        sys.exit('profile %s %s' % (st, json.dumps(js)[:500]))
    a = js['data']['attributes']
    print(a['uuid'], a['profileContent'])


def whats_new(ident, build, text, wait_min=60):
    """Текст «Что нового» (What to Test) у билда в TestFlight. Билд появляется в API после обработки Apple —
    ждём до wait_min минут. Язык — существующая локализация билда или основной язык приложения."""
    st, js = call('GET', '/v1/apps?filter[bundleId]=%s' % ident)
    app = js['data'][0]
    bid = None
    for _ in range(wait_min * 2):
        st, js = call('GET', '/v1/builds?filter[app]=%s&filter[version]=%s&limit=1' % (app['id'], build))
        if js.get('data'):
            bid = js['data'][0]['id']
            break
        time.sleep(30)
    if not bid:
        sys.exit('билд %s не появился за %d мин' % (build, wait_min))
    st, js = call('GET', '/v1/builds/%s/betaBuildLocalizations' % bid)
    locs = js.get('data', [])
    if locs:
        for l in locs:
            st, r = call('PATCH', '/v1/betaBuildLocalizations/' + l['id'], {'data': {
                'type': 'betaBuildLocalizations', 'id': l['id'], 'attributes': {'whatsNew': text}}})
            print('whatsNew', l['attributes']['locale'], st)
    else:
        loc = app['attributes'].get('primaryLocale') or 'en-US'
        st, r = call('POST', '/v1/betaBuildLocalizations', {'data': {
            'type': 'betaBuildLocalizations', 'attributes': {'locale': loc, 'whatsNew': text},
            'relationships': {'build': {'data': {'type': 'builds', 'id': bid}}}}})
        print('whatsNew', loc, st, '' if st < 300 else json.dumps(r)[:300])


if __name__ == '__main__':
    cmd = sys.argv[1]
    if cmd == 'get':
        st, js = call('GET', sys.argv[2])
        print(st, json.dumps(js, indent=1, ensure_ascii=False)[:4000])
    elif cmd == 'setup-bundle':        # [identifier name CAP...]
        setup_bundle(*([sys.argv[2], sys.argv[3], sys.argv[4:]] if len(sys.argv) > 3 else []))
    elif cmd == 'create-cert':
        create_cert(sys.argv[2])
    elif cmd == 'create-profile':      # certId [identifier "profile name"]
        create_profile(*sys.argv[2:5])
    elif cmd == 'whats-new':           # identifier build "text"
        whats_new(sys.argv[2], sys.argv[3], sys.argv[4])
