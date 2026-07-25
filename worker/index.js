/**
 * Sono's site Worker.
 *
 * The landing page is plain static assets. Release artefacts (the DMG and the
 * Sparkle appcast) come from R2 instead, so cutting a build means uploading two
 * objects rather than redeploying the whole site.
 *
 * The paths are not negotiable: `SUFeedURL` is compiled into every shipped copy
 * of the app as https://heysono.app/appcast.xml, and the appcast's enclosure
 * points at https://heysono.app/releases/<file>. Both must be served from the
 * apex, which is why this is a Worker in front of the assets rather than an R2
 * custom domain on a subdomain.
 */

/** Maps a request path to its R2 key, or null when static assets should answer. */
function releaseKey(pathname) {
  if (pathname === '/appcast.xml') return 'appcast.xml';
  if (pathname.startsWith('/releases/')) {
    const key = pathname.slice('/releases/'.length);
    // No empty key, and no traversal out of the prefix.
    return key && !key.includes('..') ? key : null;
  }
  return null;
}

export default {
  async fetch(request, env) {
    const url = new URL(request.url);
    const key = releaseKey(url.pathname);
    if (key === null) return env.ASSETS.fetch(request);

    if (request.method !== 'GET' && request.method !== 'HEAD') {
      return new Response('Method not allowed', {
        status: 405,
        headers: { allow: 'GET, HEAD' },
      });
    }

    // Range only when the client actually asked for one. Passing the headers
    // unconditionally makes R2 populate object.range anyway, and every ordinary
    // download then comes back as a 206 carrying the whole file, which is the
    // wrong status and something caches and download managers treat differently.
    const wantsRange = request.headers.has('range');
    const object = await env.RELEASES.get(key, {
      range: wantsRange ? request.headers : undefined,
      onlyIf: request.headers,
    });
    if (object === null) return new Response('Not found', { status: 404 });

    const headers = new Headers();
    object.writeHttpMetadata(headers);
    headers.set('etag', object.httpEtag);
    headers.set('accept-ranges', 'bytes');
    // A given DMG never changes, so it can be cached hard. The appcast is the
    // opposite: cache it for long and nobody is offered an update.
    headers.set(
      'cache-control',
      key === 'appcast.xml' ? 'public, max-age=300' : 'public, max-age=31536000, immutable'
    );

    // No body means the conditional request was satisfied by the client's cache.
    if (!('body' in object)) return new Response(null, { status: 304, headers });

    if (wantsRange && object.range && 'offset' in object.range) {
      const end = object.range.offset + object.range.length - 1;
      headers.set('content-range', `bytes ${object.range.offset}-${end}/${object.size}`);
      return new Response(object.body, { status: 206, headers });
    }

    return new Response(request.method === 'HEAD' ? null : object.body, { headers });
  },
};
