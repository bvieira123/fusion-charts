"""Migrate Amplify Fusion data-plane values from chart 1.17.1 to 1.18.1.

The source is the full output of ``helm get values --all``.  The migration
starts with the 1.18.1 defaults, overlays only real 1.17.1 customizations on
unchanged paths, and explicitly translates settings that moved in 1.18.1.
"""

from __future__ import annotations

import base64
from copy import deepcopy
from pathlib import Path

from ruamel.yaml import YAML


ROOT = Path(__file__).resolve().parent
OLD_CHART_VALUES = ROOT / "amplify-fusion-1.17.1" / "values.yaml"
NEW_CHART_VALUES = ROOT / "amplify-fusion-1.18.1" / "values.yaml"
SOURCE_VALUES = ROOT / "dataplane-1.17.1.yaml"
TARGET_VALUES = ROOT / "dataplane-1.18.1.yaml"
JAVA_SECURITY_OPT = "-Djava.security.properties=/etc/fusion-java-security/java.security"


yaml = YAML()
yaml.preserve_quotes = True
yaml.width = 4096


def load(path: Path, encoding: str = "utf-8"):
    with path.open("r", encoding=encoding) as stream:
        return yaml.load(stream)


def get(tree, path):
    value = tree
    for key in path:
        value = value[key]
    return value


def put(tree, path, value):
    parent = tree
    for key in path[:-1]:
        parent = parent[key]
    parent[path[-1]] = deepcopy(value)


def overlay_same_paths(current, old, target):
    """Overlay customized values only where the key exists at the same path."""
    for key, current_value in current.items():
        if key not in old or key not in target:
            continue
        old_value = old[key]
        target_value = target[key]
        if (
            isinstance(current_value, dict)
            and isinstance(old_value, dict)
            and isinstance(target_value, dict)
        ):
            overlay_same_paths(current_value, old_value, target_value)
        elif current_value != old_value:
            target[key] = deepcopy(current_value)


def copy_value(current, target, source_path, target_path):
    put(target, target_path, get(current, source_path))


def decode_secret(value, label):
    """Convert old Secret.data base64 values to new Secret.stringData text."""
    if not value:
        return value
    try:
        return base64.b64decode(str(value), validate=True).decode("utf-8")
    except (ValueError, UnicodeDecodeError) as exc:
        raise ValueError(f"{label} is not valid UTF-8 base64") from exc


old_defaults = load(OLD_CHART_VALUES)
new_defaults = load(NEW_CHART_VALUES)
current = load(SOURCE_VALUES, "utf-16")
current.pop("USER-SUPPLIED VALUES", None)
result = deepcopy(new_defaults)

# Preserve customizations on component paths that did not move. New 1.18.1
# defaults remain in place wherever the cluster still used the 1.17.1 default.
overlay_same_paths(current, old_defaults, result)

# In 1.18.1 a single-node internal Valkey is explicitly standalone. The new
# default replicasPerMaster=1 is valid for its two-node default, but invalid
# when preserving this environment's customized clusterSize=1.
if int(result["valkey"]["internal"]["clusterSize"]) == 1:
    result["valkey"]["internal"]["replicasPerMaster"] = 0

# global/common values promoted to the document root.
for old_path, new_path in (
    (("common", "acceptGeneralConditions"), ("acceptGeneralConditions",)),
    (("global", "appEnv"), ("appEnv",)),
    (("global", "clusterKey"), ("clusterKey",)),
    (("global", "external_domain"), ("external_domain",)),
    (("global", "ctlplane_domain"), ("ctlplane_domain",)),
    (("global", "shared_lb_prefix"), ("shared_lb_prefix",)),
    (("common", "sftp_server_port"), ("sftp_server_port",)),
    (("common", "externalConfigMaps"), ("externalConfigMaps",)),
    (("global", "awsRegion"), ("awsRegion",)),
    (("global", "multihost"), ("multihost",)),
):
    copy_value(current, result, old_path, new_path)

# Image registry/pull policy and init-container resources are installation
# settings. Versioned helper-image tags intentionally remain at 1.18.1.
for key in ("repository", "pullPolicy", "imagePullSecrets", "createPullSecret"):
    copy_value(current, result, ("global", "image", key), ("image", key))
copy_value(current, result, ("global", "initContainers"), ("image", "initContainers"))
if current["global"]["alpinetools"] != old_defaults["global"]["alpinetools"]:
    copy_value(current, result, ("global", "alpinetools"), ("image", "alpinetools"))

# E-mail settings were consolidated under email.*.
for old_key, new_key in (
    ("email_host", "host"),
    ("email_port", "port"),
    ("email_usetls", "useTls"),
    ("email_authentication", "authentication"),
    ("email_frommailid", "fromAddress"),
    ("admin_email", "adminAddress"),
    ("support_email", "supportAddress"),
):
    copy_value(current, result, ("common", old_key), ("email", new_key))
copy_value(current, result, ("common", "fromMail", "name"), ("email", "credentials", "name"))
copy_value(
    current,
    result,
    ("common", "fromMail", "existingSecret"),
    ("email", "credentials", "existingSecret"),
)
copy_value(current, result, ("common", "email_username"), ("email", "credentials", "username"))
if not current["common"]["fromMail"]["existingSecret"]:
    result["email"]["credentials"]["password"] = decode_secret(
        current["common"]["fromMail"]["password"], "common.fromMail.password"
    )

# Secret configuration moved and managed secret payloads changed from data
# (base64) to stringData (plain text).
for old_name, new_name in (("clusterDetails", "clusterDetails"), ("datagridCredentials", "datagrid")):
    result["secrets"][new_name]["name"] = current["common"][old_name]["name"]
    result["secrets"][new_name]["existingSecret"] = current["common"][old_name]["existingSecret"]

if not current["common"]["clusterDetails"]["existingSecret"]:
    for key in ("jwtSecret", "clusterId"):
        result["secrets"]["clusterDetails"][key] = decode_secret(
            current["common"]["clusterDetails"][key], f"common.clusterDetails.{key}"
        )
if not current["common"]["datagridCredentials"]["existingSecret"]:
    result["secrets"]["datagrid"]["password"] = decode_secret(
        current["common"]["datagridCredentials"]["password"],
        "common.datagridCredentials.password",
    )

# Storage moved from global/common into storage.*.
copy_value(current, result, ("global", "claimName"), ("storage", "claimName"))
copy_value(current, result, ("global", "volumeStorageName"), ("storage", "volumeStorageName"))
for old_key, new_key in (
    ("s3_payload", "s3Payload"),
    ("persistence", "persistence"),
    ("azfiles", "azfiles"),
    ("efs", "efs"),
    ("nfs", "nfs"),
    ("pvc", "pvc"),
):
    copy_value(current, result, ("common", old_key), ("storage", new_key))

# TLS key names and certificate mode changed in 1.18.1.
old_certificate = current["common"]["certificate"]
domain_certificate = result["tls"]["domainCertificate"]
domain_certificate["name"] = old_certificate["name"]
domain_certificate["password"] = old_certificate["password"]
domain_certificate["manuallyCreated"] = old_certificate["enabled"]
domain_certificate["rotationPeriod"] = old_certificate["generate"]["duration"]
for key in ("renewBefore", "subject", "rotationPolicy", "issuerRef"):
    domain_certificate[key] = deepcopy(old_certificate["generate"][key])

old_ssh = current["common"]["ssh_certificate"]
ssh_certificate = result["tls"]["sshCertificate"]
for old_key, new_key in (
    ("enabled", "enabled"),
    ("manually_created", "manuallyCreated"),
    ("password", "password"),
    ("rotationPeriod", "rotationPeriod"),
    ("renewBefore", "renewBefore"),
    ("rotationPolicy", "rotationPolicy"),
    ("algorithm", "algorithm"),
    ("keySize", "keySize"),
    ("issuerRef", "issuerRef"),
):
    ssh_certificate[new_key] = deepcopy(old_ssh[old_key])
for key in ("truststore", "truststorePassword", "domainCertWatch"):
    copy_value(current, result, ("common", key), ("tls", key))

# Encryption, logging and telemetry moved to dedicated root sections.
copy_value(current, result, ("global", "encryptAtRest"), ("encryption", "encryptAtRest"))
copy_value(current, result, ("global", "kms"), ("encryption", "kms"))
copy_value(current, result, ("common", "logFileEnabled"), ("logging", "logFileEnabled"))
copy_value(current, result, ("common", "logJsonEnabled"), ("logging", "logJsonEnabled"))
copy_value(current, result, ("common", "openTelemetry"), ("openTelemetry",))

# Keep the corrected 1.18.1 template expression unless clusterRefId was
# explicitly customized (the old default refers to .Values.global.clusterKey).
if current["common"]["clusterRefId"] != old_defaults["common"]["clusterRefId"]:
    copy_value(current, result, ("common", "clusterRefId"), ("clusterRefId",))

# AWS credentials moved out of each workload. Translate them only when AWS is
# in use or credentials differ from the 1.17.1 placeholders.
for component, secret_name in (
    ("inboundWorker", "inboundWorkerAws"),
    ("orchestrator", "orchestratorAws"),
):
    aws = current[component]["aws"]
    old_aws = old_defaults[component]["aws"]
    if aws["enabled"] or aws != old_aws:
        result["secrets"][secret_name]["accessKey"] = aws["Access_Key"]
        result["secrets"][secret_name]["secretKey"] = aws["Secret_Key"]
        if aws.get("Region") and aws.get("Region") != old_aws.get("Region"):
            result["awsRegion"] = aws["Region"]

# Apply the local TLS/RSA compatibility solution to customized JVM options.
for component in ("inboundWorker", "orchestrator"):
    opts = str(result[component]["javaOpts"]).strip()
    if JAVA_SECURITY_OPT not in opts.split():
        result[component]["javaOpts"] = f"{opts} {JAVA_SECURITY_OPT}"

with TARGET_VALUES.open("w", encoding="utf-8", newline="\n") as stream:
    yaml.dump(result, stream)

print(f"Generated {TARGET_VALUES}")
