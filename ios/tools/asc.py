#!/usr/bin/env python3
"""Мини-клиент App Store Connect API для ручной подписи ShamaTimer (без устройств в аккаунте).

Ключ — ~/.appstoreconnect/AuthKey_<KEY_ID>.p8 (в репо не класть: репо публичное).
  python3 asc.py get /v1/bundleIds
  python3 asc.py setup-bundle           # bundle id + HealthKit + Time Sensitive
  python3 asc.py create-cert <csr.pem>  # Apple Distribution → печатает base64 сертификата
  python3 asc.py create-profile <certId>  # IOS_APP_STORE → печатает base64 профиля
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


def bundle_id():
    st, js = call('GET', '/v1/bundleIds?filter[identifier]=%s&limit=5' % BUNDLE)
    for b in js.get('data', []):
        if b['attributes']['identifier'] == BUNDLE:
            return b['id']
    return None


def setup_bundle():
    bid = bundle_id()
    if not bid:
        st, js = call('POST', '/v1/bundleIds', {'data': {'type': 'bundleIds', 'attributes': {
            'identifier': BUNDLE, 'name': 'ShamaTimer', 'platform': 'IOS'}}})
        print('create bundleId', st, json.dumps(js)[:300])
        bid = js['data']['id']
    st, js = call('GET', '/v1/bundleIds/%s/bundleIdCapabilities' % bid)
    have = {c['attributes']['capabilityType'] for c in js.get('data', [])}
    for cap in ('HEALTHKIT', 'USERNOTIFICATIONS_TIMESENSITIVE'):
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


def create_profile(cert_id):
    bid = bundle_id()
    st, js = call('GET', '/v1/profiles?filter[name]=%s' % urllib.request.quote(PROFILE_NAME))
    for p in js.get('data', []):
        call('DELETE', '/v1/profiles/' + p['id'])          # пересоздать с текущим сертификатом
    st, js = call('POST', '/v1/profiles', {'data': {'type': 'profiles', 'attributes': {
        'name': PROFILE_NAME, 'profileType': 'IOS_APP_STORE'}, 'relationships': {
        'bundleId': {'data': {'type': 'bundleIds', 'id': bid}},
        'certificates': {'data': [{'type': 'certificates', 'id': cert_id}]}}}})
    if st >= 300:
        sys.exit('profile %s %s' % (st, json.dumps(js)[:500]))
    a = js['data']['attributes']
    print(a['uuid'], a['profileContent'])


if __name__ == '__main__':
    cmd = sys.argv[1]
    if cmd == 'get':
        st, js = call('GET', sys.argv[2])
        print(st, json.dumps(js, indent=1, ensure_ascii=False)[:4000])
    elif cmd == 'setup-bundle':
        setup_bundle()
    elif cmd == 'create-cert':
        create_cert(sys.argv[2])
    elif cmd == 'create-profile':
        create_profile(sys.argv[2])
