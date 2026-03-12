let ctx;
let muted = false;

function tone(freq, duration = 0.08, type = "triangle", volume = 0.04) {
  if (muted) return;
  if (!ctx) ctx = new (window.AudioContext || window.webkitAudioContext)();
  const osc = ctx.createOscillator();
  const gain = ctx.createGain();
  osc.type = type;
  osc.frequency.value = freq;
  gain.gain.value = volume;
  osc.connect(gain).connect(ctx.destination);
  osc.start();
  gain.gain.exponentialRampToValueAtTime(0.0001, ctx.currentTime + duration);
  osc.stop(ctx.currentTime + duration);
}

export const audio = {
  click: () => tone(420, 0.05, "square", 0.02),
  purchase: () => { tone(520, 0.06); tone(700, 0.08); },
  milestone: () => { tone(360, 0.07, "sine", 0.03); tone(560, 0.1, "triangle", 0.03); tone(820, 0.12, "sine", 0.025); },
  event: () => tone(260, 0.15, "sawtooth", 0.03),
  setMuted: (v) => { muted = v; },
  isMuted: () => muted
};
