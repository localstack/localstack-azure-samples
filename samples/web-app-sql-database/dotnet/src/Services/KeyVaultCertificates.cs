using System.Security.Cryptography;
using System.Security.Cryptography.X509Certificates;
using Azure.Identity;
using Azure.Security.KeyVault.Certificates;
using Azure.Security.KeyVault.Secrets;

namespace VacationPlanner.Services;

/// <summary>Key Vault certificate helpers: the TLS certificate served on port 8443 and the <c>/api/certificate</c> probe.</summary>
public static class KeyVaultCertificates
{
    /// <summary>
    /// Downloads the certificate (public part plus private key, stored by Key Vault as a linked secret)
    /// so Kestrel can serve HTTPS with it.
    /// </summary>
    public static async Task<X509Certificate2> LoadServerCertificateAsync(string vaultUri, string certificateName, CancellationToken cancellationToken)
    {
        var secretClient = new SecretClient(new Uri(vaultUri), new DefaultAzureCredential());
        var secret = (await secretClient.GetSecretAsync(certificateName, cancellationToken: cancellationToken)).Value;
        if (string.IsNullOrEmpty(secret.Value))
        {
            throw new InvalidOperationException($"Secret [{certificateName}] has no value");
        }

        // Key Vault returns the PFX as base64, or PEM (certificate and key concatenated) as plain text.
        return secret.Properties.ContentType == "application/x-pkcs12"
            ? X509CertificateLoader.LoadPkcs12(Convert.FromBase64String(secret.Value), password: null)
            : X509Certificate2.CreateFromPem(secret.Value, secret.Value);
    }

    /// <summary>Returns the certificate's name, subject and SHA-1 thumbprint (lowercase hex), as the Python sample does.</summary>
    public static async Task<object> GetCertificateInfoAsync(string vaultUri, string certificateName, CancellationToken cancellationToken)
    {
        var client = new CertificateClient(new Uri(vaultUri), new DefaultAzureCredential());
        var certificate = (await client.GetCertificateAsync(certificateName, cancellationToken)).Value;
        if (certificate.Cer is null)
        {
            throw new InvalidOperationException($"Certificate '{certificateName}' has no public bytes (cer is None)");
        }

        if (certificate.Policy is null)
        {
            throw new InvalidOperationException($"Certificate '{certificateName}' has no policy");
        }

        return new
        {
            name = certificate.Name,
            subject = certificate.Policy.Subject,
            thumbprint = Convert.ToHexStringLower(SHA1.HashData(certificate.Cer)),
        };
    }
}
