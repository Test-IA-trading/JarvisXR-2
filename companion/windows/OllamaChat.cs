using System;
using System.Collections.Generic;
using System.Linq;
using System.Net.Http;
using System.Text;
using System.Web.Script.Serialization;

namespace JarvisXR.Companion
{
    public sealed class ChatTurn
    {
        public string role { get; set; }
        public string content { get; set; }

        public ChatTurn() { }
        public ChatTurn(string role, string content) { this.role = role; this.content = content; }
    }

    public sealed class Conversation
    {
        public ChatTurn[] messages { get; set; }
    }

    internal sealed class ModelList
    {
        public ModelEntry[] models { get; set; }
    }
    internal sealed class ModelEntry { public string name { get; set; } }
    internal sealed class ChatReply { public bool done { get; set; } public ChatTurn message { get; set; } }

    internal sealed class OllamaChat : IDisposable
    {
        internal const string Model = "qwen3:8b";
        internal const int MaxQuestion = 2000;
        private readonly HttpClient client = new HttpClient(new HttpClientHandler {
            UseProxy = false, AllowAutoRedirect = false
        }) {
            BaseAddress = new Uri("http://127.0.0.1:11434/"),
            Timeout = TimeSpan.FromMinutes(3),
            MaxResponseContentBufferSize = 1024 * 1024
        };

        internal void CheckModel()
        {
            using (var response = client.GetAsync("api/tags").GetAwaiter().GetResult())
            {
                response.EnsureSuccessStatusCode();
                string body = response.Content.ReadAsStringAsync().GetAwaiter().GetResult();
                var list = new JavaScriptSerializer().Deserialize<ModelList>(body);
                if (list == null || list.models == null || !list.models.Any(m => m != null && m.name == Model))
                    throw new InvalidOperationException("Ollama répond, mais qwen3:8b manque dans la liste des modèles.");
            }
        }

        internal static List<ChatTurn> RecentTurns(string body)
        {
            Conversation conversation;
            try { conversation = new JavaScriptSerializer().Deserialize<Conversation>(body); }
            catch (Exception error)
            {
                if (!(error is ArgumentException) && !(error is InvalidOperationException) &&
                    !(error is FormatException)) throw;
                throw new RequestError(400, "Conversation illisible.");
            }
            var turns = conversation == null ? null : conversation.messages;
            if (turns == null || turns.Length == 0 || turns.Length > 9 || turns.Length % 2 != 1)
                throw new RequestError(400, "Envoie une question et jusqu’à quatre échanges précédents.");
            for (int i = 0; i < turns.Length; i++)
            {
                var turn = turns[i];
                bool user = i % 2 == 0;
                if (turn == null || turn.role != (user ? "user" : "assistant") ||
                    String.IsNullOrWhiteSpace(turn.content) || turn.content.Length > (user ? MaxQuestion : 6000))
                    throw new RequestError(400, "Vérifie la longueur et l’ordre des messages.");
            }
            int first = turns.Length - 1;
            int used = turns[first].content.Length;
            while (first >= 2)
            {
                int pairLength = turns[first - 1].content.Length + turns[first - 2].content.Length;
                if (used + pairLength > 4200) break;
                used += pairLength;
                first -= 2;
            }
            return turns.Skip(first).ToList();
        }

        internal string Ask(List<ChatTurn> conversation, int replyBudget)
        {
            var messages = new List<ChatTurn> {
                new ChatTurn("system", "Tu es Jarvis, l’assistant personnel de ton interlocuteur. Réponds dans sa langue, en français par défaut. Tu peux discuter. Si une action demande un outil, indique que tu ne peux pas encore la réaliser depuis ce chat.")
            };
            messages.AddRange(conversation);
            var payload = new {
                model = Model, messages = messages, stream = false, think = false,
                options = new { num_ctx = 4096, num_predict = replyBudget }
            };
            var json = new JavaScriptSerializer();
            using (var data = new StringContent(json.Serialize(payload), Encoding.UTF8, "application/json"))
            using (var response = client.PostAsync("api/chat", data).GetAwaiter().GetResult())
            {
                if (!response.IsSuccessStatusCode)
                    throw new InvalidOperationException("Ollama refuse la demande (HTTP " + (int)response.StatusCode + "). Vérifie que qwen3:8b est chargé sur le PC.");
                var reply = json.Deserialize<ChatReply>(response.Content.ReadAsStringAsync().GetAwaiter().GetResult());
                if (reply == null || !reply.done || reply.message == null || reply.message.role != "assistant" || String.IsNullOrWhiteSpace(reply.message.content))
                    throw new InvalidOperationException("Ollama a terminé sans fournir de réponse utilisable.");
                return reply.message.content.Trim();
            }
        }
        public void Dispose() { client.Dispose(); }
    }
}
