"""Certificate helper module for Azure Key Vault integration."""
import base64
import logging
import os
import ssl
import tempfile

from azure.identity import DefaultAzureCredential
from azure.keyvault.certificates import CertificateClient
from azure.keyvault.secrets import SecretClient
from cryptography.hazmat.primitives.serialization import (
    Encoding,
    NoEncryption,
    PrivateFormat,
    pkcs12,
)

logger = logging.getLogger(__name__)


def get_ssl_context_from_keyvault(vault_url: str, cert_name: str) -> ssl.SSLContext:
    """
    Downloads a certificate from Key Vault and creates an SSLContext for Flask.
    The certificate's private key is stored as a linked secret in Key Vault.

    Returns:
        An SSLContext configured with the certificate and private key.
    """
    credential = DefaultAzureCredential()
    secret_client = SecretClient(vault_url=vault_url, credential=credential)
    secret = secret_client.get_secret(cert_name)

    if not secret.value:
        raise ValueError(f"Secret [{cert_name}] has no value")

    # Key Vault returns PFX as base64 or PEM as plain text
    if secret.properties.content_type == "application/x-pkcs12":
        pfx_bytes = base64.b64decode(secret.value)
        private_key, certificate, chain = pkcs12.load_key_and_certificates(pfx_bytes, None)

        if not certificate:
            raise ValueError(f"Certificate [{cert_name}] could not be loaded")

        if not private_key:
            raise ValueError(f"Private key for [{cert_name}] could not be loaded")

        cert_pem = certificate.public_bytes(Encoding.PEM)
        key_pem = private_key.private_bytes(Encoding.PEM, PrivateFormat.TraditionalOpenSSL, NoEncryption())

        # Include chain certs if present
        if chain:
            for ca_cert in chain:
                cert_pem += ca_cert.public_bytes(Encoding.PEM)
    else:
        # PEM format - value contains cert + key concatenated
        cert_pem = secret.value.encode()
        key_pem = secret.value.encode()

    # Write to temp files (ssl module needs file paths)
    cert_file = tempfile.NamedTemporaryFile(delete=False, suffix=".pem")
    key_file = tempfile.NamedTemporaryFile(delete=False, suffix=".pem")

    cert_file.write(cert_pem)
    key_file.write(key_pem)
    cert_file.close()
    key_file.close()

    ctx = ssl.SSLContext(ssl.PROTOCOL_TLS_SERVER)
    ctx.load_cert_chain(certfile=cert_file.name, keyfile=key_file.name)

    # Clean up temp files after loading
    os.unlink(cert_file.name)
    os.unlink(key_file.name)

    logger.info("SSL context created successfully from Key Vault certificate [%s]", cert_name)
    return ctx


def get_certificate_info(vault_url: str, cert_name: str) -> dict:
    credential = DefaultAzureCredential()
    cert_client = CertificateClient(vault_url=vault_url, credential=credential)
    cert = cert_client.get_certificate(cert_name)

    return {
        "name": cert.name
    }