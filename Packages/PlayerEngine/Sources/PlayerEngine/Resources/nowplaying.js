// Runs in an isolated content world: the page cannot see `__nowPlaying` or reach the handlers set here.
(() => {
  const session = navigator.mediaSession;
  if (!session) return;
  const post = (action, time) => window.webkit.messageHandlers.nowPlaying.postMessage({ action, time });
  const register = () => {
    for (const action of ['play', 'pause', 'previoustrack', 'nexttrack']) {
      session.setActionHandler(action, () => post(action));
    }
    session.setActionHandler('seekto', (details) => post('seekto', details.seekTime));
  };
  register();

  const update = (info) => {
    // Observed: Control Centre keeps next/previous disabled unless the handlers are set again once playback is live.
    register();
    if (!info) {
      session.metadata = null;
      session.playbackState = 'none';
      session.setPositionState();
      return;
    }
    session.metadata = new MediaMetadata({
      title: info.title,
      artist: info.artist,
      album: info.album ?? '',
      artwork: info.artwork ? [{ src: info.artwork }] : [],
    });
    session.playbackState = info.playing ? 'playing' : 'paused';
    if (info.duration > 0) {
      session.setPositionState({ duration: info.duration, position: Math.min(Math.max(info.elapsed, 0), info.duration), playbackRate: 1 });
    } else {
      session.setPositionState();
    }
  };
  Object.defineProperty(window, '__nowPlaying', { value: Object.freeze({ update }), writable: false, configurable: false });
})();
