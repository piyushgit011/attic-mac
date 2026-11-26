// Composes the film's score with ElevenLabs: sections timed to src/film.ts, 90 BPM so montage cuts land on the beat.
//   npm run film-audio      (reads ELEVENLABS_API_KEY from the Versely backend .env)
// Skips the file if it already exists.
import { existsSync, mkdirSync, writeFileSync } from "node:fs";
import { dirname, join } from "node:path";
import { fileURLToPath } from "node:url";

const ROOT = join(dirname(fileURLToPath(import.meta.url)), "..");
const KEY = process.env.ELEVENLABS_API_KEY;
const BPM = "90 BPM";
const out = join(ROOT, "public", "music", "attic-film.mp3");
const plan = {
  positive_global_styles: ["cinematic product film score", "premium technology keynote", "felt piano motif", "warm analog synth pulse",
    "wide strings", "uplifting and calm", "modern minimal", BPM, "instrumental"],
  negative_global_styles: ["vocals", "lyrics", "epic trailer drums", "dubstep", "aggressive", "lo-fi hiss", "guitar solo", "cheesy"],
  sections: [
    { section_name: "Open", positive_local_styles: ["solo felt piano", "a few sparse notes", "intimate", "airy reverb", "quiet"], negative_local_styles: ["drums", "bass"], duration_ms: 4500, lines: [] },
    { section_name: "Reveal", positive_local_styles: ["soft string swell", "reverse cymbal swell", "a warm low chord blooms", "anticipation"], negative_local_styles: ["drums"], duration_ms: 4500, lines: [] },
    { section_name: "Pulse", positive_local_styles: ["steady eighth-note synth pulse", "light electronic kick and soft claps", "piano motif returns", "optimistic", "building gently", BPM], negative_local_styles: ["heavy bass drop"], duration_ms: 19000, lines: [] },
    { section_name: "Lift", positive_local_styles: ["fuller drums", "wide strings join", "confident and uplifting", "bright plucks", BPM], negative_local_styles: ["breakdown", "distortion"], duration_ms: 18000, lines: [] },
    { section_name: "Night", positive_local_styles: ["drums drop out", "deep warm pads", "piano motif alone", "calm and wondrous"], negative_local_styles: ["percussion"], duration_ms: 6000, lines: [] },
    { section_name: "Montage", positive_local_styles: ["punchy hit on every beat", "energetic build", "rising strings", BPM], negative_local_styles: ["slow"], duration_ms: 4000, lines: [] },
    { section_name: "Finale", positive_local_styles: ["big warm final chord", "strings sustain", "gentle piano resolution", "soft fade out", "resolved"], negative_local_styles: ["drums continuing", "abrupt ending"], duration_ms: 10000, lines: [] },
  ],
};

if (existsSync(out)) {
  console.log("music: exists");
} else {
  if (!KEY) throw new Error("ELEVENLABS_API_KEY missing");
  console.log("music: composing…");
  const res = await fetch("https://api.elevenlabs.io/v1/music?output_format=mp3_44100_192", {
    method: "POST",
    headers: { "xi-api-key": KEY, "Content-Type": "application/json", Accept: "audio/mpeg" },
    body: JSON.stringify({ model_id: "music_v1", composition_plan: plan }),
  });
  if (!res.ok) throw new Error(`${res.status} ${(await res.text()).slice(0, 300)}`);
  mkdirSync(dirname(out), { recursive: true });
  writeFileSync(out, Buffer.from(await res.arrayBuffer()));
  console.log("  wrote public/music/attic-film.mp3");
}
