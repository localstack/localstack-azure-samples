"""Configuration loading for the Vacation Planner sample.

The PostgreSQL connection settings do not reach the app as environment variables. They live in an Azure
App Configuration store: ``PG_HOST``, ``PG_PORT`` and ``PG_DATABASE`` as plain key-values, ``PG_USER`` and
``PG_PASSWORD`` as Key Vault references to two secrets. This module loads them once at startup with the
Azure App Configuration provider (``azure-appconfiguration-provider``):

- the store endpoint comes from the ``Endpoints__AppConfiguration`` app setting;
- one ``DefaultAzureCredential`` authenticates to the store and, through ``keyvault_credential``, to Key
  Vault; on App Service it resolves to the user-assigned managed identity selected by ``AZURE_CLIENT_ID``,
  on a developer machine to the signed-in Azure CLI user;
- the provider resolves the Key Vault references itself, so the returned mapping already holds the secret
  values and the app has a single configuration source.

Only the ``PG_*`` keys are loaded. The load is retried for a few minutes so a role assignment that has not
propagated yet, or a store that is still starting, produces log lines rather than a crash loop.
"""

import logging
import os
import time
from collections.abc import Mapping

from azure.appconfiguration import AzureAppConfigurationClient, SecretReferenceConfigurationSetting
from azure.appconfiguration.provider import SettingSelector, load
from azure.identity import DefaultAzureCredential

logger = logging.getLogger(__name__)
logger.setLevel(logging.INFO)

ENDPOINT_SETTING = "Endpoints__AppConfiguration"
KEY_FILTER = "PG_*"
LOAD_ATTEMPTS = 3
STARTUP_TIMEOUT_SECONDS = 60
RETRY_DELAY_SECONDS = 10
UNRESOLVED_REFERENCE_PREFIX = "@Microsoft."


def _endpoint() -> str:
    """Return the store endpoint from the environment, failing loudly when it is missing or unresolved."""
    value = os.environ.get(ENDPOINT_SETTING, "").strip()
    if not value:
        raise RuntimeError(
            f"The setting {ENDPOINT_SETTING} was not found. Set it to the App Configuration store endpoint "
            "(az appconfig show --query endpoint)."
        )
    if value.startswith(UNRESOLVED_REFERENCE_PREFIX):
        raise RuntimeError(
            f"The setting {ENDPOINT_SETTING} holds an unresolved App Service reference ({value[:48]}...). "
            "The platform did not resolve it; set the plain store endpoint instead."
        )
    return value


def _reject_unresolved_references(settings: Mapping[str, str]) -> None:
    """Fail when a loaded value is a literal App Service reference instead of a resolved value."""
    unresolved = sorted(
        key for key, value in settings.items() if str(value).startswith(UNRESOLVED_REFERENCE_PREFIX)
    )
    if unresolved:
        raise RuntimeError(
            f"The settings {', '.join(unresolved)} hold unresolved App Service references; "
            "they must be plain values or App Configuration Key Vault references."
        )


def _key_vault_reference_keys(endpoint: str, credential: DefaultAzureCredential) -> list[str]:
    """Return the PG_* keys stored as Key Vault references, for the startup log line (never their values)."""
    client = AzureAppConfigurationClient(endpoint, credential)
    return sorted(
        setting.key
        for setting in client.list_configuration_settings(key_filter=KEY_FILTER)
        if isinstance(setting, SecretReferenceConfigurationSetting)
    )


def load_settings() -> Mapping[str, str]:
    """Load the PG_* settings from App Configuration, resolving the Key Vault references."""
    endpoint = _endpoint()
    credential = DefaultAzureCredential()
    settings: Mapping[str, str] | None = None

    for attempt in range(1, LOAD_ATTEMPTS + 1):
        try:
            settings = load(
                endpoint=endpoint,
                credential=credential,
                keyvault_credential=credential,
                selects=[SettingSelector(key_filter=KEY_FILTER)],
                startup_timeout=STARTUP_TIMEOUT_SECONDS,
            )
            break
        except Exception as exc:  # noqa: BLE001 - every failure is reported the same way
            logger.warning(
                "App Configuration load failed (attempt %d/%d) against %s: %s: %s. Likely causes: the role "
                "assignment of the identity has not propagated yet, the endpoint is unreachable, or the "
                "Key Vault credential cannot read the referenced secrets.",
                attempt,
                LOAD_ATTEMPTS,
                endpoint,
                type(exc).__name__,
                exc,
            )
            if attempt == LOAD_ATTEMPTS:
                raise RuntimeError(
                    f"Could not load the configuration from App Configuration {endpoint} after "
                    f"{LOAD_ATTEMPTS} attempts: {type(exc).__name__}: {exc}"
                ) from exc
            time.sleep(RETRY_DELAY_SECONDS)

    assert settings is not None
    _reject_unresolved_references(settings)

    keys = sorted(settings.keys())
    try:
        references = _key_vault_reference_keys(endpoint, credential)
    except Exception as exc:  # noqa: BLE001 - the summary is informational only
        logger.warning("Could not list the Key Vault references of the store: %s: %s", type(exc).__name__, exc)
        references = []

    logger.info(
        "Loaded %d settings from App Configuration %s (%s); %d Key Vault references resolved (%s)",
        len(keys),
        endpoint,
        ", ".join(keys),
        len(references),
        ", ".join(references) or "none",
    )
    return settings
