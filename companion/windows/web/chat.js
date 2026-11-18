'use strict';
const el = id => document.getElementById(id);
const pairForm = el('pair-form');
const compose = el('compose');
const statusText = el('status');
const reset = el('reset');
const draft = el('message');
let code = '';
let turns = [];
let busy = false;

function setBusy(value) {
  busy = value;
  pairForm.querySelector('button').disabled = value;
  compose.querySelector('button').disabled = value;
  reset.disabled = value;
}
function clearConversation() {
  turns = [];
  el('history').replaceChildren();
  draft.value = '';
  statusText.textContent = '';
}
function showPairing() {
  code = '';
  clearConversation();
  el('pair').hidden = false;
  el('chat').hidden = true;
  reset.hidden = true;
}
async function post(path, payload, key) {
  let response;
  try {
    response = await fetch(path, {
      method: 'POST', credentials: 'omit', cache: 'no-store', redirect: 'error',
      headers: { 'Content-Type': 'application/json', 'X-Jarvis-Code': key },
      body: JSON.stringify(payload)
    });
  } catch {
    throw new Error('Le PC ne répond plus. Vérifie le Wi-Fi et la fenêtre Jarvis sur le PC.');
  }
  const body = await response.json();
  if (!response.ok) {
    if (response.status === 401 && code) showPairing();
    throw new Error(body.error || 'Le PC a interrompu la demande.');
  }
  return body;
}
async function pair(value) {
  if (busy) return;
  const key = value.toUpperCase().replace(/[-\s]/g, '');
  if (!/^[0-9A-F]{16}$/.test(key)) {
    statusText.textContent = 'Recopie les quatre groupes du code affiché sur le PC.';
    return;
  }
  setBusy(true);
  statusText.textContent = 'Connexion au PC…';
  try {
    const info = await post('/api/session', {}, key);
    code = key;
    el('code').value = '';
    el('pair').hidden = true;
    el('chat').hidden = false;
    reset.hidden = false;
    el('model').textContent = info.model + ' · Sur ton PC';
    statusText.textContent = '';
    draft.focus();
  } catch (error) { statusText.textContent = error.message; }
  finally { setBusy(false); }
}
function bubble(role, content) {
  const article = document.createElement('article');
  article.className = role;
  const who = document.createElement('strong');
  who.textContent = role === 'user' ? 'Toi' : 'Jarvis';
  const text = document.createElement('p');
  text.textContent = content;
  article.append(who, text);
  el('history').append(article);
  return article;
}
async function send() {
  const question = draft.value.trim();
  if (busy || !code || !question) return;
  setBusy(true);
  const user = { role: 'user', content: question };
  const pending = bubble('user', question);
  draft.readOnly = true;
  statusText.textContent = 'Qwen prépare sa réponse…';
  try {
    const body = await post('/api/chat', { messages: [...turns, user] }, code);
    if (typeof body.reply !== 'string' || !body.reply.trim()) throw new Error('Réponse vide du PC.');
    bubble('assistant', body.reply);
    turns = [...turns, user, { role: 'assistant', content: body.reply.slice(0, 6000) }].slice(-8);
    draft.value = '';
    statusText.textContent = '';
    compose.scrollIntoView({ block: 'nearest' });
  } catch (error) {
    pending.remove();
    statusText.textContent = error.message;
  } finally {
    draft.readOnly = false;
    setBusy(false);
  }
}
pairForm.addEventListener('submit', event => { event.preventDefault(); pair(el('code').value); });
compose.addEventListener('submit', event => { event.preventDefault(); send(); });
draft.addEventListener('keydown', event => {
  if (event.key === 'Enter' && !event.shiftKey && !event.isComposing) { event.preventDefault(); send(); }
});
reset.addEventListener('click', () => { clearConversation(); draft.focus(); });
if (location.hash) {
  const key = location.hash.slice(1);
  history.replaceState(null, '', location.pathname);
  pair(key);
}
