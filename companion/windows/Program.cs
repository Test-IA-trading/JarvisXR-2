using System;
using System.Collections.Generic;
using System.Diagnostics;
using System.IO;
using System.Linq;
using System.Management;
using System.Net;
using System.Net.Http;
using System.Net.NetworkInformation;
using System.Net.Sockets;
using System.Security.Cryptography;
using System.Text;
using System.Threading;

namespace JarvisXR.Companion
{
    internal static class Program
    {
        private static int Main(string[] args)
        {
            Console.OutputEncoding = new UTF8Encoding(false);
            try
            {
                using (var model = new OllamaChat())
                {
                    Console.WriteLine("Jarvis XR · Vérification de Qwen sur ce PC…");
                    EnsureOllama(model);
                    var probe = new List<ChatTurn> { new ChatTurn("user", "Réponds uniquement par JARVIS OK.") };
                    string reply = model.Ask(probe, 32);
                    Console.WriteLine("Réponse de qwen3:8b : " + new string(reply.Where(c => !Char.IsControl(c)).Take(120).ToArray()));
                    if (args.Contains("--check")) return 0;

                    IPAddress address = IPAddress.Loopback, mask = IPAddress.Parse("255.0.0.0");
                    if (!args.Contains("--pc")) ChooseHomeNetwork(out address, out mask);
                    byte[] key = new byte[8];
                    using (var random = RandomNumberGenerator.Create()) random.GetBytes(key);
                    string code = BitConverter.ToString(key).Replace("-", "");
                    var server = new LocalHttp(address, mask, code, model);
                    server.Start();
                    bool pcOnly = IPAddress.IsLoopback(address);
                    if (pcOnly)
                        Console.WriteLine("Chat sur ce PC uniquement. Pour l’iPhone, relance sur ton réseau domestique classé Privé dans Windows.");
                    else
                        Console.WriteLine("Sur ton iPhone connecté au même réseau privé, ouvre cette adresse dans Safari.");
                    Console.WriteLine("Adresse : " + server.Origin);
                    Console.WriteLine("Code : " + String.Join("-", Enumerable.Range(0, 4).Select(i => code.Substring(i * 4, 4))));
                    if (!pcOnly) Console.WriteLine("Utilise ce chat HTTP sur ton réseau de confiance. Le texte circule en clair sur le réseau local.");
                    Console.WriteLine("Laisse cette fenêtre ouverte pendant la discussion. Ctrl+C arrête le chat.");
                    if (!args.Contains("--no-browser"))
                    {
                        try { Process.Start(new ProcessStartInfo(server.Origin + "/#" + code) { UseShellExecute = true }); }
                        catch (System.ComponentModel.Win32Exception) { Console.WriteLine("Ouvre l’adresse dans ton navigateur pour discuter."); }
                    }
                    server.Serve();
                }
                return 0;
            }
            catch (System.Threading.Tasks.TaskCanceledException)
            { Console.Error.WriteLine("Qwen a dépassé le délai de trois minutes. Vérifie Ollama sur le PC, puis relance."); }
            catch (HttpRequestException)
            { Console.Error.WriteLine("Ollama ne répond pas correctement sur 127.0.0.1:11434. Ouvre Ollama, puis relance Jarvis."); }
            catch (SocketException ex)
            { Console.Error.WriteLine(ex.SocketErrorCode == SocketError.AddressAlreadyInUse ? "Le port 8765 est déjà utilisé sur ce PC. Vérifie si Jarvis est déjà ouvert." : "Windows a refusé l’ouverture du chat : " + ex.Message); }
            catch (Exception ex) { Console.Error.WriteLine(ex.Message); }
            return 1;
        }

        private static void EnsureOllama(OllamaChat model)
        {
            try { model.CheckModel(); return; }
            catch (HttpRequestException error)
            {
                // Start the installed server only when Windows reports a closed port.
                Exception cause = error;
                while (cause != null && !(cause is SocketException)) cause = cause.InnerException;
                if (cause == null || ((SocketException)cause).SocketErrorCode != SocketError.ConnectionRefused) throw;
            }
            string exe = Path.Combine(Environment.GetFolderPath(Environment.SpecialFolder.LocalApplicationData), "Programs", "Ollama", "ollama.exe");
            if (!File.Exists(exe)) throw new InvalidOperationException("Ouvre l’application Ollama installée sur ton PC, puis relance Jarvis.");
            var info = new ProcessStartInfo(exe, "serve") {
                UseShellExecute = false, CreateNoWindow = true, WindowStyle = ProcessWindowStyle.Hidden
            };
            info.EnvironmentVariables["OLLAMA_HOST"] = "127.0.0.1:11434";
            using (Process started = Process.Start(info))
            {
                for (int attempt = 0; attempt < 20; attempt++)
                {
                    Thread.Sleep(500);
                    try { model.CheckModel(); return; }
                    catch (HttpRequestException) { if (started.HasExited && attempt >= 2) break; }
                }
            }
            throw new InvalidOperationException("Le serveur Ollama n’a pas démarré. Ouvre Ollama puis relance Jarvis.");
        }

        private static void ChooseHomeNetwork(out IPAddress address, out IPAddress mask)
        {
            address = IPAddress.Loopback; mask = IPAddress.Parse("255.0.0.0");
            try
            {
                var privateIndexes = new HashSet<int>();
                using (var search = new ManagementObjectSearcher(@"root\StandardCimv2",
                    "SELECT InterfaceIndex FROM MSFT_NetConnectionProfile WHERE NetworkCategory = 1"))
                using (var profiles = search.Get())
                    foreach (ManagementObject profile in profiles)
                        using (profile) privateIndexes.Add(Convert.ToInt32(profile["InterfaceIndex"]));

                foreach (var adapter in NetworkInterface.GetAllNetworkInterfaces()
                         .Where(n => n.OperationalStatus == OperationalStatus.Up &&
                                     (n.NetworkInterfaceType == NetworkInterfaceType.Ethernet || n.NetworkInterfaceType == NetworkInterfaceType.Wireless80211))
                         .OrderByDescending(n => n.NetworkInterfaceType == NetworkInterfaceType.Wireless80211))
                {
                    var info = adapter.GetIPProperties();
                    var ipv4 = info.GetIPv4Properties();
                    if (ipv4 == null || !privateIndexes.Contains(ipv4.Index) ||
                        !info.GatewayAddresses.Any(g => g.Address.AddressFamily == AddressFamily.InterNetwork && !g.Address.Equals(IPAddress.Any))) continue;
                    foreach (var local in info.UnicastAddresses)
                    {
                        if (local.Address.AddressFamily != AddressFamily.InterNetwork || local.IPv4Mask == null || local.IPv4Mask.Equals(IPAddress.Any)) continue;
                        var octets = local.Address.GetAddressBytes();
                        if (octets[0] == 10 || (octets[0] == 192 && octets[1] == 168) || (octets[0] == 172 && octets[1] >= 16 && octets[1] <= 31))
                        { address = local.Address; mask = local.IPv4Mask; return; }
                    }
                }
            }
            catch (ManagementException) { }
            catch (UnauthorizedAccessException) { }
            catch (NetworkInformationException) { }
            catch (System.Runtime.InteropServices.COMException) { }
        }
    }
}
