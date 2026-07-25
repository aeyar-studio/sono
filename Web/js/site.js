/* Sono landing page.
   No framework and no 3D. The only motion is the product explaining itself:
   the island cycling through its real states, and speech turning into text. */

const reduced = window.matchMedia('(prefers-reduced-motion: reduce)').matches;

/* Browsers restore the previous scroll offset on reload, so refreshing while you
   happened to be reading the pricing card reopened the page halfway down it.
   Deep links still work; only the automatic restore is suppressed. */
if ('scrollRestoration' in history) history.scrollRestoration = 'manual';
if (!location.hash) window.scrollTo(0, 0);

/* ─────────────────────────────────────────── reveal on scroll */
const io = new IntersectionObserver((entries) => {
  entries.forEach((entry, i) => {
    if (entry.isIntersecting) {
      // Slight stagger so a row of cards arrives as a sequence, not a slab.
      setTimeout(() => entry.target.classList.add('in'), i * 70);
    } else if (entry.boundingClientRect.bottom < 0) {
      // Already above the viewport. Opening /#faq jumps straight past these,
      // so they never intersect and would stay invisible for good.
      entry.target.classList.add('in');
    } else {
      return; // still below the fold, keep watching
    }
    io.unobserve(entry.target);
  });
}, { rootMargin: '0px 0px -12% 0px', threshold: 0.08 });
document.querySelectorAll('.reveal').forEach((el) => io.observe(el));

/* ─────────────────────────────────────────── nav hairline on scroll */
const nav = document.querySelector('.nav');
const onScroll = () => nav.classList.toggle('stuck', window.scrollY > 8);
addEventListener('scroll', onScroll, { passive: true });
onScroll();

/* ─────────────────────────────────────────── hero glow drifts toward the pointer */
if (!reduced) {
  const glow = document.querySelector('.hero-glow');
  addEventListener('pointermove', (e) => {
    const dx = (e.clientX / innerWidth - 0.5) * 46;
    const dy = (e.clientY / innerHeight - 0.5) * 26;
    glow.style.transform = `translate(calc(-50% + ${dx}px), ${dy}px)`;
  }, { passive: true });
}

/* ─────────────────────────────────────────── scene furniture
   Avatars are drawn, not photographed. Stock faces of real people are not ours
   to ship, and a flat silhouette on a colour is what an app shows anyway when
   someone has not uploaded a picture. */
function avatar(bg, cls) {
  return `<svg class="av ${cls || ''}" viewBox="0 0 24 24" aria-hidden="true">
    <rect width="24" height="24" rx="5.5" fill="${bg}" />
    <circle cx="12" cy="9.4" r="3.9" fill="rgba(255,255,255,0.92)" />
    <path d="M4 24c.8-4.5 4-7.1 8-7.1s7.2 2.6 8 7.1z" fill="rgba(255,255,255,0.92)" />
  </svg>`;
}

/** Slack's left rail. Filled glyphs so they read at 15px. */
const RAIL = {
  Home: 'M12 3 2.6 10.9h2.7v9.6h5.1v-5.9h3.2v5.9h5.1v-9.6h2.7z',
  DMs: 'M3.6 4.6h16.8a1 1 0 0 1 1 1v8.6a1 1 0 0 1-1 1H9.7L5.2 19.4v-4.2H3.6a1 1 0 0 1-1-1V5.6a1 1 0 0 1 1-1z',
  Activity: 'M12 2.4A5.6 5.6 0 0 0 6.4 8v3.6L4 15.2h16l-2.4-3.6V8A5.6 5.6 0 0 0 12 2.4zM9.4 16.8a2.6 2.6 0 0 0 5.2 0z',
  Later: 'M12 2.8a9.2 9.2 0 1 0 0 18.4 9.2 9.2 0 0 0 0-18.4zm0 2.2a7 7 0 1 1 0 14 7 7 0 0 1 0-14zm-1 2.6v5.5l4.3 2.5 1-1.7-3.3-1.9V7.6z',
};
const rail = (name, on) =>
  `<span class="sk-r${on ? ' on' : ''}"><svg viewBox="0 0 24 24" aria-hidden="true">
     <path d="${RAIL[name]}" /></svg>${name}</span>`;

/* Shortcut icons for the channel's installed apps. Named, and drawn as their own
   shapes: enough for a reader to recognise the row, no borrowed artwork. */
const APPS = [
  ['DocuSign', `<rect x="3" y="2.2" width="18" height="19.6" rx="2.6" fill="#d4b13c"/>
    <path d="M7.2 12.4l3.3 3.3 6.4-6.6" fill="none" stroke="#fff" stroke-width="2.4"
      stroke-linecap="round" stroke-linejoin="round"/>`],
  ['Google Drive', `<path d="M12 3.5 2 20.5 12 14.8z" fill="#1e88e5"/>
    <path d="M12 3.5 22 20.5 12 14.8z" fill="#f9bc2c"/>
    <path d="M2 20.5h20L12 14.8z" fill="#34a853"/>`],
  ['Zoom', `<rect x="2" y="2" width="20" height="20" rx="5.5" fill="#2d8cff"/>
    <path d="M6.4 9h6.1a1.1 1.1 0 0 1 1.1 1.1v3.8a1.1 1.1 0 0 1-1.1 1.1H6.4a1.1 1.1 0 0 1-1.1-1.1v-3.8A1.1 1.1 0 0 1 6.4 9zm8.3 2.2 3.3-2v5.6l-3.3-2z" fill="#fff"/>`],
];
const appRow = APPS.map(([name, art]) =>
  `<span><svg viewBox="0 0 24 24" aria-hidden="true">${art}</svg>${name}</span>`).join('');

/* ─────────────────────────────────────────── the places Sono lands
   One scene per app, each with copy someone would actually dictate there. */
const SCENES = [
  {
    tab: 'Slack',
    // bare: the aubergine top bar carries the traffic lights, so the generic
    // cream title bar would sit above Slack's own chrome and look wrong.
    bare: true,
    text: 'Thursday works better for me. I will push the build tonight and drop the release notes in this channel.',
    body: `<div class="sc sc-slack">
      <div class="sk-top">
        <span class="sk-dots"><i></i><i></i><i></i></span>
        <span class="sk-arrows">&#8249; &#8250;</span>
        <span class="sk-search">Search Acme Inc.</span>
      </div>
      <div class="sk-cols">
        <div class="sk-rail">
          <span class="sk-ws">A</span>
          ${rail('Home', true)}${rail('DMs')}${rail('Activity')}${rail('Later')}
        </div>
        <div class="sk-side">
          <p class="sk-name">Acme Inc.</p>
          <p class="sk-i">Threads</p>
          <p class="sk-i">Drafts &amp; Sent</p>
          <p class="sk-g">Channels</p>
          <p class="sk-i"># acct-mooncorp<b class="sk-b">1</b></p>
          <p class="sk-i on"># acct-midtech<b class="sk-b">2</b></p>
          <p class="sk-i"># quarterly-planning</p>
          <p class="sk-i"># support-triage</p>
          <p class="sk-g">Direct messages</p>
          <p class="sk-i sk-dm">${avatar('#7a9e6b', 'sm')}Sara Parras</p>
          <p class="sk-i sk-dm">${avatar('#b58a4a', 'sm')}Lisa Zhang</p>
        </div>
        <div class="sk-main">
          <div class="sk-head">
            <div>
              <p class="sk-ch"># acct-midtech <span>&#8964;</span></p>
              <p class="sk-desc">Account channel for the MidTech Corp Opportunity</p>
            </div>
            <p class="sk-mem">${avatar('#c2708a', 'xs')}${avatar('#4a7fb5', 'xs')}${avatar('#7a9e6b', 'xs')}<b>3</b></p>
          </div>
          <p class="sk-apps">${appRow}</p>
          <div class="sk-feed">
            <div class="sk-msg">${avatar('#c2708a')}<div>
              <p class="sk-who">Zoe Maxwell <span>10:56 AM</span></p>
              <p class="sk-txt">Heads-up before our meeting with Sam and Alexa, they are keen to
                see the product roadmap</p>
              <p class="sk-react"><span>&#128077; 1</span></p></div></div>
            <div class="sk-msg">${avatar('#4a7fb5')}<div>
              <p class="sk-who">Matt Brewer <span>10:57 AM</span></p>
              <p class="sk-txt">Have they mentioned anything about a timeline for migration?</p>
              <p class="sk-react"><span>&#9989; 1</span><span>&#128064; 1</span>
                <em>2 replies</em></p></div></div>
          </div>
          <div class="sk-box">
            <p class="sk-tools"><b>B</b><i>I</i><s>S</s><u>&#8734;</u><span>&#8801;</span><span>&#8942;</span></p>
            <p class="typed" data-typed></p>
            <p class="sk-foot"><span>+</span><span>&#9658;</span><span>&#9786;</span><span>@</span>
              <span>Aa</span><em>&#10148;</em></p>
          </div>
        </div>
      </div>
    </div>`,
  },
  {
    tab: 'Claude Code',
    bare: true,
    text: 'Add a launch at login toggle to settings, wire it to the login items API, then run the tests and show me what breaks.',
    body: `<div class="sc sc-term">
      <span class="sk-dots tm-dots"><i></i><i></i><i></i></span>
      <div class="tm-hero">
        <!-- The Claude mark, from the asset you supplied. Used to name the app
             Sono works with, which is what the row of tabs is for. -->
        <svg class="tm-logo" viewBox="0 0 24 24" aria-hidden="true">
          <path fill-rule="nonzero" d="M4.709 15.955l4.72-2.647.08-.23-.08-.128H9.2l-.79-.048-2.698-.073-2.339-.097-2.266-.122-.571-.121L0 11.784l.055-.352.48-.321.686.06 1.52.103 2.278.158 1.652.097 2.449.255h.389l.055-.157-.134-.098-.103-.097-2.358-1.596-2.552-1.688-1.336-.972-.724-.491-.364-.462-.158-1.008.656-.722.881.06.225.061.893.686 1.908 1.476 2.491 1.833.365.304.145-.103.019-.073-.164-.274-1.355-2.446-1.446-2.49-.644-1.032-.17-.619a2.97 2.97 0 01-.104-.729L6.283.134 6.696 0l.996.134.42.364.62 1.414 1.002 2.229 1.555 3.03.456.898.243.832.091.255h.158V9.01l.128-1.706.237-2.095.23-2.695.08-.76.376-.91.747-.492.584.28.48.685-.067.444-.286 1.851-.559 2.903-.364 1.942h.212l.243-.242.985-1.306 1.652-2.064.73-.82.85-.904.547-.431h1.033l.76 1.129-.34 1.166-1.064 1.347-.881 1.142-1.264 1.7-.79 1.36.073.11.188-.02 2.856-.606 1.543-.28 1.841-.315.833.388.091.395-.328.807-1.969.486-2.309.462-3.439.813-.042.03.049.061 1.549.146.662.036h1.622l3.02.225.79.522.474.638-.079.485-1.215.62-1.64-.389-3.829-.91-1.312-.329h-.182v.11l1.093 1.068 2.006 1.81 2.509 2.33.127.578-.322.455-.34-.049-2.205-1.657-.851-.747-1.926-1.62h-.128v.17l.444.649 2.345 3.521.122 1.08-.17.353-.608.213-.668-.122-1.374-1.925-1.415-2.167-1.143-1.943-.14.08-.674 7.254-.316.37-.729.28-.607-.461-.322-.747.322-1.476.389-1.924.315-1.53.286-1.9.17-.632-.012-.042-.14.018-1.434 1.967-2.18 2.945-1.726 1.845-.414.164-.717-.37.067-.662.401-.589 2.388-3.036 1.44-1.882.93-1.086-.006-.158h-.055L4.132 18.56l-1.13.146-.487-.456.061-.746.231-.243 1.908-1.312-.006.006z" />
        </svg>
        <div>
          <p class="tm-name">Claude Code <span>v2.0.26</span></p>
          <p class="tm-meta">Opus 5 &middot; Claude Max</p>
          <p class="tm-meta">~/SaaS/Sono</p>
        </div>
      </div>
      <p class="tm-you">&gt; where is the trial counter stored?</p>
      <p class="tm-b"><em>&#9679;</em> In <span class="tm-path">Sources/Licensing.swift</span>, in the
        Keychain rather than UserDefaults, so clearing preferences cannot reset it.</p>
      <p class="tm-b"><em class="ok">&#9679;</em> <b>Read</b>(Sources/Licensing.swift)</p>
      <p class="tm-sub">&#9492; 214 lines</p>
      <div class="tm-input"><span class="tm-gt">&gt;</span> <span class="typed" data-typed></span></div>
      <p class="tm-hint">? for shortcuts</p>
    </div>`,
  },
  {
    tab: 'VS Code',
    text: 'Returns the cleaned transcript, or the original text when the model gives back something unusable.',
    bare: true,
    body: `<div class="sc sc-code">
      <div class="vs-side">
        <p class="vs-dots"><span class="sk-dots"><i></i><i></i><i></i></span></p>
        <p class="vs-h">EXPLORER</p>
        <p class="vs-f">&#9662; SONO</p>
        <p class="vs-f in1">&#9662; Sources</p>
        <p class="vs-f in2 on">Polisher.swift</p>
        <p class="vs-f in2">Island.swift</p>
        <p class="vs-f in2">Licensing.swift</p>
        <p class="vs-f in2">History.swift</p>
        <p class="vs-f in1">&#9656; Resources</p>
        <p class="vs-f in1">&#9656; Vendor</p>
        <p class="vs-f in1">project.yml</p>
      </div>
      <div class="vs-body">
        <p class="vs-tabs"><span class="on">Polisher.swift</span><span>Island.swift</span></p>
        <div class="vs-rows">
          <p><i>31</i><span class="dimmed">extension Polisher {</span></p>
          <p><i>32</i><span></span></p>
          <p><i>33</i><span class="cm">&nbsp;&nbsp;&nbsp;&nbsp;/// <span class="typed" data-typed></span></span></p>
          <p><i>34</i><span>&nbsp;&nbsp;&nbsp;&nbsp;<span class="kw">func</span> <span class="fn">polish</span>(<span class="pm">_ text</span>: String) <span class="kw">async</span> -&gt; String {</span></p>
          <p><i>35</i><span class="dimmed">&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;guard model.isAvailable else { return text }</span></p>
          <p><i>36</i><span class="dimmed">&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;let reply = await session.respond(to: prompt(text))</span></p>
          <p><i>37</i><span class="dimmed">&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;return sanitise(reply) ?? text</span></p>
          <p><i>38</i><span class="dimmed">&nbsp;&nbsp;&nbsp;&nbsp;}</span></p>
          <p><i>39</i><span class="dimmed">}</span></p>
        </div>
        <p class="vs-status"><span>main*</span><span>Swift</span><span>Ln 33, Col 8</span><span>Spaces: 4</span></p>
      </div>
    </div>`,
  },
  {
    tab: 'Mail',
    title: 'New Message',
    // The spoken list arriving as a real numbered list, which is the whole trick.
    // Said out loud this is one breathless sentence; it lands as three lines.
    text: 'Here is what is left before we ship:\n1. Finish the pricing page\n2. Record the demo video\n3. File the trademark',
    body: `<div class="sc sc-mail">
      <p class="ml-tools"><span>&#10148;</span><span>&#128206;</span><span>Aa</span><span>&#128522;</span></p>
      <p class="ml-f"><span>To</span> jonas@northwind.co</p>
      <p class="ml-f"><span>Cc</span></p>
      <p class="ml-f"><span>Subject</span> Launch checklist</p>
      <div class="ml-body">
        <p class="typed typed-pre" data-typed></p>
        <p class="ml-sig">Aneesha<br />Aeyar Studio</p>
      </div>
    </div>`,
  },
  {
    tab: 'GitHub',
    title: 'github.com',
    text: 'If I hold option for under a second the pill never leaves the transcribing state and nothing pastes. Only happens on an external microphone.',
    body: `<div class="sc sc-web">
      <p class="br-url"><span class="br-lock"></span>github.com/aeyar-studio/sono/issues/new</p>
      <div class="br-page">
        <p class="gh-repo">aeyar-studio / <b>sono</b></p>
        <p class="gh-nav"><span>Code</span><span class="on">Issues</span><span>Pull requests</span>
          <span>Actions</span><span>Settings</span></p>
        <p class="gh-lab">Add a title</p>
        <p class="gh-title">Island stays in transcribing state</p>
        <p class="gh-lab">Add a description</p>
        <div class="gh-box">
          <p class="gh-tools"><b>B</b><i>I</i><span>H</span><span>&lt;/&gt;</span><span>&#9776;</span><span>&#9745;</span></p>
          <p class="typed" data-typed></p>
        </div>
        <p class="gh-submit"><span>Submit new issue</span></p>
      </div>
    </div>`,
  },
];

/* ─────────────────────────────────────────── the island, cycling its real states
   Sequence mirrors the app exactly: idle, listening with a live waveform,
   transcribing, then the pasted confirmation. */
const island = document.getElementById('island');
const label = document.getElementById('island-label');
const scene = document.getElementById('scene');
const tabsEl = document.getElementById('scene-tabs');
const canvas = document.getElementById('wave');
const ctx = canvas.getContext('2d');

let typedOut = null;   // set per scene
let level = 0, targetLevel = 0;

function drawWave(t) {
  const dpr = devicePixelRatio || 1;
  if (canvas.width !== canvas.clientWidth * dpr) {
    canvas.width = canvas.clientWidth * dpr;
    canvas.height = canvas.clientHeight * dpr;
  }
  const { width: w, height: h } = canvas;
  ctx.clearRect(0, 0, w, h);
  ctx.lineWidth = 1.8 * dpr;
  ctx.lineCap = 'round';

  const mid = h / 2;
  const amp = mid * 0.86 * Math.max(0.06, level);
  const grad = ctx.createLinearGradient(0, 0, w, 0);
  grad.addColorStop(0, 'rgba(155, 126, 196, 0.55)');
  grad.addColorStop(0.5, '#ffffff');
  grad.addColorStop(1, 'rgba(155, 126, 196, 0.55)');
  ctx.strokeStyle = grad;

  ctx.beginPath();
  for (let x = 0; x <= w; x += 2) {
    const rel = x / w;
    // Two offset sines: the motion reads organic rather than metronomic.
    const taper = Math.sin(rel * Math.PI);
    const a = Math.sin(rel * Math.PI * 10 - t * 5.5);
    const b = Math.sin(rel * Math.PI * 6.5 - t * 3.4) * 0.45;
    const y = mid + (a + b) * amp * taper;
    x === 0 ? ctx.moveTo(x, y) : ctx.lineTo(x, y);
  }
  ctx.stroke();
}

function frame(ms) {
  const t = ms / 1000;
  // Attack fast, release slow, same as the app's meter.
  level += (targetLevel - level) * (targetLevel > level ? 0.14 : 0.05);
  if (island.classList.contains('listening')) drawWave(t);
  requestAnimationFrame(frame);
}

/* Sono pastes the finished text in one shot, so the page must too. A typewriter
   here would be advertising behaviour the app does not have. The only concession
   is a 180ms fade, without which the text blinks in and the eye misses it. */
function pasteText(text) {
  typedOut.textContent = text;
  typedOut.classList.remove('landed');
  void typedOut.offsetWidth;          // reflow, so the animation restarts
  typedOut.classList.add('landed');
}

const wait = (ms) => new Promise((r) => setTimeout(r, ms));

/** Paints one app's chrome and points the typewriter at its input. */
function mountScene(i) {
  const s = SCENES[i];
  const bar = s.bare ? '' : `<div class="fake-bar"><i></i><i></i><i></i>
    <span class="win-title">${s.title}</span></div>`;
  scene.innerHTML = bar + s.body;
  typedOut = scene.querySelector('[data-typed]');
  tabsEl.querySelectorAll('button').forEach((b, n) => {
    b.classList.toggle('on', n === i);
    b.setAttribute('aria-pressed', String(n === i));
  });
}

SCENES.forEach((s, i) => {
  const b = document.createElement('button');
  b.className = 'scene-tab';
  b.type = 'button';
  b.textContent = s.tab;
  b.addEventListener('click', () => (reduced ? still(i) : cycle(i)));
  tabsEl.appendChild(b);
});

// Not a button: there is no sixth scene behind it. It says the list is a sample,
// which is true, since Sono pastes anywhere you can type.
const more = document.createElement('span');
more.className = 'scene-more';
more.textContent = 'and more';
tabsEl.appendChild(more);

// Bumped by every cycle start, so a tab click abandons the loop already running
// instead of leaving two of them fighting over the same island.
let gen = 0;

async function cycle(start) {
  const g = ++gen;
  const fresh = (ms) => wait(ms).then(() => g === gen);

  for (let i = start; ; i = (i + 1) % SCENES.length) {
    // idle: the target app is on screen before anything is spoken
    island.className = 'island';
    label.textContent = 'hold ⌥';
    targetLevel = 0;
    mountScene(i);
    if (!(await fresh(1500))) return;

    // listening
    island.className = 'island listening';
    for (let n = 0; n < 16; n++) {
      targetLevel = 0.25 + Math.random() * 0.72;
      if (!(await fresh(150))) return;
    }

    // transcribing
    island.className = 'island thinking';
    label.textContent = 'transcribing';
    targetLevel = 0;
    if (!(await fresh(1000))) return;

    // pasted, and the whole thing lands in that app at once
    island.className = 'island done';
    label.textContent = 'pasted';
    pasteText(SCENES[i].text);
    if (!(await fresh(3400))) return;
  }
}

/** Reduced motion: the finished result, no animation. */
function still(i) {
  gen++;
  mountScene(i);
  island.className = 'island done';
  label.textContent = 'pasted';
  typedOut.textContent = SCENES[i].text;
}

if (reduced) {
  still(0);
} else {
  requestAnimationFrame(frame);
  cycle(0);
}

/* ─────────────────────────────────────────── the stream
   Two marquees on one path. Both loop by wrapping startOffset modulo the length
   of a single phrase: because the content repeats with exactly that period, the
   wrap is invisible, so there is no seam to hide and no clone to swap in. */
const STREAM_RAW = 'so I told the team the the new timeline should be ready by Friday, no, Monday, and um there has been a lot of back and forth honestly. ';
const STREAM_CLEAN = 'I told the team the new timeline should be ready by Monday. There has been a lot of back and forth. ';

function initStream() {
  const svg = document.querySelector('.stream-svg');
  const path = document.getElementById('stream-path');
  const raw = document.getElementById('stream-raw-tp');
  const clean = document.getElementById('stream-clean-tp');
  if (!svg || !path || !raw || !clean) return;

  const pathLen = path.getTotalLength();

  /** Fills a textPath with enough repeats to cover the path plus two phrases of
      lead-in, and returns one phrase's length in user units. */
  function fill(tp, phrase) {
    tp.textContent = phrase;
    const one = tp.getComputedTextLength();
    if (!one) return 0;                      // fonts not ready yet
    tp.textContent = phrase.repeat(Math.ceil((pathLen + one * 2) / one) + 1);
    return one;
  }

  const rawOne = fill(raw, STREAM_RAW);
  const cleanOne = fill(clean, STREAM_CLEAN);
  if (!rawOne || !cleanOne) return;

  // Start two phrases back so the leading edge is always off the left of frame.
  const place = (tp, one, travelled) =>
    tp.setAttribute('startOffset', -one * 2 + (travelled % one));

  // Place once up front. Without this the band renders at offset 0 until the
  // first frame arrives, which is wrong wherever frames are throttled or never
  // come at all: a background tab, a heavily loaded machine, reduced motion.
  place(raw, rawOne, 0);
  place(clean, cleanOne, 0);
  if (reduced) return;

  const SPEED = 128;         // user units per second
  let frame = null, t0 = null, base = 0, travelled = 0;

  const step = (ms) => {
    if (t0 === null) t0 = ms;
    travelled = base + ((ms - t0) / 1000) * SPEED;
    place(raw, rawOne, travelled);
    place(clean, cleanOne, travelled);
    frame = requestAnimationFrame(step);
  };

  // Text on a path relays out on every offset change, so do not pay for it while
  // the band is scrolled away. base carries the position so it resumes in place
  // instead of snapping back to the start.
  new IntersectionObserver((entries) => {
    entries.forEach((e) => {
      if (e.isIntersecting && frame === null) {
        t0 = null;
        frame = requestAnimationFrame(step);
      } else if (!e.isIntersecting && frame !== null) {
        cancelAnimationFrame(frame);
        frame = null;
        base = travelled;
      }
    });
  }).observe(document.querySelector('.stage'));
}

/* getComputedTextLength is only right once the webfont has loaded, otherwise the
   phrase is measured in the fallback and the loop drifts. */
if (document.fonts && document.fonts.ready) document.fonts.ready.then(initStream);
else addEventListener('load', initStream);


/* ─────────────────────────────────────────── the listening pass
   One transcript per utterance, cleaned up by a playhead sweeping a waveform.

   Everything visual is a pure function of one number: how far through the clip we
   are, 0 to 1. draw(p) is the whole renderer, so the state can be inspected at
   any position without waiting for frames, and the driver below is only a clock.

   Token spans are laid out once and never rebuilt; a pass just adds and removes
   classes. Rebuilding the line each frame would thrash layout and lose the css
   transitions that do the actual animating. */
const UTTERANCES = [
  {
    fix: 'Self correction',
    step: 'Changed their mind',
    tokens: [
      { s: 'I will send you the report' },
      { s: 'on Friday. No no not Friday,', cut: true },
      { s: 'on Monday because the' },
      { s: 'uh', cut: true },
      { s: 'data is not ready yet.' },
    ],
  },
  {
    // Not a list example: this line ends flat, and calling it one would be a
    // label that does not match its own output. Lists are shown properly in the
    // hero, where Mail receives a real numbered one.
    fix: 'Stumbles and repeats',
    step: 'Tripped over a word',
    tokens: [
      { s: 'so', cut: true },
      { s: 'I told the team the' },
      { s: 'the', cut: true },
      { s: 'new timeline should be ready by Monday, and' },
      { s: 'um,', cut: true },
      { s: 'there has been a lot of back and forth.' },
    ],
  },
  {
    fix: 'Grammar',
    step: 'Spoke faster than they thought',
    tokens: [
      { s: 'um so', cut: true },
      { s: 'him and me was discussing about', cut: true },
      { s: 'He and I were discussing', add: true },
      { s: 'the pricing yesterday and' },
      { s: 'uh', cut: true },
      { s: 'he said it looks fine.' },
    ],
  },
];

function initHeard() {
  const waveEl = document.getElementById('heard-wave');
  const headEl = document.getElementById('heard-playhead');
  const scriptEl = document.getElementById('heard-script');
  const fixEl = document.getElementById('heard-fix');
  const clockEl = document.getElementById('heard-elapsed');
  const stepsEl = document.getElementById('heard-steps');
  const stage = document.querySelector('.heard');
  if (!waveEl || !scriptEl || !stepsEl || !stage) return;

  // Time each token by its length, so the head passes long phrases slowly. Gaps
  // between tokens are the breaths, and the waveform dips in them.
  UTTERANCES.forEach((u) => {
    const weights = u.tokens.map((t) => t.s.length + 6);
    const total = weights.reduce((a, b) => a + b, 0);
    let at = 0;
    u.tokens.forEach((t, i) => {
      t.from = at;
      at += (weights[i] / total) * 0.94;      // leave a beat at the end
      t.to = at;
    });
    u.seconds = Math.round(2.5 + total / 26);
  });

  let bars = [], BARS = 0;

  /* Bar count from the available width, not a constant: 84 bars in a 335px
     phone leaves each one about a pixel wide, which reads as a picket fence
     rather than a waveform. Target roughly 5px per bar plus gap. */
  function buildBars() {
    const w = waveEl.getBoundingClientRect().width || 900;
    const want = Math.max(34, Math.min(190, Math.floor(w / 5)));
    if (want === BARS) return false;
    BARS = want;
    bars.forEach((b) => b.remove());
    bars = [];
    for (let i = 0; i < BARS; i++) {
      const b = document.createElement('i');
      waveEl.appendChild(b);
      bars.push(b);
    }
    return true;
  }

  const steps = UTTERANCES.map((u, i) => {
    const btn = document.createElement('button');
    btn.className = 'heard-step';
    btn.type = 'button';
    btn.innerHTML = `<span class="heard-step-bar"><b></b></span>
      <span class="heard-step-label">${u.step}</span>`;
    btn.addEventListener('click', () => play(i));
    stepsEl.appendChild(btn);
    return { btn, fill: btn.querySelector('b') };
  });

  let index = 0, spans = [], amps = [];

  /** Speech-shaped bars: loud inside a token, near silent in the breaths. */
  function buildWave(u) {
    amps = [];
    for (let i = 0; i < BARS; i++) {
      const f = (i + 0.5) / BARS;
      const inWord = u.tokens.some((t) => f >= t.from && f <= t.to);
      // Deterministic jitter, so a replay looks like the same recording.
      const n = Math.abs(Math.sin(i * 12.9898 + u.fix.length) * 43758.5453 % 1);
      const env = 0.55 + 0.45 * Math.sin(f * Math.PI);
      amps.push(inWord ? (0.34 + 0.66 * n) * env : 0.06 + 0.08 * n);
    }
    bars.forEach((b, i) => {
      b.style.height = `${Math.max(3, Math.round(amps[i] * 58))}px`;
    });
  }

  function mount(i) {
    const u = UTTERANCES[i];
    fixEl.textContent = u.fix;
    scriptEl.innerHTML = '';
    spans = u.tokens.map((t) => {
      const el = document.createElement('span');
      el.className = 'tk' + (t.cut ? ' cut' : '') + (t.add ? ' add' : '');
      el.textContent = t.s;
      scriptEl.appendChild(el);
      return el;
    });
    buildWave(u);
    steps.forEach((s, n) => {
      s.btn.setAttribute('aria-current', String(n === i));
      s.fill.style.width = n < i ? '100%' : '0%';
    });
  }

  /** The renderer. p is 0..1 through the current clip. */
  function draw(p) {
    const u = UTTERANCES[index];
    headEl.style.left = `${(p * 100).toFixed(2)}%`;
    clockEl.textContent = `0:${String(Math.round(p * u.seconds)).padStart(2, '0')}`;
    steps[index].fill.style.width = `${(p * 100).toFixed(1)}%`;

    for (let i = 0; i < BARS; i++) {
      const passed = (i + 0.5) / BARS <= p;
      bars[i].classList.toggle('lit', passed);
    }
    u.tokens.forEach((t, i) => {
      const el = spans[i];
      if (t.cut) {
        // Struck the moment the head enters the phrase, lifted once it clears it.
        el.classList.toggle('struck', p >= t.from + (t.to - t.from) * 0.35);
        el.classList.toggle('gone', p >= t.to);
      } else if (t.add) {
        el.classList.toggle('grown', p >= t.from);
      } else {
        el.classList.toggle('done', p >= t.to);
      }
    });
  }

  let frame = null, t0 = null, holding = false;

  function play(i) {
    index = i;
    mount(i);
    t0 = null;
    holding = false;
    draw(0);
    if (reduced) { draw(1); return; }
    stage.classList.add('running');
    if (frame === null) frame = requestAnimationFrame(tick);
  }

  function tick(ms) {
    if (t0 === null) t0 = ms;
    const u = UTTERANCES[index];
    const p = Math.min(1, (ms - t0) / (u.seconds * 1000));
    draw(p);
    if (p >= 1 && !holding) {
      // Let the finished sentence sit before moving on.
      holding = true;
      stage.classList.remove('running');
      setTimeout(() => {
        if (frame !== null) play((index + 1) % UTTERANCES.length);
      }, 2200);
    }
    frame = requestAnimationFrame(tick);
  }

  // Only run while the section is on screen; a waveform nobody is looking at is
  // pure battery.
  new IntersectionObserver((entries) => {
    entries.forEach((e) => {
      if (e.isIntersecting && frame === null) {
        play(index);
      } else if (!e.isIntersecting && frame !== null) {
        cancelAnimationFrame(frame);
        frame = null;
        stage.classList.remove('running');
      }
    });
  }, { threshold: 0.35 }).observe(stage);

  /* Reserve the tallest *unedited* transcript at this width. The raw line wraps
     to more lines than the cleaned one, so without this the stage shrinks as the
     words collapse and shoves the rest of the page upward mid-read. Measured
     rather than assumed: three lines is right at desktop and one short on a
     phone, and any hardcoded number is wrong at some width. */
  function fitScript() {
    scriptEl.style.minHeight = '0px';
    let tallest = 0;
    UTTERANCES.forEach((u, i) => {
      mount(i);
      draw(0);
      tallest = Math.max(tallest, scriptEl.getBoundingClientRect().height);
    });
    scriptEl.style.minHeight = `${Math.ceil(tallest)}px`;
  }

  function layout() {
    buildBars();
    fitScript();
    mount(index);
    draw(0);
  }

  layout();
  addEventListener('resize', () => { layout(); if (frame !== null) play(index); },
                   { passive: true });
  if (reduced) draw(1);

  // Exposed so the pass can be inspected at any position without frames.
  window.__heard = { draw, mount, play, count: UTTERANCES.length,
                     at: (i, p) => { mount(i); index = i; draw(p); } };
}
initHeard();
