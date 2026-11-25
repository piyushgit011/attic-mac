// Composes the launch video's music with ElevenLabs (sections timed to src/timeline.ts) and copies the SFX kit.
//   npm run audio        (reads ELEVENLABS_API_KEY from the Versely backend .env)
// Skips files that already exist, so a re-run only pays for what's missing.
import { copyFileSync, existsSync, mkdirSync, writeFileSync } from "node:fs";
import { dirname, join } from "node:path";
import { fileURLToPath } from "node:url";

const ROOT = join(dirname(fileURLToPath(import.meta.url)), "..");
const KEY = process.env.ELEVENLABS_API_KEY;
const BPM = "112 BPM";
const MUSIC = "music/attic-launch.mp3";
const plan = {
  positive_global_styles: ["modern minimal electronic", "premium tech product launch", "warm synth plucks", "clean punchy production", BPM, "instrumental", "optimistic"],
  negative_global_styles: ["vocals", "lyrics", "aggressive", "dubstep", "lo-fi hiss", "acoustic guitar"],
  sections: [
    { section_name: "Tension", positive_local_styles: ["soft clock-like ticking", "low sub drone", "muted", "anticipation", BPM], negative_local_styles: ["drums", "melody"], duration_ms: 4000, lines: [] },
    { section_name: "Reveal", positive_local_styles: ["warm synth swell", "bright pluck hit on the downbeat", "airy shimmer", BPM], negative_local_styles: ["heavy bass"], duration_ms: 3000, lines: [] },
    { section_name: "Groove", positive_local_styles: ["light four-on-the-floor kick", "tight claps", "warm plucked synth melody", "bouncy bassline", "confident and friendly", BPM], negative_local_styles: ["huge drop", "distortion"], duration_ms: 32000, lines: [] },
    { section_name: "Lift", positive_local_styles: ["added arpeggio", "wide pads", "uplifting lift", "slightly fuller", BPM], negative_local_styles: ["breakdown"], duration_ms: 9000, lines: [] },
    { section_name: "Outro", positive_local_styles: ["final pluck hit", "sustained warm pad", "gentle fade out", "resolved"], negative_local_styles: ["drums continuing"], duration_ms: 6000, lines: [] },
  ],
};

const out = join(ROOT, "public", MUSIC);
if (!existsSync(out)) {
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
  console.log(`  wrote ${MUSIC}`);
} else console.log("music: exists");

// SFX generated earlier for the Versely promo
const SFX_SRC = join(ROOT, "../../versely/versely-motion/public/sfx");
for (const name of ["whoosh", "click", "pop", "chime", "impact-soft", "typing", "shimmer", "tick", "swipe", "riser"]) {
  const dst = join(ROOT, "public/sfx", `${name}.mp3`);
  if (!existsSync(dst) && existsSync(join(SFX_SRC, `${name}.mp3`))) copyFileSync(join(SFX_SRC, `${name}.mp3`), dst);
}
console.log("sfx: ready");
