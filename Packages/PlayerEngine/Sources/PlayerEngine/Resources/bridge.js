(() => {
  const handler = window.webkit.messageHandlers.player;
  const post = (message) => handler.postMessage(JSON.stringify(message));
  const player = () => document.getElementById('movie_player');
  const video = () => document.querySelector('video');
  const bar = () => document.querySelector('ytmusic-player-bar');
  const queueElement = () => document.querySelector('#queue');
  const queueStore = () => queueElement()?.queue?.store?.store;

  const call = (target, name, ...args) => {
    if (typeof target?.[name] !== 'function') return false;
    target[name](...args);
    return true;
  };
  const click = (selector) => {
    const element = document.querySelector(selector);
    if (!element) return false;
    element.click();
    return true;
  };

  const MAX_ROWS = 500;
  const unwrap = (row) =>
    row?.playlistPanelVideoRenderer ?? row?.playlistPanelVideoWrapperRenderer?.primaryRenderer?.playlistPanelVideoRenderer ?? null;
  const rows = () => {
    const items = queueStore()?.getState?.()?.queue?.items ?? queueElement()?.queue?.getItems?.();
    return Array.isArray(items) ? items : null;
  };
  const text = (runs) => (runs?.runs ?? []).map((run) => run.text).join('');

  // The page may have reordered the queue since Swift read it, so every row operation names the row it expects.
  const rowMatches = (index, videoId, setId) => {
    const row = unwrap(rows()?.[index]);
    return !!row && row.videoId === videoId && (setId == null || row.playlistSetVideoId === setId);
  };
  const dispatch = (action) => call(queueElement(), 'dispatch', action);

  const enqueue = async (videoId, playNext) => {
    const app = document.querySelector('ytmusic-app');
    const state = queueStore()?.getState?.()?.queue;
    if (!app?.networkManager?.fetch || !state) return false;
    const position = playNext ? 'INSERT_AFTER_CURRENT_VIDEO' : 'INSERT_AT_END';
    const response = await app.networkManager.fetch('/music/get_queue', {
      queueContextParams: state.queueContextParams,
      queueInsertPosition: position,
      videoIds: [videoId],
    });
    const items = (response?.queueDatas ?? []).map((data) => data?.content).filter(Boolean);
    if (!items.length) return false;
    const index = playNext ? (state.selectedItemIndex ?? 0) + 1 : state.items.length;
    return dispatch({
      type: 'ADD_ITEMS',
      payload: { nextQueueItemId: state.nextQueueItemId, index, items, shuffleEnabled: false, shouldAssignIds: true },
    });
  };

  const operations = Object.freeze(Object.assign(Object.create(null), {
    play: () => call(player(), 'playVideo'),
    pause: () => call(player(), 'pauseVideo'),
    togglePlay: () => {
      const p = player();
      if (typeof p?.getPlayerState !== 'function') return false;
      return call(p, p.getPlayerState() === 2 ? 'playVideo' : 'pauseVideo');
    },
    next: () => click('.next-button.ytmusic-player-bar') || call(player(), 'nextVideo'),
    previous: () => click('.previous-button.ytmusic-player-bar') || call(player(), 'previousVideo'),
    seekTo: (time) => call(player(), 'seekTo', time),
    seekBy: (delta) => {
      const p = player();
      if (typeof p?.getCurrentTime !== 'function') return false;
      return call(p, 'seekTo', Math.max(0, p.getCurrentTime() + delta));
    },
    setVolume: (level) => call(bar(), 'updateVolume', level) || call(player(), 'setVolume', level),
    toggleMute: () => {
      const p = player();
      if (typeof p?.isMuted !== 'function') return call(bar(), 'onVolumeClick');
      return call(p, p.isMuted() ? 'unMute' : 'mute');
    },
    toggleShuffle: () => call(bar()?.queue, 'shuffle') || click('.shuffle.ytmusic-player-bar'),
    cycleRepeat: () => call(bar(), 'onRepeatButtonClick') || click('.repeat.ytmusic-player-bar'),
    jump: (index, videoId, setId) => rowMatches(index, videoId, setId) && dispatch({ type: 'SET_INDEX', payload: index }),
    remove: (index, videoId, setId) => rowMatches(index, videoId, setId) && dispatch({ type: 'REMOVE_ITEM', payload: index }),
    move: (from, videoId, setId, to) =>
      rowMatches(from, videoId, setId) && dispatch({ type: 'MOVE_ITEM', payload: { fromIndex: from, toIndex: to } }),
    enqueue,
  }));

  const run = async (action, args) => {
    const operation = typeof action === 'string' ? operations[action] : undefined;
    if (!operation || !Array.isArray(args)) return false;
    try {
      return (await operation(...args)) === true;
    } catch (error) {
      return false;
    }
  };

  try {
    Object.defineProperty(window, '__bridge', { value: Object.freeze({ run }), writable: false, configurable: false });
  } catch (error) {
    return;
  }

  let adShowing = false;
  let lastUnavailable = null;

  const postSong = () => {
    if (adShowing) return;
    const response = player()?.getPlayerResponse?.();
    const status = response?.playabilityStatus?.status;
    if (status && status !== 'OK') {
      const videoId = response.videoDetails?.videoId ?? new URL(location.href).searchParams.get('v');
      if (videoId && videoId !== lastUnavailable) {
        lastUnavailable = videoId;
        post({ type: 'error', kind: 'unavailable', videoId });
      }
      return;
    }
    if (!response?.videoDetails) return;
    lastUnavailable = null;
    post({ type: 'song', videoDetails: response.videoDetails, microformat: response.microformat });
  };

  const postVolume = () => {
    const p = player();
    if (typeof p?.getVolume === 'function') post({ type: 'volume', volume: p.getVolume(), muted: p.isMuted() });
  };

  let likeElement = null;
  const postLike = () => {
    const status = likeElement?.getAttribute('like-status');
    if (status) post({ type: 'like', status });
  };
  const likeObserver = new MutationObserver(postLike);
  const watchLike = () => {
    const element = document.querySelector('#like-button-renderer');
    if (element && element !== likeElement) {
      likeElement = element;
      likeObserver.disconnect();
      likeObserver.observe(element, { attributes: true, attributeFilter: ['like-status'] });
    }
    postLike();
  };

  let lastQueue = '';
  let lastRepeat = '';
  let lastShuffle = '';
  const postQueue = () => {
    const items = rows();
    if (items) {
      const projected = items.slice(0, MAX_ROWS).map((row) => {
        const inner = unwrap(row);
        if (!inner) return null;
        return {
          videoId: inner.videoId,
          title: text(inner.title),
          artist: inner.longBylineText?.runs?.[0]?.text ?? '',
          artwork: inner.thumbnail?.thumbnails?.at(-1)?.url,
          length: inner.lengthText ? text(inner.lengthText) : undefined,
          selected: !!(inner.selected || row.playlistPanelVideoWrapperRenderer?.selected),
          setId: inner.playlistSetVideoId,
        };
      });
      // A row that cannot be read would shift every later index, so the page's queue is not reported at all.
      const json = JSON.stringify(projected);
      if (!projected.includes(null) && json !== lastQueue) {
        lastQueue = json;
        post({ type: 'queue', items: projected });
      }
    }
    const state = queueStore()?.getState?.()?.queue;
    if (state?.repeatMode && state.repeatMode !== lastRepeat) {
      lastRepeat = state.repeatMode;
      post({ type: 'repeat', repeatMode: state.repeatMode });
    }
    const shuffle = JSON.stringify(!!state?.shuffleEnabled);
    if (state && shuffle !== lastShuffle) {
      lastShuffle = shuffle;
      post({ type: 'shuffle', shuffle: !!state.shuffleEnabled });
    }
  };

  let queueTimer = null;
  const schedulePostQueue = () => {
    clearTimeout(queueTimer);
    queueTimer = setTimeout(postQueue, 100);
  };
  let subscribedStore = null;
  const subscribeQueue = () => {
    const store = queueStore();
    if (!store?.subscribe) return false;
    if (store !== subscribedStore) {
      subscribedStore = store;
      store.subscribe(schedulePostQueue);
    }
    postQueue();
    return true;
  };

  const watchAd = () => {
    const p = player();
    const showing = !!p && (p.classList.contains('ad-showing') || p.classList.contains('ad-interrupting'));
    if (showing === adShowing) return;
    adShowing = showing;
    post({ type: 'ad', ad: showing });
    if (!showing) postSong();
  };

  const attach = () => {
    const p = player();
    const v = video();
    p.addEventListener('videodatachange', () => {
      postSong();
      watchLike();
      schedulePostQueue();
    });
    v.addEventListener('loadedmetadata', postSong);
    v.addEventListener('play', () => post({ type: 'playback', paused: false, time: v.currentTime }));
    v.addEventListener('pause', () => post({ type: 'playback', paused: true, time: v.currentTime }));
    v.addEventListener('timeupdate', () => post({ type: 'time', time: v.currentTime }));
    v.addEventListener('seeked', () => post({ type: 'time', time: v.currentTime }));
    v.addEventListener('volumechange', postVolume);
    new MutationObserver(watchAd).observe(p, { attributes: true, attributeFilter: ['class'] });
    post({ type: 'ready' });
    watchAd();
    postSong();
    postVolume();
    watchLike();
    // The video may have started before the bridge attached, so its 'play' event was already missed.
    post({ type: 'playback', paused: v.paused, time: v.currentTime });
    // The queue element can appear after the player does.
    const queueDeadline = Date.now() + 30000;
    const queueWait = setInterval(() => {
      if (subscribeQueue() || Date.now() > queueDeadline) clearInterval(queueWait);
    }, 1000);
  };

  const deadline = Date.now() + 15000;
  const wait = setInterval(() => {
    if (player() && video() && document.querySelector('ytmusic-app')) {
      clearInterval(wait);
      attach();
    } else if (Date.now() > deadline) {
      clearInterval(wait);
    }
  }, 250);
})();
