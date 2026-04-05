import { Bridge } from './src/bridge.js';

const bridge = new Bridge(3200);
const port = await bridge.start();
console.error(`[test] Bridge listening on port ${port}`);

bridge.on('studio-connected', (info) => {
  console.error(`[test] Studio connected: ${info.studioId} (${info.placeName ?? 'unknown'})`);
});

bridge.on('studio-disconnected', (info) => {
  console.error(`[test] Studio disconnected: ${info.studioId}`);
});

// Poll health every 5s
setInterval(async () => {
  try {
    const res = await fetch(`http://127.0.0.1:${port}/health`);
    const data = await res.json();
    console.error(`[health] connected=${data.connected}, studios=${data.studios.length}`);
  } catch {}
}, 5000);
