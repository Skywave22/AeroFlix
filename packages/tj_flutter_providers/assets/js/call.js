// TJ Flutter Providers — call wrapper (adapted from Nuvio JsBindings staticCallCode)
// Dart loads this AFTER provider code. It resolves a JSON string of streams and
// also publishes globalThis.__TJ_DONE / __TJ_RESULT / __TJ_ERROR so Dart can poll
// for completion without relying on flutter_js promise handling.
//
// Expected globals set by Dart before loading provider:
//   globalThis.__TJ_CALL_ARGS = { tmdbId, mediaType, season, episode }
//   globalThis.TMDB_API_KEY, SCRAPER_ID, SCRAPER_SETTINGS
//
// Provider contract (from Plugins-TJ src/_lib/adapter.js makeProvider):
//   getStreams(tmdbId, mediaType, season, episode) -> Promise<Array<Stream>>
//   Stream = { name, title, url, quality, provider, language?, size?, headers?, subtitles? }

(async function () {
  var payload;
  try {
    var getStreams = (typeof module !== 'undefined' && module.exports && module.exports.getStreams) || globalThis.getStreams;
    if (!getStreams) {
      // Some bundles export via exports.getStreams
      if (typeof exports !== 'undefined' && exports.getStreams) getStreams = exports.getStreams;
    }
    if (!getStreams) {
      console.error('getStreams function not found on module.exports or globalThis');
      return JSON.stringify([]);
    }
    var args = globalThis.__TJ_CALL_ARGS || {};
    var season = args.season == null ? undefined : args.season;
    var episode = args.episode == null ? undefined : args.episode;
    var result = await getStreams(String(args.tmdbId || ''), String(args.mediaType || 'movie'), season, episode);
    payload = JSON.stringify(result || []);
    globalThis.__TJ_RESULT = payload;
    globalThis.__TJ_DONE = true;
    globalThis.__TJ_ERROR = null;
    return payload;
  } catch (e) {
    var msg = e && e.message ? e.message : String(e);
    console.error('getStreams error:', msg, e && e.stack ? e.stack : '');
    globalThis.__TJ_RESULT = JSON.stringify([]);
    globalThis.__TJ_DONE = true;
    globalThis.__TJ_ERROR = msg;
    return globalThis.__TJ_RESULT;
  }
})();
