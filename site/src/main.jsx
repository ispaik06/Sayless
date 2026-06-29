import React, { useState } from "react";
import { createRoot } from "react-dom/client";
import {
  ArrowRight,
  CheckCircle2,
  ChevronRight,
  Command,
  Download,
  Eye,
  Github,
  Instagram,
  Linkedin,
  LockKeyhole,
  MessageSquareText,
  RefreshCw,
  Sparkles,
  Wand2,
  X
} from "lucide-react";
import "./styles.css";

const DOWNLOAD_URL = "https://sayless-production-e6b4.up.railway.app/download";
const INSTALL_URL = "install.html";

function App() {
  const path = window.location.pathname;
  const isInstallPage = path.endsWith("/install.html") || path.endsWith("/install");

  return isInstallPage ? <InstallPage /> : <HomePage />;
}

function Shell({ children, install = false }) {
  return (
    <div className="site-shell">
      <header className="topbar">
        <a className="brand" href="index.html" aria-label="Sayless home">
          <img src="assets/img/app-icon.png" alt="" />
          <span>Sayless</span>
        </a>
        <nav className="nav-links" aria-label="Primary navigation">
          <a href={install ? "index.html#product" : "#product"}>Product</a>
          <a href={install ? "index.html#privacy" : "#privacy"}>Privacy</a>
          <a href={INSTALL_URL}>Install</a>
        </nav>
        <a className="nav-cta" href={INSTALL_URL}>
          <Download size={17} />
          Download
        </a>
      </header>
      {children}
    </div>
  );
}

function HomePage() {
  return (
    <Shell>
      <main>
        <section className="hero">
          <div className="hero-copy">
            <div className="eyebrow">
              <Sparkles size={16} />
              AI communication wingman for macOS
            </div>
            <h1>Your next reply, already in context.</h1>
            <p className="hero-subtitle">
              Sayless reads the conversation in front of you and suggests replies that fit the room, the relationship,
              and what you are trying to say.
            </p>
            <div className="hero-actions">
              <a className="primary-button" href={INSTALL_URL}>
                <Download size={19} />
                Download for macOS
              </a>
              <a className="secondary-button" href="#demo">
                See how it works
                <ChevronRight size={18} />
              </a>
            </div>
            <p className="hero-note">Requires macOS, Accessibility permission, and a Sayless account.</p>
          </div>

          <div className="hero-visual" aria-label="Sayless app preview">
            <HeroAppVisual />
          </div>
        </section>

        <section className="demo-section" id="demo">
          <AssistantMockup />
        </section>

        <section className="proof-band" aria-label="Sayless workflow">
          <div>
            <span>01</span>
            Reads visible context
          </div>
          <div>
            <span>02</span>
            Understands the room
          </div>
          <div>
            <span>03</span>
            Gives you the line
          </div>
        </section>

        <section className="section split" id="product">
          <div>
            <p className="section-kicker">No prompt theater</p>
            <h2>An assistant for the chat you are already in.</h2>
            <p>
              Sayless is not a tone converter. It is a context-aware reply assistant that lives beside your text input.
              Open it when you are stuck, pick the option that sounds closest, and keep the conversation moving.
            </p>
          </div>
          <div className="feature-grid">
            <FeatureCard
              icon={<Eye />}
              title="Reads the room"
              text="Uses the latest visible messages to understand what is happening before suggesting anything."
            />
            <FeatureCard
              icon={<MessageSquareText />}
              title="Sounds like a reply"
              text="Gives concise, usable lines instead of long AI paragraphs that need another edit."
            />
            <FeatureCard
              icon={<Wand2 />}
              title="Adjusts fast"
              text="Ask for shorter, warmer, cleaner, funnier, or custom versions until the line fits."
            />
            <FeatureCard
              icon={<Command />}
              title="Native on Mac"
              text="A menu bar app with a shortcut-first overlay designed to stay out of the way."
            />
          </div>
        </section>

        <section className="section workflow">
          <p className="section-kicker">How it feels</p>
          <h2>Less explaining. More replying.</h2>
          <div className="workflow-grid">
            <Step number="1" title="You are in KakaoTalk" text="No copying the whole conversation into a separate AI app." />
            <Step number="2" title="Sayless sees the context" text="The assistant reads what is visible and prepares replies around the current moment." />
            <Step number="3" title="You choose the line" text="Send it as-is, tweak the tone, or use it as the starting point." />
          </div>
        </section>

        <section className="section privacy" id="privacy">
          <div className="privacy-panel">
            <LockKeyhole size={28} />
            <div>
              <p className="section-kicker">Trust by design</p>
              <h2>You stay in control.</h2>
              <p>
                Sayless appears when you ask for help. The current macOS build requires Accessibility permission so it
                can read supported visible text and place a lightweight assistant next to your conversation.
              </p>
            </div>
          </div>
        </section>

        <section className="final-cta">
          <div>
            <p className="section-kicker">Ready when the chat is not</p>
            <h2>Read the room. Reply with Sayless.</h2>
          </div>
          <a className="primary-button light" href={INSTALL_URL}>
            Review install notes
            <ArrowRight size={19} />
          </a>
        </section>
      </main>
      <Footer />
    </Shell>
  );
}

function InstallPage() {
  const [acknowledged, setAcknowledged] = useState(false);

  return (
    <Shell install>
      <main className="install-page">
        <section className="install-hero">
          <div>
            <div className="eyebrow">
              <Sparkles size={16} />
              Installation notes
            </div>
            <h1>Install Sayless for macOS.</h1>
            <p>
              Review the first-launch steps, then unlock the download. The current release is distributed outside the
              Mac App Store, so macOS may ask you to allow it manually.
            </p>
          </div>
          <div className="install-summary">
            <img src="assets/img/app-icon.png" alt="Sayless app icon" />
            <span>macOS menu bar app</span>
            <strong>Accessibility permission required on first launch.</strong>
          </div>
        </section>

        <section className="install-layout">
          <div className="install-notes">
            <p className="section-kicker">Installation notes</p>
            <h2>macOS may block the app once.</h2>
            <p>
              Sayless is distributed outside the Mac App Store. If macOS shows the "'Sayless' Not Opened" alert, allow
              it manually in System Settings.
            </p>
            <ol>
              <li>Click <strong>Done</strong> on the macOS warning.</li>
              <li>Open <strong>System Settings</strong> and go to <strong>Privacy &amp; Security</strong>.</li>
              <li>Scroll down to the <strong>Security</strong> section.</li>
              <li>Click <strong>Open Anyway</strong> next to the Sayless message.</li>
              <li>Launch Sayless again, then grant Accessibility permission when prompted.</li>
            </ol>
          </div>
          <MacSecurityMockup />
        </section>

        <section className="install-gate" aria-label="Download confirmation">
          <button
            className={`read-button ${acknowledged ? "is-complete" : ""}`}
            type="button"
            onClick={() => setAcknowledged(true)}
          >
            <CheckCircle2 size={20} />
            {acknowledged ? "Installation notes confirmed" : "I have read the installation notes"}
          </button>
          <div className={`download-reveal ${acknowledged ? "is-visible" : ""}`}>
            <a className="primary-button" href={DOWNLOAD_URL}>
              <Download size={19} />
              Download latest DMG
            </a>
            <p>Downloads the latest macOS build directly.</p>
          </div>
        </section>
      </main>
      <Footer />
    </Shell>
  );
}

function HeroAppVisual() {
  return (
    <div className="hero-app-visual">
      <div className="hero-glass-orbit one"></div>
      <div className="hero-glass-orbit two"></div>
      <div className="app-photo-card">
        <div className="app-photo-topline">
          <span></span>
          <span></span>
          <span></span>
        </div>
        <img src="assets/img/app-icon.png" alt="Sayless app icon" />
        <strong>Sayless</strong>
        <p>Mac-first AI communication assistant</p>
      </div>
      <div className="floating-status top">
        <span>Menu bar</span>
        <strong>Always one shortcut away</strong>
      </div>
      <div className="floating-status bottom">
        <span>Context ready</span>
        <strong>3 replies prepared</strong>
      </div>
    </div>
  );
}

const DEMO_REPLY_PRESETS = {
  rizz: [
    { label: "Rizz", text: "가야지. 근데 너 있으면 나 오늘 텐션 좀 위험함 ㅋㅋ" },
    { label: "Flirty", text: "나 원래 고민하는 척 잘하는데, 너 부르면 바로 흔들림." },
    { label: "MZ", text: "오히려 좋아. 대신 오늘 플러팅은 네가 책임져야 됨." }
  ],
  shorter: [
    { label: "Short", text: "갈게. 너 있으면 재밌을 듯 ㅋㅋ" },
    { label: "Clean", text: "좋아, 몇 시에 볼까?" },
    { label: "Lowkey", text: "나갈까 봐. 너도 계속 있는 거지?" }
  ],
  softer: [
    { label: "Soft", text: "나도 보고 싶긴 해. 너무 티났나 ㅋㅋ" },
    { label: "Warm", text: "갈게. 너 기다린다니까 좀 설렌다." },
    { label: "Sweet", text: "네가 그렇게 말하면 안 나갈 수가 없잖아." }
  ],
  funnier: [
    { label: "Funny", text: "이 정도면 나 거의 소환 당한 거 아님? 출동함." },
    { label: "Chaotic", text: "나가면 너 때문에 심박수 이슈 생길 듯 ㅋㅋ" },
    { label: "Bold", text: "오늘 내가 가면 분위기 버프 들어가는 거 알지?" }
  ],
  custom: [
    { label: "Custom", text: "너한테만 살짝 약한 컨셉으로 가볼게." },
    { label: "Try", text: "지금 가면 나 너무 기대한 사람 같아? 그래도 갈래." },
    { label: "Draft", text: "나갈게. 대신 오늘은 네가 내 옆자리 예약해." }
  ]
};

const DEMO_ADJUSTMENTS = [
  { id: "shorter", label: "Shorter" },
  { id: "softer", label: "Softer" },
  { id: "funnier", label: "Funnier" },
  { id: "custom", label: "Custom" }
];

function AssistantMockup() {
  const [activePreset, setActivePreset] = useState("rizz");
  const [customDraft, setCustomDraft] = useState("");
  const [showCustom, setShowCustom] = useState(false);
  const [overlayPosition, setOverlayPosition] = useState({ x: 0, y: 0 });
  const [isDragging, setIsDragging] = useState(false);
  const replies = DEMO_REPLY_PRESETS[activePreset];

  function selectPreset(presetId) {
    setActivePreset(presetId);
    setShowCustom(presetId === "custom");
  }

  function startOverlayDrag(event) {
    if (event.button !== undefined && event.button !== 0) {
      return;
    }

    if (event.target.closest("button, input")) {
      return;
    }

    event.preventDefault();
    event.currentTarget.setPointerCapture?.(event.pointerId);
    setIsDragging(true);

    const startX = event.clientX;
    const startY = event.clientY;
    const initialPosition = overlayPosition;

    function handlePointerMove(moveEvent) {
      setOverlayPosition({
        x: initialPosition.x + moveEvent.clientX - startX,
        y: initialPosition.y + moveEvent.clientY - startY
      });
    }

    function handlePointerUp() {
      setIsDragging(false);
      window.removeEventListener("pointermove", handlePointerMove);
      window.removeEventListener("pointerup", handlePointerUp);
    }

    window.addEventListener("pointermove", handlePointerMove);
    window.addEventListener("pointerup", handlePointerUp, { once: true });
  }

  return (
    <div className="device-frame">
      <div className="window-bar">
        <span />
        <span />
        <span />
      </div>
      <div className="conversation">
        <div className="chat-title">
          <strong>하린</strong>
          <span>typing like she knows exactly what she is doing</span>
        </div>
        <div className="chat-thread">
          <div className="chat-row left">오늘 나올거야?</div>
          <div className="chat-row left compact">너 오면 나 텐션 좀 올라갈 듯 ㅋㅋ</div>
          <div className="chat-row right">나 지금 고민하는 척 하는 중</div>
        </div>
        <div className="input-line">센스있게 답장하고 싶은데 너무 티나면 안 됨...</div>
        <div
          className={`sayless-overlay-demo ${isDragging ? "is-dragging" : ""}`}
          style={{ transform: `translate(${overlayPosition.x}px, ${overlayPosition.y}px)` }}
        >
          <div className="overlay-head" onPointerDown={startOverlayDrag}>
            <div className="overlay-brand">
              <span className="overlay-symbol">...</span>
              <strong>Sayless</strong>
              <em>KakaoTalk</em>
            </div>
            <div className="overlay-actions">
              <button type="button" aria-label="Refresh suggestions">
                <RefreshCw size={13} />
              </button>
              <button type="button" aria-label="Close overlay">
                <X size={13} />
              </button>
            </div>
          </div>
          <div className="overlay-suggestions">
            {replies.map((reply, index) => (
              <button key={reply.label} type="button" className={index === 0 ? "is-selected" : ""}>
                <span>{reply.label}</span>
                <p>{reply.text}</p>
              </button>
            ))}
          </div>
          <div className="overlay-adjustments" aria-label="Reply adjustment controls">
            {DEMO_ADJUSTMENTS.map((adjustment) => (
              <button
                key={adjustment.id}
                type="button"
                className={activePreset === adjustment.id ? "is-active" : ""}
                onClick={() => selectPreset(adjustment.id)}
              >
                {adjustment.label}
              </button>
            ))}
          </div>
          {showCustom && (
            <input
              className="overlay-custom-input"
              value={customDraft}
              onChange={(event) => setCustomDraft(event.target.value)}
              onKeyDown={(event) => {
                if (event.key === "Enter") {
                  event.preventDefault();
                }
              }}
              placeholder="원하는 무드 적어보기"
            />
          )}
        </div>
      </div>
    </div>
  );
}

function FeatureCard({ icon, title, text }) {
  return (
    <article className="feature-card">
      <div className="feature-icon">{icon}</div>
      <h3>{title}</h3>
      <p>{text}</p>
    </article>
  );
}

function Step({ number, title, text }) {
  return (
    <article className="step-card">
      <span>{number}</span>
      <h3>{title}</h3>
      <p>{text}</p>
    </article>
  );
}

function MacSecurityMockup() {
  return (
    <div className="mac-install-guide" aria-label="macOS Privacy and Security settings showing the Open Anyway button">
      <div className="gatekeeper-alert">
        <div className="alert-help">?</div>
        <div className="alert-icon-wrap">
          <img src="assets/img/app-icon.png" alt="" className="alert-app-icon" />
          <span className="alert-warning">!</span>
        </div>
        <h3>"Sayless" Not Opened</h3>
        <p>Apple could not verify "Sayless" is free of malware that may harm your Mac or compromise your privacy.</p>
        <div className="alert-done">Done</div>
      </div>

      <div className="settings-window">
        <div className="settings-sidebar">
          <div className="settings-traffic-lights" aria-hidden="true">
            <span className="dot red"></span>
            <span className="dot yellow"></span>
            <span className="dot green"></span>
          </div>
          <div className="settings-search">Search</div>
          <div className="settings-side-row"><span className="settings-side-icon pink"></span>Notifications</div>
          <div className="settings-side-row"><span className="settings-side-icon purple"></span>Focus</div>
          <div className="settings-side-row"><span className="settings-side-icon gray"></span>Screen Time</div>
          <div className="settings-side-row"><span className="settings-side-icon black"></span>Lock Screen</div>
          <div className="settings-side-row active"><span className="settings-side-icon blue"></span>Privacy &amp; Security</div>
          <div className="settings-side-row"><span className="settings-side-icon rose"></span>Touch ID &amp; Password</div>
          <div className="settings-side-row"><span className="settings-side-icon cyan"></span>Users &amp; Groups</div>
          <div className="settings-side-row"><span className="settings-side-icon orange"></span>Internet Accounts</div>
        </div>
        <div className="settings-content">
          <div className="settings-titlebar">
            <div className="settings-nav-buttons" aria-hidden="true">
              <span>&lt;</span>
              <span>&gt;</span>
            </div>
            <h3>Privacy &amp; Security</h3>
          </div>
          <div className="settings-list">
            <div className="settings-row"><span className="settings-row-icon teal"></span>Speech Recognition <strong>0</strong></div>
            <div className="settings-row"><span className="settings-row-icon azure"></span>Sensitive Content Warning <strong>Off</strong></div>
            <div className="settings-row"><span className="settings-row-icon red"></span>Blocked Contacts</div>
            <div className="settings-row"><span className="settings-row-icon indigo"></span>Analytics &amp; Improvements</div>
            <div className="settings-row"><span className="settings-row-icon blue"></span>Apple Advertising</div>
          </div>
          <div className="security-label">Security</div>
          <div className="security-panel">
            <div className="allow-row">
              <span>Allow applications from</span>
              <strong>App Store &amp; Known Developers</strong>
            </div>
            <div className="blocked-row">
              <div>
                <strong>"Sayless" was blocked to protect your Mac.</strong>
                <p>Apple could not verify "Sayless" is free of malware that may harm your Mac or compromise your privacy.</p>
              </div>
              <button type="button" className="open-anyway-callout">Open Anyway</button>
            </div>
          </div>
          <div className="settings-list settings-list-bottom">
            <div className="settings-row"><span className="settings-row-icon gray"></span>FileVault <strong>On</strong></div>
            <div className="settings-row"><span className="settings-row-icon slate"></span>Accessories <strong>Ask for new accessories</strong></div>
          </div>
        </div>
      </div>
    </div>
  );
}

function Footer() {
  const socials = [
    { label: "Instagram", href: "https://www.instagram.com/_ispaik/", icon: <Instagram size={19} /> },
    { label: "GitHub", href: "https://github.com/ispaik06", icon: <Github size={19} /> },
    { label: "LinkedIn", href: "https://www.linkedin.com/in/inseong-paik-7b2982354/", icon: <Linkedin size={19} /> }
  ];

  return (
    <footer className="footer">
      <div className="footer-left">
        <span>&copy; 2026 Sayless. All rights reserved.</span>
        <a href="appcast.xml">Appcast</a>
      </div>
      <div className="footer-right" aria-label="Creator links">
        <span>Created by Inseong Paik</span>
        <div className="social-links">
          {socials.map((social) => (
            <a key={social.label} href={social.href} aria-label={social.label} target="_blank" rel="noopener noreferrer">
              {social.icon}
            </a>
          ))}
        </div>
      </div>
    </footer>
  );
}

createRoot(document.getElementById("root")).render(<App />);
