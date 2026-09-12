// Cloudflare Worker: iframe-headers-flujo
//
// Deployado sobre flujo.ripaconsultora.net/* para modificar los response
// headers que setea Cloudflare Access (bloquean iframing por default con
// X-Frame-Options: DENY y CSP frame-ancestors 'none').
//
// Los Workers corren DESPUES de Access, asi que pueden reescribir la
// respuesta de la propia pagina de login/SSO ademas de las del origin.
//
// Deploy via API (recreable con el mismo bearer):
//   PUT /accounts/{account_id}/workers/scripts/iframe-headers-flujo
//   POST /zones/{zone_id}/workers/routes  {pattern, script}

addEventListener('fetch', event => {
  event.respondWith(handleRequest(event.request));
});

const ALLOWED_FRAME_ANCESTORS =
  "frame-ancestors 'self' " +
  "https://v0-bi-client-intranet.vercel.app " +
  "https://*.ripaconsultora.net; " +
  "connect-src 'self' http://127.0.0.1:*; " +
  "default-src https: 'unsafe-inline'";

async function handleRequest(request) {
  const response = await fetch(request);
  const headers = new Headers(response.headers);
  headers.delete('X-Frame-Options');
  headers.set('Content-Security-Policy', ALLOWED_FRAME_ANCESTORS);
  return new Response(response.body, {
    status: response.status,
    statusText: response.statusText,
    headers,
  });
}
