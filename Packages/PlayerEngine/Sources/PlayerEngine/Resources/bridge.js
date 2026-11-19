(() => {
  if (window.__bridge) return;

  const post = (message) => window.webkit.messageHandlers.player.postMessage(JSON.stringify(message));
  const player = () => document.getElementById('movie_player');
  const video = () => document.querySelector('video');

  const COMMANDS = new Set([
    'playVideo', 'pauseVideo', 'stopVideo', 'seekTo', 'setVolume', 'mute', 'unMute',
    'nextVideo', 'previousVideo', 'loadVideoById', 'setShuffle', 'setLoop',
  ]);

  window.__bridge = {
    cmd(name, ...args) {
      const p = player();
      if (!COMMANDS.has(name) || !p || typeof p[name] !== 'function') return null;
      return p[name](...args);
    },
  };

  const postSong = () => {
    const response = player()?.getPlayerResponse?.();
    if (!response?.videoDetails) return;
    post({ type: 'song', videoDetails: response.videoDetails, microformat: response.microformat });
  };

  const attach = () => {
    const p = player();
    const v = video();
    p.addEventListener('videodatachange', postSong);
    v.addEventListener('loadedmetadata', postSong);
    v.addEventListener('play', () => post({ type: 'playback', paused: false, time: v.currentTime }));
    v.addEventListener('pause', () => post({ type: 'playback', paused: true, time: v.currentTime }));
    v.addEventListener('timeupdate', () => post({ type: 'time', time: v.currentTime }));
    v.addEventListener('seeked', () => post({ type: 'time', time: v.currentTime }));
    post({ type: 'ready' });
    postSong();
  };

  const deadline = Date.now() + 30000;
  const wait = setInterval(() => {
    if (player() && video() && document.querySelector('ytmusic-app')) {
      clearInterval(wait);
      attach();
    } else if (Date.now() > deadline) {
      clearInterval(wait);
    }
  }, 250);
})();
