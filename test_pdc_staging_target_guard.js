'use strict';
const assert = require('assert');
const { spawnSync } = require('child_process');

const probe = String.raw`
import importlib.util
import base64
import hashlib
import json
import os
from pathlib import Path
import sys
import tempfile
import types

connector_calls = []
def connector_spy(*args, **kwargs):
    connector_calls.append((args, kwargs))
    return 'connection-spy-result'
sys.modules['psycopg2'] = types.SimpleNamespace(connect=connector_spy)
spec = importlib.util.spec_from_file_location('pdc_staging_runtime_guard_test', 'scripts/pdc_staging_runtime.py')
module = importlib.util.module_from_spec(spec)
spec.loader.exec_module(module)
ref = module.EXPECTED_STAGING_REF
ca_dir = tempfile.TemporaryDirectory(prefix='pdc-staging-ca-')
ca_path = Path(ca_dir.name) / 'trusted-root.pem'
ca_path.write_bytes(Path('tests/fixtures/pdc_test_root_ca.pem').read_bytes())
os.environ[module.SSLROOTCERT_ENV] = str(ca_path.resolve())
ca_sha256 = hashlib.sha256(ca_path.read_bytes()).hexdigest()
os.environ[module.SSLROOTCERT_SHA256_ENV] = ca_sha256
accepted = [
    ('project', f'https://{ref}.supabase.co'),
    ('project', f'https://{ref}.supabase.co/'),
    ('database', f'postgresql://postgres:placeholder@db.{ref}.supabase.co:5432/postgres'),
    ('database', f'postgres://postgres.{ref}:placeholder@aws-0-ap-southeast-1.pooler.supabase.com:5432/postgres'),
    ('database', f'postgresql://postgres.{ref}:placeholder@aws-0-ap-southeast-1.pooler.supabase.com:6543/postgres'),
]
rejected = [
    ('project', f'https://{ref}@attacker.example'),
    ('project', f'https://attacker.example/?project={ref}'),
    ('project', f'https://{ref}.attacker.example'),
    ('project', f'http://{ref}.supabase.co'),
    ('project', f'https://attacker.example/{ref}'),
    ('project', f'https://{ref}.supabase.co:444'),
    ('project', f'https://user@{ref}.supabase.co'),
    ('project', f'https://{ref}.supabase.co:notaport'),
    ('project', f'https://{ref}.supabase.co:443'),
    ('project', f'https://{ref}.supabase.co/rest/v1/'),
    ('project', f'https://{ref}.supabase.co/?x=1'),
    ('project', f'https://{ref}.supabase.co/#fragment'),
    ('project', f'https://{ref}.supabase.co./'),
    ('database', f'postgresql://{ref}:placeholder@attacker.example:5432/postgres'),
    ('database', f'postgresql://postgres:placeholder@attacker.example:5432/postgres?project={ref}'),
    ('database', f'postgresql://postgres:placeholder@{ref}.attacker.example:5432/postgres'),
    ('database', f'http://db.{ref}.supabase.co:5432/postgres'),
    ('database', f'postgresql://postgres:placeholder@attacker.example:5432/{ref}'),
    ('database', f'postgresql://postgres.wrongref:placeholder@aws-0-ap-southeast-1.pooler.supabase.com:5432/postgres'),
    ('database', f'postgresql://postgres.{ref}:placeholder@aws-0-ap-southeast-1.pooler.supabase.com:443/postgres'),
    ('database', f'postgresql://postgres.{ref}:placeholder@aws-0-ap-southeast-1.pooler.supabase.com.attacker.example:5432/postgres'),
    ('database', f'postgresql://postgres:placeholder@db.{ref}.supabase.co:5432/postgres?host=attacker.example'),
    ('database', f'postgresql://postgres:placeholder@db.{ref}.supabase.co:5432/postgres?hostaddr=203.0.113.10'),
    ('database', f'postgresql://postgres:placeholder@db.{ref}.supabase.co:5432/postgres?service=attacker'),
    ('database', f'postgresql://postgres:placeholder@db.{ref}.supabase.co:5432/other_database'),
    ('database', f'postgresql://postgres:placeholder@db.{ref}.supabase.co:notaport/postgres'),
    ('database', f'postgresql://postgres:placeholder@db.{ref}.supabase.co/postgres'),
    ('database', f'postgresql://Postgres:placeholder@db.{ref}.supabase.co:5432/postgres'),
    ('database', f'postgresql://postgres@db.{ref}.supabase.co:5432/postgres'),
    ('database', f'postgresql://postgres:@db.{ref}.supabase.co:5432/postgres'),
    ('database', f'postgresql://postgres:placeholder@db.{ref}.supabase.co.:5432/postgres'),
    ('database', f'postgresql://postgres:placeholder@db.{ref}.supabase.co:5432/postgres?sslmode=require'),
    ('database', f'postgresql://postgres:placeholder@db.{ref}.supabase.co:5432/postgres#fragment'),
    ('database', f' postgresql://postgres:placeholder@db.{ref}.supabase.co:5432/postgres'),
    ('database', f'postgresql://postgres:placeholder@db.{ref}.supabase.co:5432/postgres\\n'),
    ('database', f'postgresql://postgres:{ref}@attacker.example:5432/postgres'),
    ('database', f'postgresql://postgres:prefix{module.PRODUCTION_REF}suffix@db.{ref}.supabase.co:5432/postgres'),
    ('database', f'postgresql://postgres:prefix%{ord(module.PRODUCTION_REF[0]):02x}{module.PRODUCTION_REF[1:]}suffix@db.{ref}.supabase.co:5432/postgres'),
    ('database', f'postgresql://postgres:prefix%25{ord(module.PRODUCTION_REF[0]):02x}{module.PRODUCTION_REF[1:]}suffix@db.{ref}.supabase.co:5432/postgres'),
    ('database', f'postgresql://postgres:ok%pw@db.{ref}.supabase.co:5432/postgres'),
    ('database', f'postgresql://postgres:ok%2pw@db.{ref}.supabase.co:5432/postgres'),
    ('database', f'postgresql://postgres:ok%GGpw@db.{ref}.supabase.co:5432/postgres'),
    ('database', f'postgresql://postgres:ok%25%GGpw@db.{ref}.supabase.co:5432/postgres'),
]
for kind, value in accepted:
    module.assert_staging_target(**{f'{kind}_url': value})
for kind, value in rejected:
    before = len(connector_calls)
    try:
        if kind == 'database':
            os.environ['PDC_STAGING_DATABASE_URL'] = value
            module.get_conn()
        else:
            module.assert_staging_target(project_url=value)
    except Exception as error:
        assert len(connector_calls) == before
        assert 'placeholder' not in str(error)
        continue
    raise AssertionError(f'guard accepted spoofed {kind} endpoint: {value}')
database_accepted = [value for kind, value in accepted if kind == 'database']
valid_database = database_accepted[0]
tls_rejected = []
os.environ.pop(module.SSLROOTCERT_ENV, None)
tls_rejected.append('missing')
os.environ[module.SSLROOTCERT_ENV] = 'relative-ca.pem'
tls_rejected.append('relative')
os.environ[module.SSLROOTCERT_ENV] = str((Path(ca_dir.name) / 'missing.pem').resolve())
tls_rejected.append('missing-file')
non_pem = Path(ca_dir.name) / 'not-a-ca.txt'
non_pem.write_text('not a certificate', encoding='ascii')
os.environ[module.SSLROOTCERT_ENV] = str(non_pem.resolve())
tls_rejected.append('non-pem')
malformed_pem = Path(ca_dir.name) / 'malformed-ca.pem'
malformed_pem.write_text(
    '-----BEGIN CERTIFICATE-----\\nNOT-A-CERTIFICATE\\n-----END CERTIFICATE-----\\n',
    encoding='ascii',
)
canonical_der = base64.b64decode(b''.join(
    line.strip() for line in ca_path.read_bytes().splitlines()
    if not line.startswith(b'-----')))
critical_true = bytes.fromhex('0603551d130101ff')
assert canonical_der.count(critical_true) == 1
explicit_false_der = canonical_der.replace(
    critical_true, bytes.fromhex('0603551d13010100'), 1)
explicit_false = Path(ca_dir.name) / 'explicit-false-critical.pem'
encoded = base64.b64encode(explicit_false_der)
explicit_false.write_bytes(
    b'-----BEGIN CERTIFICATE-----\\n' +
    b'\\n'.join(encoded[i:i + 64] for i in range(0, len(encoded), 64)) +
    b'\\n-----END CERTIFICATE-----\\n')
noncanonical_source = Path('tests/fixtures/pdc_test_ca_without_keycertsign.pem').resolve()
noncanonical_der = base64.b64decode(b''.join(
    line.strip() for line in noncanonical_source.read_bytes().splitlines()
    if not line.startswith(b'-----')))
canonical_key_usage = bytes.fromhex('0603551d0f0101ff040403020780')
assert noncanonical_der.count(canonical_key_usage) == 1
noncanonical_der = noncanonical_der.replace(
    canonical_key_usage, bytes.fromhex('0603551d0f0101ff040403020784'), 1)
try:
    module._assert_ca_certificate(noncanonical_der)
except ValueError:
    pass
else:
    raise AssertionError('DER guard accepted non-zero unused Key Usage bits')

def der_tlv(tag, value):
    assert len(value) < 128
    return bytes([tag, len(value)]) + value
def synthetic_ca_path_length(integer_value):
    basic_constraints = der_tlv(0x30,
        der_tlv(0x01, bytes([0xff])) + der_tlv(0x02, integer_value))
    extension = der_tlv(0x30,
        der_tlv(0x06, bytes.fromhex('551d13')) +
        der_tlv(0x01, bytes([0xff])) +
        der_tlv(0x04, basic_constraints))
    return der_tlv(0x30,
        der_tlv(0x30, der_tlv(0xA3, der_tlv(0x30, extension))))
module._assert_ca_certificate(synthetic_ca_path_length(bytes([0])))
nonminimal_path_length = synthetic_ca_path_length(bytes([0, 0]))
try:
    module._assert_ca_certificate(nonminimal_path_length)
except ValueError:
    pass
else:
    raise AssertionError('DER guard accepted non-minimal Basic Constraints INTEGER')
def synthetic_ca_key_usage(bit_string_value):
    basic_constraints = der_tlv(0x30, der_tlv(0x01, bytes([0xff])))
    basic_extension = der_tlv(0x30,
        der_tlv(0x06, bytes.fromhex('551d13')) +
        der_tlv(0x01, bytes([0xff])) +
        der_tlv(0x04, basic_constraints))
    key_usage_extension = der_tlv(0x30,
        der_tlv(0x06, bytes.fromhex('551d0f')) +
        der_tlv(0x01, bytes([0xff])) +
        der_tlv(0x04, der_tlv(0x03, bit_string_value)))
    return der_tlv(0x30,
        der_tlv(0x30, der_tlv(0xA3, der_tlv(0x30, basic_extension + key_usage_extension))))
module._assert_ca_certificate(synthetic_ca_key_usage(bytes([2, 4])))
try:
    module._assert_ca_certificate(synthetic_ca_key_usage(bytes([0, 4])))
except ValueError:
    pass
else:
    raise AssertionError('DER guard accepted non-minimal Key Usage named-bit encoding')
canonical_unknown_oid = bytes.fromhex('0603551d0e')
assert canonical_der.count(canonical_unknown_oid) == 1
malformed_unknown_oid_der = canonical_der.replace(canonical_unknown_oid, bytes.fromhex('0603551d8e'), 1)
try:
    module._assert_ca_certificate(malformed_unknown_oid_der)
except ValueError:
    pass
else:
    raise AssertionError('DER guard accepted malformed extension OID base-128 encoding')
noncanonical_key_usage = Path(ca_dir.name) / 'noncanonical-key-usage.pem'
encoded = base64.b64encode(noncanonical_der)
noncanonical_key_usage.write_bytes(
    b'-----BEGIN CERTIFICATE-----\\n' +
    b'\\n'.join(encoded[i:i + 64] for i in range(0, len(encoded), 64)) +
    b'\\n-----END CERTIFICATE-----\\n')
semantic_non_ca = Path('tests/fixtures/pdc_test_non_ca.pem').resolve()
semantic_bad_key_usage = Path('tests/fixtures/pdc_test_ca_without_keycertsign.pem').resolve()
os.environ[module.SSLROOTCERT_ENV] = str(malformed_pem.resolve())
tls_rejected.append('malformed-pem')
os.environ[module.SSLROOTCERT_ENV] = str(ca_path.resolve())
os.environ.pop(module.SSLROOTCERT_SHA256_ENV, None)
tls_rejected.append('missing-sha256')
os.environ[module.SSLROOTCERT_SHA256_ENV] = '0' * 64
tls_rejected.append('wrong-sha256')
tls_rejected.extend(['semantic-non-ca', 'semantic-bad-key-usage', 'explicit-false-critical', 'noncanonical-key-usage'])
for label in tls_rejected:
    if label == 'missing':
        os.environ.pop(module.SSLROOTCERT_ENV, None)
    elif label == 'relative':
        os.environ[module.SSLROOTCERT_ENV] = 'relative-ca.pem'
    elif label == 'missing-file':
        os.environ[module.SSLROOTCERT_ENV] = str((Path(ca_dir.name) / 'missing.pem').resolve())
    elif label == 'non-pem':
        os.environ[module.SSLROOTCERT_ENV] = str(non_pem.resolve())
    elif label == 'malformed-pem':
        os.environ[module.SSLROOTCERT_ENV] = str(malformed_pem.resolve())
    elif label == 'semantic-non-ca':
        os.environ[module.SSLROOTCERT_ENV] = str(semantic_non_ca)
    elif label == 'semantic-bad-key-usage':
        os.environ[module.SSLROOTCERT_ENV] = str(semantic_bad_key_usage)
    elif label == 'explicit-false-critical':
        os.environ[module.SSLROOTCERT_ENV] = str(explicit_false.resolve())
    elif label == 'noncanonical-key-usage':
        os.environ[module.SSLROOTCERT_ENV] = str(noncanonical_key_usage.resolve())
    else:
        os.environ[module.SSLROOTCERT_ENV] = str(ca_path.resolve())
    if label == 'missing-sha256':
        os.environ.pop(module.SSLROOTCERT_SHA256_ENV, None)
    elif label == 'wrong-sha256':
        os.environ[module.SSLROOTCERT_SHA256_ENV] = '0' * 64
    elif label not in ('semantic-non-ca', 'semantic-bad-key-usage', 'explicit-false-critical', 'noncanonical-key-usage'):
        os.environ[module.SSLROOTCERT_SHA256_ENV] = ca_sha256
    else:
        os.environ[module.SSLROOTCERT_SHA256_ENV] = hashlib.sha256(
            Path(os.environ[module.SSLROOTCERT_ENV]).read_bytes()).hexdigest()
    before = len(connector_calls)
    os.environ['PDC_STAGING_DATABASE_URL'] = valid_database
    try:
        module.get_conn()
    except Exception:
        assert len(connector_calls) == before
    else:
        raise AssertionError(f'TLS guard accepted {label} CA configuration')
os.environ[module.SSLROOTCERT_ENV] = str(ca_path.resolve())
os.environ[module.SSLROOTCERT_SHA256_ENV] = ca_sha256
for value in database_accepted:
    os.environ['PDC_STAGING_DATABASE_URL'] = value
    assert module.get_conn() == 'connection-spy-result'
assert len(connector_calls) == len(database_accepted)
for value, (args, kwargs) in zip(database_accepted, connector_calls):
    assert args == (value,)
    assert kwargs == {'sslmode': 'verify-full', 'sslrootcert': str(ca_path.resolve())}
print(json.dumps({'accepted': len(accepted), 'rejected': len(rejected), 'tls_rejected': len(tls_rejected), 'connector_calls': len(connector_calls)}))
`;
const result = spawnSync('python3', ['-I', '-c', probe], { encoding: 'utf8' });
assert.strictEqual(result.status, 0, result.stderr || result.stdout);
const report = JSON.parse(result.stdout.trim());
assert.deepStrictEqual(report, { accepted: 5, rejected: 43, tls_rejected: 11, connector_calls: 3 });
console.log('PDC staging parsed-host endpoint and connector-spy guard passed');
