// Attic launch video (16:9, 54 s) for X. Every product shot is a real recording of Attic running on a
// made-up demo library (branding/demo); the backdrop, captions, cold open, montage and end card are composed here.
import React from "react";
import { AbsoluteFill, Img, Sequence, interpolate, spring, staticFile, useCurrentFrame, useVideoConfig } from "remotion";
import { Audio, Video } from "@remotion/media";
import { C, CLAMP, E, FPS, H, INTER, JAKARTA, W, prog, sec } from "./theme";
import { FEATURES, Feature, SFX, T, TOTAL } from "./timeline";

// ── Backdrop: warm glows drifting on near-black ─────────────────────────────────────────────────────
const Backdrop: React.FC = () => {
  const f = useCurrentFrame();
  const blob = (x: number, y: number, r: number, color: string, speed: number, phase: number) => {
    const dx = Math.sin(f / (FPS * speed) + phase) * 90;
    const dy = Math.cos(f / (FPS * speed * 1.3) + phase) * 60;
    return (
      <div style={{ position: "absolute", left: x + dx - r, top: y + dy - r, width: r * 2, height: r * 2, borderRadius: "50%",
        background: `radial-gradient(circle, ${color} 0%, transparent 68%)`, opacity: 0.55, filter: "blur(40px)" }} />
    );
  };
  return (
    <AbsoluteFill style={{ backgroundColor: C.bg, overflow: "hidden" }}>
      {blob(260, 180, 620, "rgba(255,192,77,0.45)", 5, 0)}
      {blob(1650, 900, 760, "rgba(238,68,114,0.42)", 6, 1.7)}
      {blob(1250, 160, 520, "rgba(255,126,69,0.35)", 4.4, 3.1)}
      <AbsoluteFill style={{ background: "radial-gradient(ellipse at center, transparent 40%, rgba(0,0,0,0.55) 100%)" }} />
    </AbsoluteFill>
  );
};

// ── Cold open: "Your Mac is almost full." ─────────────────────────────────────────────────────────────
const ColdOpen: React.FC = () => {
  const f = useCurrentFrame();
  const fill = interpolate(f, [sec(0.2), sec(3.0)], [0.62, 0.975], { ...CLAMP, easing: E.inOut });
  const freeGB = interpolate(f, [sec(0.2), sec(3.0)], [187, 4.2], { ...CLAMP, easing: E.inOut });
  const red = prog(f, sec(2.0), sec(2.8));
  const out = prog(f, sec(3.55), sec(4.0), E.in);
  const words = ["Your", "Mac", "is", "almost", "full."];
  const barColor = `rgb(${Math.round(255)}, ${Math.round(interpolate(red, [0, 1], [126, 69]))}, ${Math.round(interpolate(red, [0, 1], [69, 58]))})`;
  return (
    <AbsoluteFill style={{ alignItems: "center", justifyContent: "center", opacity: 1 - out, transform: `scale(${1 + out * 0.12})`, filter: out ? `blur(${out * 12}px)` : undefined }}>
      <div style={{ fontFamily: JAKARTA, fontWeight: 800, fontSize: 124, letterSpacing: "-0.04em", color: C.ink, display: "flex", gap: 30 }}>
        {words.map((w, i) => {
          const p = prog(f, sec(0.15 + i * 0.16), sec(0.5 + i * 0.16));
          return <span key={i} style={{ opacity: p, transform: `translateY(${(1 - p) * 40}px)`, color: i === 4 ? `rgb(255,${Math.round(255 - red * 186)},${Math.round(255 - red * 197)})` : C.ink }}>{w}</span>;
        })}
      </div>
      <div style={{ marginTop: 70, width: 1100, opacity: prog(f, sec(0.6), sec(1.0)) }}>
        <div style={{ display: "flex", justifyContent: "space-between", fontFamily: INTER, fontSize: 30, color: C.dim, marginBottom: 16 }}>
          <span>Macintosh HD</span>
          <span style={{ color: red > 0.5 ? "#FF8A80" : C.dim, fontWeight: 600 }}>{freeGB.toFixed(freeGB < 10 ? 1 : 0)} GB free</span>
        </div>
        <div style={{ height: 30, borderRadius: 15, background: "rgba(255,255,255,0.10)", overflow: "hidden" }}>
          <div style={{ width: `${fill * 100}%`, height: "100%", borderRadius: 15, background: `linear-gradient(90deg, ${C.amber}, ${barColor})`,
            boxShadow: red > 0.3 ? `0 0 ${30 * red}px rgba(255,69,58,${0.6 * red})` : undefined }} />
        </div>
      </div>
    </AbsoluteFill>
  );
};

// ── Reveal: icon + wordmark ────────────────────────────────────────────────────────────────────────
const Reveal: React.FC = () => {
  const f = useCurrentFrame();
  const { fps } = useVideoConfig();
  const s = spring({ frame: f, fps, config: { damping: 12, stiffness: 140, mass: 0.9 } });
  const ring = prog(f, 0, sec(0.9));
  const word = prog(f, sec(0.35), sec(0.85));
  const tag = prog(f, sec(0.8), sec(1.3));
  const out = prog(f, sec(2.6), sec(3.0), E.in);
  return (
    <AbsoluteFill style={{ alignItems: "center", justifyContent: "center", opacity: 1 - out, transform: `scale(${1 - out * 0.08})` }}>
      <div style={{ position: "absolute", width: 300 + ring * 900, height: 300 + ring * 900, borderRadius: "50%",
        border: `3px solid rgba(255,170,110,${0.55 * (1 - ring)})` }} />
      <div style={{ display: "flex", alignItems: "center", gap: 56 }}>
        <Img src={staticFile("attic-icon.png")} style={{ width: 300, height: 300, transform: `scale(${0.4 + s * 0.6}) rotate(${(1 - s) * -12}deg)`,
          filter: "drop-shadow(0 30px 60px rgba(238,68,114,0.45))" }} />
        <div>
          <div style={{ fontFamily: JAKARTA, fontWeight: 800, fontSize: 190, letterSpacing: "-0.05em", color: C.ink, lineHeight: 0.95,
            opacity: word, transform: `translateX(${(1 - word) * -30}px)` }}>Attic</div>
          <div style={{ fontFamily: INTER, fontWeight: 500, fontSize: 44, color: C.dim, marginTop: 18, opacity: tag, transform: `translateY(${(1 - tag) * 16}px)` }}>
            Free up your Mac. Keep everything.
          </div>
        </div>
      </div>
    </AbsoluteFill>
  );
};

// ── A feature: caption on the left, the real recording in a window on the right ────────────────────────
const segments = (feat: Feature) => {
  const list = Array.isArray(feat.clip) ? feat.clip : [feat.clip];
  let at = 0;
  return list.map((clip) => {
    const len = Math.round(((clip.to - clip.from) / clip.rate) * FPS);
    const s = { clip, at, len };
    at += len;
    return s;
  });
};
const WIN_W = 1180;
const WIN_H = Math.round((WIN_W * 1600) / 2560);

const FeatureScene: React.FC<{ feat: Feature; dur: number }> = ({ feat, dur }) => {
  const f = useCurrentFrame();
  const enter = prog(f, 0, sec(0.55), E.outQuint);
  const exit = prog(f, dur - sec(0.35), dur, E.in);
  const lines = feat.title.split("\n");
  const zoom = interpolate(f, [0, dur], [1, 1.035]);
  return (
    <AbsoluteFill style={{ opacity: 1 - exit }}>
      <div style={{ position: "absolute", left: 104, top: 0, bottom: 0, width: 600, display: "flex", flexDirection: "column", justifyContent: "center" }}>
        <div style={{ alignSelf: "flex-start", display: "flex", alignItems: "center", gap: 12, padding: "10px 20px", borderRadius: 999,
          background: "rgba(255,126,69,0.14)", border: "1px solid rgba(255,160,110,0.45)", fontFamily: INTER, fontWeight: 600, fontSize: 26,
          color: "#FFB48A", opacity: prog(f, sec(0.1), sec(0.4)), transform: `translateY(${(1 - prog(f, sec(0.1), sec(0.4))) * 14}px)` }}>
          <span style={{ fontSize: 26 }}>{feat.icon}</span>{feat.kicker}
        </div>
        <div style={{ marginTop: 28 }}>
          {lines.map((l, i) => {
            const p = prog(f, sec(0.18 + i * 0.12), sec(0.6 + i * 0.12));
            return (
              <div key={i} style={{ fontFamily: JAKARTA, fontWeight: 800, fontSize: lines.join("").length > 40 ? 64 : 78, lineHeight: 1.04,
                letterSpacing: "-0.035em", color: C.ink, opacity: p, transform: `translateY(${(1 - p) * 30}px)` }}>{l}</div>
            );
          })}
        </div>
        <div style={{ marginTop: 26, fontFamily: INTER, fontWeight: 500, fontSize: 30, lineHeight: 1.35, color: C.dim, maxWidth: 540,
          opacity: prog(f, sec(0.5), sec(0.9)) }}>{feat.sub}</div>
      </div>
      <div style={{ position: "absolute", left: 690, top: (H - WIN_H) / 2, width: WIN_W, height: WIN_H, borderRadius: 22, overflow: "hidden",
        boxShadow: "0 50px 120px rgba(0,0,0,0.6), 0 0 0 1px rgba(255,255,255,0.09)",
        opacity: enter, transform: `translateX(${(1 - enter) * 160}px) perspective(2000px) rotateY(${(1 - enter) * -10}deg) scale(${zoom})`,
        transformOrigin: "left center", background: "#1d1d1f" }}>
        <div style={{ position: "absolute", inset: 0, transformOrigin: `${feat.focus?.x ?? 50}% ${feat.focus?.y ?? 50}%`,
          transform: `scale(${interpolate(f, [sec(0.7), sec(2.2)], [1, feat.focus?.z ?? 1], { ...CLAMP, easing: E.inOut })})` }}>
        {segments(feat).map((seg, i) => (
          <Sequence key={i} from={seg.at} durationInFrames={i === segments(feat).length - 1 ? dur - seg.at : seg.len} layout="none">
            <Video src={staticFile(seg.clip.file)} muted trimBefore={Math.round(seg.clip.from * FPS)} trimAfter={Math.round(seg.clip.to * FPS)}
              playbackRate={seg.clip.rate} style={{ position: "absolute", inset: 0, width: "100%", height: "100%", objectFit: "cover" }} />
          </Sequence>
        ))}
        </div>
        {segments(feat).map((seg, i) => seg.clip.tag ? (
          <Sequence key={`tag${i}`} from={seg.at} durationInFrames={seg.len} layout="none">
            <div style={{ position: "absolute", right: 18, bottom: 18, padding: "10px 18px", borderRadius: 999, background: "rgba(0,0,0,0.65)",
              fontFamily: INTER, fontWeight: 600, fontSize: 24, color: "rgba(255,255,255,0.92)" }}>▸▸ {seg.clip.tag}</div>
          </Sequence>
        ) : null)}
      </div>
    </AbsoluteFill>
  );
};

// ── Montage: the whole app at a glance ────────────────────────────────────────────────────────────────
const SHOTS = ["01-home", "02-search", "05-cleanup", "07-duplicates", "08-deep-clean", "09-memory", "13-cloud", "15-quick-search", "04-downloaded-from"];
const Montage: React.FC<{ dur: number }> = ({ dur }) => {
  const f = useCurrentFrame();
  const enter = prog(f, 0, sec(0.5));
  const exit = prog(f, dur - sec(0.4), dur, E.in);
  const drift = interpolate(f, [0, dur], [0, -120]);
  const chips = ["Native SwiftUI", "Open source · MIT", "No account", "Cloudflare R2 + iCloud Drive"];
  return (
    <AbsoluteFill style={{ opacity: 1 - exit }}>
      <AbsoluteFill style={{ transform: `perspective(1800px) rotateX(24deg) rotateZ(-9deg) translateY(${drift}px) scale(1.25)`, opacity: enter * 0.9 }}>
        <div style={{ position: "absolute", left: -80, top: -60, display: "grid", gridTemplateColumns: "repeat(3, 700px)", gap: 34 }}>
          {SHOTS.map((s, i) => {
            const p = prog(f, sec(0.05 * i), sec(0.4 + 0.05 * i));
            return <Img key={s} src={staticFile(`shots/${s}.jpg`)} style={{ width: 700, borderRadius: 14, opacity: p,
              transform: `translateY(${(1 - p) * 60}px)`, boxShadow: "0 30px 60px rgba(0,0,0,0.55)" }} />;
          })}
        </div>
      </AbsoluteFill>
      <AbsoluteFill style={{ background: "linear-gradient(180deg, rgba(13,9,12,0.15) 0%, rgba(13,9,12,0.85) 70%)" }} />
      <AbsoluteFill style={{ alignItems: "center", justifyContent: "flex-end", paddingBottom: 130 }}>
        <div style={{ fontFamily: JAKARTA, fontWeight: 800, fontSize: 96, letterSpacing: "-0.04em", color: C.ink, opacity: prog(f, sec(0.3), sec(0.8)) }}>
          One app. Gigabytes back.
        </div>
        <div style={{ display: "flex", gap: 18, marginTop: 34 }}>
          {chips.map((c, i) => {
            const p = prog(f, sec(0.7 + i * 0.12), sec(1.05 + i * 0.12), E.back);
            return <div key={c} style={{ padding: "14px 26px", borderRadius: 999, background: "rgba(255,255,255,0.08)", border: "1px solid rgba(255,255,255,0.16)",
              fontFamily: INTER, fontWeight: 600, fontSize: 28, color: C.ink, opacity: p, transform: `scale(${0.85 + p * 0.15})` }}>{c}</div>;
          })}
        </div>
      </AbsoluteFill>
    </AbsoluteFill>
  );
};

// ── End card ──────────────────────────────────────────────────────────────────────────────────────────
const EndCard: React.FC = () => {
  const f = useCurrentFrame();
  const { fps } = useVideoConfig();
  const s = spring({ frame: f, fps, config: { damping: 14, stiffness: 120 } });
  const a = prog(f, sec(0.3), sec(0.8));
  const b = prog(f, sec(0.7), sec(1.2));
  const c = prog(f, sec(1.1), sec(1.6), E.back);
  return (
    <AbsoluteFill style={{ alignItems: "center", justifyContent: "center" }}>
      <Img src={staticFile("attic-icon.png")} style={{ width: 230, height: 230, transform: `scale(${0.5 + s * 0.5})`, filter: "drop-shadow(0 26px 50px rgba(238,68,114,0.45))" }} />
      <div style={{ fontFamily: JAKARTA, fontWeight: 800, fontSize: 150, letterSpacing: "-0.05em", color: C.ink, marginTop: 6, opacity: a, transform: `translateY(${(1 - a) * 24}px)` }}>Attic</div>
      <div style={{ fontFamily: INTER, fontWeight: 500, fontSize: 42, color: C.dim, marginTop: 4, opacity: b }}>Free up your Mac. Keep everything.</div>
      <div style={{ marginTop: 48, display: "flex", alignItems: "center", gap: 16, padding: "18px 34px", borderRadius: 999,
        background: "linear-gradient(90deg, rgba(255,192,77,0.22), rgba(238,68,114,0.22))", border: "1px solid rgba(255,180,130,0.5)",
        fontFamily: INTER, fontWeight: 600, fontSize: 36, color: C.ink, opacity: c, transform: `scale(${0.9 + c * 0.1})` }}>
        <svg width="34" height="34" viewBox="0 0 16 16" fill="white"><path d="M8 0C3.58 0 0 3.58 0 8c0 3.54 2.29 6.53 5.47 7.59.4.07.55-.17.55-.38 0-.19-.01-.82-.01-1.49-2.01.37-2.53-.49-2.69-.94-.09-.23-.48-.94-.82-1.13-.28-.15-.68-.52-.01-.53.63-.01 1.08.58 1.23.82.72 1.21 1.87.87 2.33.66.07-.52.28-.87.51-1.07-1.78-.2-3.64-.89-3.64-3.95 0-.87.31-1.59.82-2.15-.08-.2-.36-1.02.08-2.12 0 0 .67-.21 2.2.82.64-.18 1.32-.27 2-.27.68 0 1.36.09 2 .27 1.53-1.04 2.2-.82 2.2-.82.44 1.1.16 1.92.08 2.12.51.56.82 1.27.82 2.15 0 3.07-1.87 3.75-3.65 3.95.29.25.54.73.54 1.48 0 1.07-.01 1.93-.01 2.2 0 .21.15.46.55.38A8.013 8.013 0 0016 8c0-4.42-3.58-8-8-8z"/></svg>
        github.com/piyushgit011/attic-mac
      </div>
      <div style={{ fontFamily: INTER, fontWeight: 500, fontSize: 28, color: "rgba(255,255,255,0.5)", marginTop: 26, opacity: c }}>
        Free &amp; open source · macOS 14 or later
      </div>
    </AbsoluteFill>
  );
};

export const AtticLaunch: React.FC = () => {
  const range = (a: number, b: number) => ({ from: sec(a), durationInFrames: sec(b - a) });
  return (
    <AbsoluteFill style={{ backgroundColor: C.bg }}>
      <Backdrop />
      <Sequence {...range(T.coldOpen[0], T.coldOpen[1])}><ColdOpen /></Sequence>
      <Sequence {...range(T.reveal[0], T.reveal[1])}><Reveal /></Sequence>
      {FEATURES.map((feat) => (
        <Sequence key={feat.start} {...range(feat.start, feat.end)} premountFor={sec(1)}>
          <FeatureScene feat={feat} dur={sec(feat.end - feat.start)} />
        </Sequence>
      ))}
      <Sequence {...range(T.montage[0], T.montage[1])}><Montage dur={sec(T.montage[1] - T.montage[0])} /></Sequence>
      <Sequence {...range(T.end[0], T.end[1])}><EndCard /></Sequence>
      <Audio src={staticFile("music/attic-launch.mp3")} volume={(f) => interpolate(f, [0, 8, TOTAL - sec(1.6), TOTAL], [0, 0.85, 0.85, 0], CLAMP)} />
      {SFX.map((s, i) => (
        <Sequence key={i} from={sec(s.at)} durationInFrames={sec(3)}>
          <Audio src={staticFile(`sfx/${s.name}.mp3`)} volume={s.volume ?? 0.5} />
        </Sequence>
      ))}
    </AbsoluteFill>
  );
};

export { W, H };
