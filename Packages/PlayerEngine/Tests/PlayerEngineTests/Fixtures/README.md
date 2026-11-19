# PlayerEngine fixtures

`player-response.json` has the shape of the `videoDetails` and `microformat` subset of a guest `POST https://music.youtube.com/youtubei/v1/player` response (client `WEB_REMIX`, `hl=en`, `gl=US`, no cookies), which is also what `bridge.js` posts from `getPlayerResponse()`.

It was written by hand to that shape, not captured: only the fields `SongInfo.parse` reads are present, and the IDs and the artwork URL are illustrative. `responseContext`, `streamingData`, `playbackTracking` and `attestation` are deliberately absent because they hold the IP, `cpn` and `visitorData`. Replace it with a real capture trimmed the same way when one is taken (MC-4).
