from __future__ import annotations

from copy import deepcopy
from pathlib import Path

import yaml as pyyaml
from ruamel.yaml import YAML


ROOT = Path(__file__).resolve().parent
CURRENT_PATH = ROOT / "control-plane-1.17.1.yaml"
OLD_DEFAULTS_PATH = ROOT / "amplify-studio-1.17.1" / "values.yaml"
NEW_DEFAULTS_PATH = ROOT / "amplify-studio-1.18.1" / "values.yaml"
OUTPUT_PATH = ROOT / "control-plane-1.18.1.yaml"


def read_current_values() -> dict:
    raw = CURRENT_PATH.read_bytes()
    encoding = "utf-16" if raw.startswith((b"\xff\xfe", b"\xfe\xff")) else "utf-8-sig"
    values = pyyaml.safe_load(raw.decode(encoding))
    # `helm get values` prints this heading as an unindented line. YAML reads it
    # as a null-valued key, so discard it before migration.
    values.pop("USER-SUPPLIED VALUES", None)
    return values


def get_path(values: dict, path: str):
    node = values
    for key in path.split("."):
        node = node[key]
    return node


def has_path(values: dict, path: str) -> bool:
    try:
        get_path(values, path)
        return True
    except (KeyError, TypeError):
        return False


def set_path(values: dict, path: str, value) -> None:
    keys = path.split(".")
    node = values
    for key in keys[:-1]:
        node = node[key]
    node[keys[-1]] = deepcopy(value)


def overlay_changed(current, old_defaults, new_values) -> None:
    """Carry overrides whose path still exists unchanged in 1.18.1."""
    if not all(isinstance(item, dict) for item in (current, old_defaults, new_values)):
        return

    for key, current_value in current.items():
        if key not in old_defaults or key not in new_values:
            continue
        old_value = old_defaults[key]
        new_value = new_values[key]
        if all(isinstance(item, dict) for item in (current_value, old_value, new_value)):
            overlay_changed(current_value, old_value, new_value)
        elif current_value != old_value:
            new_values[key] = deepcopy(current_value)


def main() -> None:
    current = read_current_values()
    old_defaults = pyyaml.safe_load(OLD_DEFAULTS_PATH.read_text(encoding="utf-8"))

    round_trip_yaml = YAML()
    round_trip_yaml.preserve_quotes = True
    round_trip_yaml.width = 4096
    with NEW_DEFAULTS_PATH.open("r", encoding="utf-8") as stream:
        migrated = round_trip_yaml.load(stream)

    # Preserve actual cluster overrides on paths that did not move. This keeps
    # resources, autoscaling, ingress, probes and security settings while using
    # the new 1.18.1 defaults for versioned images and other changed defaults.
    overlay_changed(current, old_defaults, migrated)

    moved_paths = {
        "common.acceptGeneralConditions": "acceptGeneralConditions",
        "global.appEnv": "appEnv",
        "global.default_currency_code": "default_currency_code",
        "global.external_domain": "external_domain",
        "global.shared_lb_prefix": "shared_lb_prefix",
        "common.externalConfigMaps": "externalConfigMaps",
        "global.image.repository": "image.repository",
        "global.image.pullPolicy": "image.pullPolicy",
        "global.image.imagePullSecrets": "image.imagePullSecrets",
        "global.image.createPullSecret": "image.createPullSecret",
        "global.initContainers": "image.initContainers",
        "common.admin_email": "email.adminAddress",
        "common.email_host": "email.host",
        "common.authentication.email_port": "email.port",
        "common.email_frommailid": "email.fromAddress",
        "common.support_email": "email.supportAddress",
        "common.admin_mail_notify_event_status": "email.adminNotifyOnEvents",
        "api.fulfillment_email": "email.fulfillmentAddress",
        "api.tenant_approver_email": "email.tenantApproverAddress",
        "common.authentication.enabled": "email.authentication.enabled",
        "common.emailPassword.name": "email.credentials.name",
        "common.emailPassword.existingSecret": "email.credentials.existingSecret",
        "common.authentication.email_username": "email.credentials.username",
        "common.emailPassword.email_password": "email.credentials.password",
        "common.postgresCredentials.name": "secrets.postgres.name",
        "common.postgresCredentials.existingSecret": "secrets.postgres.existingSecret",
        "common.postgresCredentials.postgres_username": "secrets.postgres.username",
        "common.postgresCredentials.postgres_password": "secrets.postgres.password",
        "common.clusterDetails.name": "secrets.clusterDetails.name",
        "common.clusterDetails.existingSecret": "secrets.clusterDetails.existingSecret",
        "common.clusterDetails.jwt_secret": "secrets.clusterDetails.jwtSecret",
        "common.clusterDetails.cluster_id": "secrets.clusterDetails.clusterId",
        "common.mongoDB.name": "secrets.mongoDB.name",
        "common.mongoDB.existingSecret": "secrets.mongoDB.existingSecret",
        "common.mongoDB.mongo_uri": "secrets.mongoDB.uri",
        "global.volumeMounts": "storage.volumeMounts",
        "global.persistentVolumeClaim": "storage.persistentVolumeClaim",
        "common.efs_root": "storage.efsRoot",
        "common.efs": "storage.efs",
        "common.pvc": "storage.pvc",
        "global.rdb_name": "database.name",
        "global.rdb_endpoint": "database.endpoint",
        "global.apiAuthPort": "ports.apiAuthPort",
        "global.auditSvcPort": "ports.auditSvcPort",
        "global.imMonitorPort": "ports.imMonitorPort",
        "common.logFileEnabled": "logging.logFileEnabled",
        "common.logJsonEnabled": "logging.logJsonEnabled",
        "common.min_member_count": "hazelcast.min_member_count",
    }

    for old_path, new_path in moved_paths.items():
        if has_path(current, old_path):
            set_path(migrated, new_path, get_path(current, old_path))

    # The new chart represents the three old per-workload switches with one
    # global flag. The current release has all three set to false; `any` is also
    # the safest conversion if an older release has one of them enabled.
    old_cluster_flags = [
        get_path(current, path)
        for path in (
            "api.ClusterSecretKey.enabled",
            "im.ClusterSecretKey.enabled",
            "auditservice.ClusterSecretKey.enabled",
        )
        if has_path(current, path)
    ]
    migrated["clusterSecretKey"] = any(old_cluster_flags)

    # sftp_server_port changed location and its new default is intentionally a
    # quoted string. Keep the 1.18.1 default unless the cluster customized it.
    if get_path(current, "global.sftp_server_port") != get_path(old_defaults, "global.sftp_server_port"):
        set_path(migrated, "api.sftp_server_port", get_path(current, "global.sftp_server_port"))

    # Keep the new Alpine image/version unless it was explicitly customized.
    for field in ("name", "buildTag", "repository"):
        old_path = f"global.alpinetools.image.{field}"
        new_path = f"image.alpinetools.image.{field}"
        if has_path(current, old_path) and (
            not has_path(old_defaults, old_path)
            or get_path(current, old_path) != get_path(old_defaults, old_path)
        ):
            set_path(migrated, new_path, get_path(current, old_path))

    # Optional settings consumed by templates but absent from the generated
    # schema/default values files.
    if has_path(current, "common.singleTenantMode"):
        insertion_index = list(migrated).index("clusterSecretKey")
        migrated.insert(
            insertion_index,
            "singleTenantMode",
            get_path(current, "common.singleTenantMode"),
        )
        migrated.ca.items["externalConfigMaps"][2].value = (
            "\n\n# Single-tenant mode migrated from common.singleTenantMode\n"
        )
        migrated.yaml_set_comment_before_after_key(
            "clusterSecretKey",
            before=(
                "Set to true when deploying a shared Fusion - enables cluster-details "
                "secret injection in api, im, and auditservice"
            ),
        )
    if has_path(current, "global.clusterKey"):
        migrated["clusterKey"] = deepcopy(get_path(current, "global.clusterKey"))
    if has_path(current, "common.chimeraUsageReporting"):
        migrated["secrets"]["chimeraUsageReporting"] = deepcopy(
            get_path(current, "common.chimeraUsageReporting")
        )

    # Do not retain an HPA whose target Deployment is intentionally disabled.
    # The chart's HPA template does not also check marketplaceAgent.enabled.
    if not migrated["marketplaceAgent"]["enabled"]:
        migrated["marketplaceAgent"]["autoscaling"]["enabled"] = False

    with OUTPUT_PATH.open("w", encoding="utf-8", newline="\n") as stream:
        round_trip_yaml.dump(migrated, stream)

    print(f"Created {OUTPUT_PATH.name}")
    print(f"clusterSecretKey={migrated['clusterSecretKey']}")
    print("Sensitive values were not printed.")


if __name__ == "__main__":
    main()
