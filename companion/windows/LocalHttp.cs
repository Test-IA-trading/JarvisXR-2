using System;
using System.Collections.Generic;
using System.Diagnostics;
using System.IO;
using System.Linq;
using System.Net;
using System.Net.Sockets;
using System.Reflection;
using System.Text;
using System.Threading;
using System.Web.Script.Serialization;

namespace JarvisXR.Companion
{
    internal sealed class RequestError : Exception
    {
        internal readonly int Status;
        internal RequestError(int status, string message) : base(message) { Status = status; }
    }

    internal sealed class LocalHttp
    {
        private readonly IPAddress address;
        private readonly IPAddress mask;
        private readonly string code;
        private readonly OllamaChat model;
        private readonly SemaphoreSlim clients = new SemaphoreSlim(12);
        private readonly SemaphoreSlim generation = new SemaphoreSlim(1);
        private readonly Dictionary<string, byte[]> pages = new Dictionary<string, byte[]>();
        private readonly TcpListener listener;
        internal string Origin { get; private set; }

        internal LocalHttp(IPAddress address, IPAddress mask, string code, OllamaChat model)
        {
            this.address = address; this.mask = mask; this.code = code; this.model = model;
            foreach (string file in new[] { "index.html", "app.css", "chat.js" })
            {
                using (var resource = Assembly.GetExecutingAssembly().GetManifestResourceStream("Jarvis." + file))
                using (var bytes = new MemoryStream())
                {
                    if (resource == null) throw new InvalidOperationException("Ressource absente : " + file);
                    resource.CopyTo(bytes);
                    pages.Add(file, bytes.ToArray());
                }
            }
            listener = new TcpListener(address, 8765);
            listener.ExclusiveAddressUse = true;
        }

        internal void Start()
        {
            listener.Start(16);
            Origin = "http://" + address + ":" + ((IPEndPoint)listener.LocalEndpoint).Port;
        }

        internal void Serve()
        {
            for (;;)
            {
                TcpClient socket = listener.AcceptTcpClient();
                IPAddress remote = ((IPEndPoint)socket.Client.RemoteEndPoint).Address;
                if (!SameSubnet(remote) || !clients.Wait(0)) { socket.Close(); continue; }
                ThreadPool.QueueUserWorkItem(delegate {
                    try { Handle(socket); }
                    catch (IOException) { }
                    catch (SocketException) { }
                    finally { socket.Close(); clients.Release(); }
                });
            }
        }

        private bool SameSubnet(IPAddress remote)
        {
            if (IPAddress.IsLoopback(address)) return IPAddress.IsLoopback(remote);
            byte[] a = address.GetAddressBytes(), b = remote.GetAddressBytes(), m = mask.GetAddressBytes();
            if (a.Length != b.Length) return false;
            for (int i = 0; i < a.Length; i++)
                if ((a[i] & m[i]) != (b[i] & m[i])) return false;
            return true;
        }

        private void Handle(TcpClient socket)
        {
            socket.ReceiveTimeout = 5000; socket.SendTimeout = 5000;
            using (var io = new BufferedStream(socket.GetStream()))
            {
                try { Dispatch(io); }
                catch (RequestError error) { SendJson(io, error.Status, new { error = error.Message }); }
                catch (IOException) { throw; }
                catch (Exception) { SendJson(io, 500, new { error = "Le compagnon a interrompu cette demande." }); }
            }
        }

        private void Dispatch(Stream io)
        {
            var clock = Stopwatch.StartNew();
            int headerBytes = 0;
            string[] line = ReadLine(io, clock, ref headerBytes).Split(' ');
            if (line.Length != 3 || (line[2] != "HTTP/1.1" && line[2] != "HTTP/1.0"))
                throw new RequestError(400, "Requête HTTP invalide.");
            var headers = new Dictionary<string, string>(StringComparer.OrdinalIgnoreCase);
            for (;;)
            {
                string item = ReadLine(io, clock, ref headerBytes);
                if (item.Length == 0) break;
                int colon = item.IndexOf(':');
                if (colon < 1) throw new RequestError(400, "En-tête HTTP invalide.");
                string name = item.Substring(0, colon);
                if (name.Any(c => !Char.IsLetterOrDigit(c) && c != '-') || headers.ContainsKey(name))
                    throw new RequestError(400, "En-tête HTTP invalide.");
                headers.Add(name, item.Substring(colon + 1).Trim());
            }
            string value;
            if (!headers.TryGetValue("Host", out value) || "http://" + value != Origin ||
                (headers.TryGetValue("Origin", out value) && value != Origin))
                throw new RequestError(403, "Ouvre l’adresse affichée sur le PC.");
            if (headers.ContainsKey("Transfer-Encoding")) throw new RequestError(400, "Format HTTP non accepté.");

            if (line[0] == "GET")
            {
                string file = line[1] == "/" ? "index.html" : line[1] == "/app.css" ? "app.css" : line[1] == "/chat.js" ? "chat.js" : null;
                if (file == null) throw new RequestError(404, "Page introuvable.");
                string type = file == "index.html" ? "text/html" : file == "app.css" ? "text/css" : "text/javascript";
                Send(io, 200, type, pages[file]);
                return;
            }
            if (line[0] != "POST") throw new RequestError(405, "Méthode indisponible.");
            if (line[1] != "/api/session" && line[1] != "/api/chat") throw new RequestError(404, "Commande inconnue.");
            if (!headers.TryGetValue("X-Jarvis-Code", out value) || !SameCode(value, code))
                throw new RequestError(401, "Vérifie le code affiché sur le PC.");
            if (!headers.TryGetValue("Content-Type", out value) ||
                !String.Equals(value.Split(';')[0].Trim(), "application/json", StringComparison.OrdinalIgnoreCase))
                throw new RequestError(415, "Une demande JSON est attendue.");
            int length;
            if (!headers.TryGetValue("Content-Length", out value) ||
                !Int32.TryParse(value, System.Globalization.NumberStyles.None, System.Globalization.CultureInfo.InvariantCulture, out length))
                throw new RequestError(411, "Longueur du message manquante.");
            if (length > 64000) throw new RequestError(413, "Message trop long.");
            var bytes = new byte[length];
            for (int offset = 0; offset < length;)
            {
                if (clock.ElapsedMilliseconds > 8000) throw new RequestError(408, "Lecture interrompue.");
                int count = io.Read(bytes, offset, length - offset);
                if (count == 0) throw new RequestError(400, "Message incomplet.");
                offset += count;
            }
            if (line[1] == "/api/session") { SendJson(io, 200, new { model = OllamaChat.Model }); return; }

            string body;
            try { body = new UTF8Encoding(false, true).GetString(bytes); }
            catch (DecoderFallbackException) { throw new RequestError(400, "Encodage UTF-8 attendu."); }
            var turns = OllamaChat.RecentTurns(body);
            if (!generation.Wait(0)) throw new RequestError(429, "Qwen prépare déjà une réponse. Réessaie dans un instant.");
            string answer;
            try { answer = model.Ask(turns, 512); }
            catch (System.Threading.Tasks.TaskCanceledException) { throw new RequestError(504, "Qwen a mis trop de temps à répondre."); }
            catch (InvalidOperationException ex) { throw new RequestError(502, ex.Message); }
            catch (Exception) { throw new RequestError(502, "Ollama est inaccessible sur le PC. Ouvre Ollama et réessaie."); }
            finally { generation.Release(); }
            SendJson(io, 200, new { reply = answer });
        }

        private static string ReadLine(Stream io, Stopwatch clock, ref int total)
        {
            var line = new StringBuilder();
            while (++total <= 12288 && clock.ElapsedMilliseconds <= 8000)
            {
                int c = io.ReadByte();
                if (c == 13 && io.ReadByte() == 10) { total++; return line.ToString(); }
                if (c < 32 || c > 126) throw new RequestError(400, "Ligne HTTP invalide.");
                line.Append((char)c);
            }
            throw new RequestError(400, "En-têtes trop longs ou incomplets.");
        }

        private static bool SameCode(string a, string b)
        {
            if (a.Length != b.Length) return false;
            int difference = 0;
            for (int i = 0; i < b.Length; i++) difference |= a[i] ^ b[i];
            return difference == 0;
        }

        private static void SendJson(Stream stream, int status, object obj)
        {
            Send(stream, status, "application/json", Encoding.UTF8.GetBytes(new JavaScriptSerializer().Serialize(obj)));
        }

        private static void Send(Stream stream, int status, string type, byte[] bytes)
        {
            string head = "HTTP/1.1 " + status + (status == 200 ? " OK\r\n" : " Error\r\n") +
                "Connection: close\r\nContent-Type: " + type + "; charset=utf-8\r\nContent-Length: " + bytes.Length +
                "\r\nCache-Control: no-store\r\nReferrer-Policy: no-referrer\r\nX-Content-Type-Options: nosniff\r\n" +
                "Content-Security-Policy: default-src 'none'; script-src 'self'; style-src 'self'; connect-src 'self'; img-src 'self'; base-uri 'none'; frame-ancestors 'none'; form-action 'none'\r\n\r\n";
            byte[] header = Encoding.ASCII.GetBytes(head);
            stream.Write(header, 0, header.Length); stream.Write(bytes, 0, bytes.Length); stream.Flush();
        }
    }
}
