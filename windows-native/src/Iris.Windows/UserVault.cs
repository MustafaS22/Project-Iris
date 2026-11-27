using System.Security.Cryptography;
using System.Text;
using Iris.Core;

namespace Iris.Windows;

internal sealed class UserVault(string directory)
{
    private static readonly byte[] Entropy = "AriZe.Iris.Windows.v1"u8.ToArray();

    public string? Read(ProviderKind provider) => Read(KeyPath(provider));
    public string? ReadImageToken() => Read(ImageKeyPath());

    private static string? Read(string path)
    {
        if (!File.Exists(path)) return null;
        if (new FileInfo(path).Length > 8192) throw new InvalidDataException("Invalid saved credential.");
        var plaintext = ProtectedData.Unprotect(File.ReadAllBytes(path), Entropy, DataProtectionScope.CurrentUser);
        try { return Encoding.UTF8.GetString(plaintext); }
        finally { CryptographicOperations.ZeroMemory(plaintext); }
    }

    public void Save(ProviderKind provider, string credential) => Save(KeyPath(provider), credential);
    public void SaveImageToken(string credential) => Save(ImageKeyPath(), credential);

    private void Save(string path, string credential)
    {
        if (credential.Length is < 1 or > 2048 || credential.Any(char.IsWhiteSpace))
            throw new ArgumentException("Enter an API key without spaces.");
        Directory.CreateDirectory(directory);
        var plaintext = Encoding.UTF8.GetBytes(credential);
        var temporary = path + ".tmp";
        try
        {
            File.WriteAllBytes(temporary, ProtectedData.Protect(plaintext, Entropy, DataProtectionScope.CurrentUser));
            File.Move(temporary, path, overwrite: true);
        }
        finally
        {
            CryptographicOperations.ZeroMemory(plaintext);
            if (File.Exists(temporary)) File.Delete(temporary);
        }
    }

    public void Remove(ProviderKind provider) => File.Delete(KeyPath(provider));
    public void RemoveImageToken() => File.Delete(ImageKeyPath());
    private string ImageKeyPath() => Path.Combine(directory, "CloudflareImage.credential");

    private string KeyPath(ProviderKind provider)
    {
        if (!Enum.IsDefined(provider)) throw new ArgumentException("Unknown provider.");
        return Path.Combine(directory, provider + ".credential");
    }
}
