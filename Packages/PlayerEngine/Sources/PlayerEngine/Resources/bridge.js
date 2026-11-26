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

  const until = async (probe, ms) => {
    const end = Date.now() + ms;
    for (;;) {
      const value = probe();
      if (value || Date.now() > end) return value;
      await new Promise((resolve) => setTimeout(resolve, 250));
    }
  };

  // After a reload the page fills its own queue first; items added before that would be replaced.
  const enqueue = async (videoIds, playNext) => {
    const app = document.querySelector('ytmusic-app');
    const state = await until(() => {
      const queue = queueStore()?.getState?.()?.queue;
      return queue?.items?.length ? queue : null;
    }, 10000);
    if (!app?.networkManager?.fetch || !state) return false;
    const position = playNext ? 'INSERT_AFTER_CURRENT_VIDEO' : 'INSERT_AT_END';
    const response = await app.networkManager.fetch('/music/get_queue', {
      queueContextParams: state.queueContextParams,
      queueInsertPosition: position,
      videoIds,
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
      const state = p.getPlayerState();
      return call(p, state === 1 || state === 3 ? 'pauseVideo' : 'playVideo');
    },
    next: () => click('.next-button.ytmusic-player-bar') || call(player(), 'nextVideo'),
    previous: () => click('.previous-button.ytmusic-player-bar') || call(player(), 'previousVideo'),
    seekTo: (time) => call(player(), 'seekTo', time),
    seekBy: (delta) => {
      const p = player();
      if (typeof p?.getCurrentTime !== 'function') return false;
      return call(p, 'seekTo', Math.max(0, p.getCurrentTime() + delta));
    },
    // The player bar maps its slider through a curve (50 → 20), while volume events report the player's linear value.
    setVolume: (level) => call(player(), 'setVolume', level) || call(bar(), 'updateVolume', level),
    unmute: () => {
      const p = player();
      if (typeof p?.isMuted !== 'function') return false;
      if (p.isMuted()) call(p, 'unMute');
      return !p.isMuted();
    },
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
    enqueue: (videoIds, playNext) => Array.isArray(videoIds) && videoIds.length > 0 && enqueue(videoIds, playNext),
    append: (videoIds) => Array.isArray(videoIds) && videoIds.length > 0 && enqueue(videoIds, false),
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
  const postUnavailable = (videoId) => {
    if (!videoId || videoId === lastUnavailable) return;
    lastUnavailable = videoId;
    post({ type: 'error', kind: 'unavailable', videoId });
  };

  // The page may already have rewritten location by the time this script runs; the navigation entry keeps the URL that was loaded.
  const loadedURL = new URL(performance.getEntriesByType('navigation')[0]?.name ?? location.href);
  const requestedVideoId = loadedURL.pathname === '/watch' ? loadedURL.searchParams.get('v') : null;
  let requestSettled = !requestedVideoId;

  const postSong = () => {
    if (adShowing) return;
    const response = player()?.getPlayerResponse?.();
    const status = response?.playabilityStatus?.status;
    if (status && status !== 'OK') {
      postUnavailable(response.videoDetails?.videoId ?? new URL(location.href).searchParams.get('v'));
      return;
    }
    if (!response?.videoDetails) return;
    if (location.pathname === '/watch') requestSettled = true;
    lastUnavailable = null;
    post({ type: 'song', videoDetails: response.videoDetails, microformat: response.microformat });
  };

  // A missing video id reports no playability error: the page drops back to the home screen and keeps whatever it played before.
  const checkRequestDropped = () => {
    if (requestSettled) return true;
    if (location.pathname === '/watch') return false;
    requestSettled = true;
    postUnavailable(requestedVideoId);
    return true;
  };

  const postVolume = () => {
    const p = player();
    if (typeof p?.getVolume === 'function') post({ type: 'volume', volume: p.getVolume(), muted: p.isMuted() });
  };

  let likeElement = null;
  // During an ad the page's video id is the ad's, which would tag the status with the wrong track.
  const postLike = () => {
    if (adShowing) return;
    const status = likeElement?.getAttribute('like-status');
    if (status) post({ type: 'like', status, videoId: player()?.getVideoData?.()?.video_id });
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
      // A queue longer than MAX_ROWS is reported as a window around the current row, with its page index as offset.
      const selected = items.findIndex((row) => unwrap(row)?.selected || row?.playlistPanelVideoWrapperRenderer?.selected);
      const offset = Math.max(0, Math.min(selected - MAX_ROWS / 2, items.length - MAX_ROWS));
      const projected = items.slice(offset, offset + MAX_ROWS).map((row) => {
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
      const json = JSON.stringify([offset, projected]);
      if (!projected.includes(null) && json !== lastQueue) {
        lastQueue = json;
        post({ type: 'queue', items: projected, offset });
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
    if (!showing) {
      postSong();
      postLike();
    }
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
    v.addEventListener('seeked', () => post({ type: 'playback', paused: v.paused, time: v.currentTime }));
    v.addEventListener('volumechange', postVolume);
    v.addEventListener('waiting', () => post({ type: 'buffering', buffering: true }));
    for (const name of ['playing', 'pause', 'seeked']) v.addEventListener(name, () => post({ type: 'buffering', buffering: false }));
    new MutationObserver(watchAd).observe(p, { attributes: true, attributeFilter: ['class'] });
    post({ type: 'ready' });
    watchAd();
    postSong();
    postVolume();
    watchLike();
    // The video may have started before the bridge attached, so its 'play' event was already missed.
    post({ type: 'playback', paused: v.paused, time: v.currentTime });
    const requestDeadline = Date.now() + 15000;
    const requestWait = setInterval(() => {
      if (checkRequestDropped() || Date.now() > requestDeadline) clearInterval(requestWait);
    }, 250);
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
