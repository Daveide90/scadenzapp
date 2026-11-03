#!/usr/bin/env python3
"""Genera un backup .bak di prova per ScadenzApp (formato identico a BackupService).
120 farmaci distribuiti su 3 armadietti. Password: demo1234.

Formato file: magic(13 'SCADENZAPP_BK') + version(1) + salt(32) + iv(16) + hmac(32) + ciphertext
ciphertext = AES-256-CBC/PKCS7( gzip( utf8( json(data) ) ) )
encKey  = PBKDF2-HMAC-SHA256(pw, salt+'enc',  210000, 32)
hmacKey = PBKDF2-HMAC-SHA256(pw, salt+'hmac', 210000, 32)
hmac    = HMAC-SHA256(hmacKey, ciphertext)
"""
import os, json, gzip, hashlib, hmac as hmaclib, random, sys
from cryptography.hazmat.primitives.ciphers import Cipher, algorithms, modes
from cryptography.hazmat.primitives import padding as sympad

MAGIC = b'SCADENZAPP_BK'   # 13 byte
VERSION = 1
ITER = 210000
PW = b'demo1234'
SEED = 20260601
random.seed(SEED)

def sync_code():
    chars = 'ABCDEFGHJKLMNPQRSTUVWXYZ23456789'
    return ''.join(random.choice(chars) for _ in range(8))

# --- Armadietti ---
cabinets = [
    {'id': 1, 'name': 'Carrello Emergenza', 'position': 0, 'sync_code': sync_code()},
    {'id': 2, 'name': 'Armadio Reparto A',  'position': 1, 'sync_code': sync_code()},
    {'id': 3, 'name': 'Frigo Farmaci 2-8°C','position': 2, 'sync_code': sync_code()},
]

# --- Pool farmaci realistici: (nome, forma, unita) ---
POOL = [
    ('Tachipirina','compresse','mg'),('Augmentin','compresse','mg'),('OKi','bustine','mg'),
    ('Brufen','compresse','mg'),('Aulin','bustine','mg'),('Bentelan','compresse','mg'),
    ('Cardioaspirin','compresse','mg'),('Coumadin','compresse','mg'),('Eutirox','compresse','mcg'),
    ('Plavix','compresse','mg'),('Lasix','compresse','mg'),('Zitromax','compresse','mg'),
    ('Voltaren','fiale','mg'),('Moment','compresse','mg'),('Nurofen','compresse','mg'),
    ('Toradol','gocce','mg'),('Deltacortene','compresse','mg'),('Clexane','siringhe','mg'),
    ('Ventolin','spray','mcg'),('Seretide','spray','mcg'),('Lansox','capsule','mg'),
    ('Pantorc','compresse','mg'),('Triatec','compresse','mg'),('Norvasc','compresse','mg'),
    ('Nebivololo','compresse','mg'),('Coversyl','compresse','mg'),('Targin','compresse','mg'),
    ('Tachidol','compresse','mg'),('Buscopan','compresse','mg'),('Maalox','sciroppo','ml'),
    ('Fluimucil','bustine','mg'),('Rinazina','spray','ml'),('Oki Tantum','collutorio','ml'),
    ('Gaviscon','sciroppo','ml'),('Imodium','capsule','mg'),('Enterogermina','flaconi','ml'),
    ('Daflon','compresse','mg'),('Cardicor','compresse','mg'),('Lobivon','compresse','mg'),
    ('Glucophage','compresse','mg'),('Januvia','compresse','mg'),('Lantus','penne','UI'),
    ('Humalog','penne','UI'),('Xanax','compresse','mg'),('En','gocce','mg'),
    ('Laroxyl','gocce','mg'),('Depakin','compresse','mg'),('Keppra','compresse','mg'),
    ('Aricept','compresse','mg'),('Madopar','compresse','mg'),
]
DOSAGES = {'mg':['100','250','500','875','1000'],'mcg':['25','50','100','250'],
           'ml':['10','15','100','200'],'UI':['100'],}

def rand_dose(unit):
    return random.choice(DOSAGES.get(unit, ['1']))

# Date: oggi simulato = 2026-06-01. Mix scaduti / in scadenza / futuri.
from datetime import date, timedelta, datetime
TODAY = date(2026, 6, 1)
def rand_exp():
    r = random.random()
    if r < 0.15:   # gia' scaduto
        d = TODAY - timedelta(days=random.randint(5, 400))
    elif r < 0.45: # in scadenza entro 90 gg
        d = TODAY + timedelta(days=random.randint(1, 90))
    else:          # futuro
        d = TODAY + timedelta(days=random.randint(120, 900))
    return f'{d.year}-{d.month:02d}-{d.day:02d}'

def rand_added():
    d = datetime(2026, 1, 1) + timedelta(days=random.randint(0, 150),
                                          hours=random.randint(0, 23),
                                          minutes=random.randint(0, 59))
    return d.isoformat() + '.000'

# Distribuzione: 45 + 40 + 35 = 120
counts = {1: 45, 2: 40, 3: 35}
medicines = []
mid = 1
for cab_id, n in counts.items():
    for _ in range(n):
        name, form, unit = random.choice(POOL)
        dose = rand_dose(unit)
        medicines.append({
            'id': mid,
            'cabinet_id': cab_id,
            'name': name,
            'expiration_date': rand_exp(),
            'quantity': random.randint(1, 30),
            'added_at': rand_added(),
            'form': form,
            'dosage': dose,
            'unit': unit,
        })
        mid += 1

assert len(medicines) == 120, len(medicines)

data = {
    'cabinets': cabinets,
    'medicines': medicines,
    'custom_medicines': [],
    '_meta': {'version': VERSION, 'type': 'full',
              'created_at': '2026-06-01T09:00:00.000'},
}

# --- cifratura (identica a BackupService) ---
jsonb = json.dumps(data, ensure_ascii=False).encode('utf-8')
comp = gzip.compress(jsonb)
salt = os.urandom(32)
iv = os.urandom(16)
ek = hashlib.pbkdf2_hmac('sha256', PW, salt + b'enc', ITER, 32)
hk = hashlib.pbkdf2_hmac('sha256', PW, salt + b'hmac', ITER, 32)
padder = sympad.PKCS7(128).padder()
padded = padder.update(comp) + padder.finalize()
enc = Cipher(algorithms.AES(ek), modes.CBC(iv)).encryptor()
ct = enc.update(padded) + enc.finalize()
mac = hmaclib.new(hk, ct, hashlib.sha256).digest()
blob = MAGIC + bytes([VERSION]) + salt + iv + mac + ct

out_path = sys.argv[1] if len(sys.argv) > 1 else 'scadenzapp_backup_prova.bak'
with open(out_path, 'wb') as f:
    f.write(blob)

# riepilogo
per_cab = {c['name']: sum(1 for m in medicines if m['cabinet_id'] == c['id']) for c in cabinets}
print(f'OK: {out_path} ({len(blob)} byte) | password=demo1234')
print(f'farmaci: {len(medicines)} | per armadietto: {per_cab}')
scaduti = sum(1 for m in medicines if m['expiration_date'] < "2026-06-01")
print(f'di cui gia\' scaduti: {scaduti}')
