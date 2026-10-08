// Offline shell: network first, fall back to the last cached copy. API calls are never cached.
const CACHE='sidadi-v1';
self.addEventListener('install',e=>self.skipWaiting());
self.addEventListener('activate',e=>e.waitUntil(self.clients.claim()));
self.addEventListener('fetch',e=>{
  const r=e.request;
  if(r.method!=='GET'||new URL(r.url).origin!==location.origin) return;
  e.respondWith(fetch(r).then(res=>{ const c=res.clone(); caches.open(CACHE).then(k=>k.put(r,c)); return res; }).catch(()=>caches.match(r)));
});
