export const clamp = (v, min, max) => Math.max(min, Math.min(max, v));

export function format(num) {
  if (!Number.isFinite(num)) return "∞";
  if (Math.abs(num) < 1000) return num.toFixed(num < 10 ? 2 : 1);
  const suffixes = ["K", "M", "B", "T", "Qa", "Qi", "Sx", "Sp", "Oc", "No"];
  let idx = -1;
  let n = num;
  while (Math.abs(n) >= 1000 && idx < suffixes.length - 1) {
    n /= 1000;
    idx += 1;
  }
  return `${n.toFixed(2)}${suffixes[idx]}`;
}

export const deepCopy = (obj) => JSON.parse(JSON.stringify(obj));
export const now = () => Date.now();
export const rand = (min, max) => Math.random() * (max - min) + min;
export const pick = (arr) => arr[Math.floor(Math.random() * arr.length)];
