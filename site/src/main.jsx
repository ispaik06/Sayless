import React, { useEffect, useRef, useState } from "react";
import { createRoot } from "react-dom/client";
import {
  ArrowRight,
  CheckCircle2,
  ChevronRight,
  CircleUser,
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
    { label: "Soft Rizz", text: "Hey Isabel, I had a really good time tonight. Want to let me take you to dinner tomorrow?" },
    { label: "Confident", text: "I keep thinking about tonight. Dinner tomorrow, just us?" },
    { label: "Smooth", text: "Tonight was way too fun to leave it there. Dinner tomorrow?" }
  ],
  sweet: [
    { label: "Sweet", text: "I had a really nice time with you tonight. Would you want to grab dinner tomorrow?" },
    { label: "Warm", text: "Tonight made me want to see you again soon. Dinner tomorrow?" },
    { label: "Gentle", text: "No pressure, but I would love to take you to dinner tomorrow." }
  ],
  playful: [
    { label: "Playful", text: "I am trying to play it cool, but dinner with you tomorrow sounds too good not to ask." },
    { label: "Cute", text: "The movie was fun, but I think dinner with you tomorrow might beat it." },
    { label: "Tease", text: "If I ask you to dinner tomorrow, are you going to pretend you did not see this coming?" }
  ],
  custom: [
    { label: "Custom", text: "Make it sweet, a little nervous, but still confident." },
    { label: "Try", text: "Ask her to dinner without sounding too intense." },
    { label: "Draft", text: "Keep it warm, simple, and obvious enough that she feels it." }
  ]
};

const DEMO_ADJUSTMENTS = [
  { id: "rizz", label: "Rizz" },
  { id: "sweet", label: "Sweet" },
  { id: "playful", label: "Playful" },
  { id: "custom", label: "Custom" }
];

const DEMO_CHAT_MESSAGES = [
  { side: "left", delay: 420, text: "Hey! I had a great time tonight." },
  { side: "left", compact: true, delay: 780, text: "The movie was fun 🙂" },
  { side: "right", delay: 1650, text: "Me too! Really enjoyed hanging out with you 🍿" },
  { side: "left", delay: 800, text: "Let's do it again soon! 😌" }
];

const DEMO_TYPED_MESSAGE = "Hey, Isabel... I was thinking, maybe we could grab dinner tomorrow...?";
const DEMO_TYPING_START_DELAY = 1000;
const DEMO_INSTALL_URL = "https://ispaik06.github.io/Sayless/install.html";

function AssistantMockup() {
  const stageRef = useRef(null);
  const overlayRef = useRef(null);
  const chatThreadRef = useRef(null);
  const [activePreset, setActivePreset] = useState("rizz");
  const [customDraft, setCustomDraft] = useState("");
  const [showCustom, setShowCustom] = useState(false);
  const [overlayVisible, setOverlayVisible] = useState(false);
  const [overlayOpened, setOverlayOpened] = useState(false);
  const [overlayPosition, setOverlayPosition] = useState({ x: 0, y: 0 });
  const [selectedReply, setSelectedReply] = useState(null);
  const [isDragging, setIsDragging] = useState(false);
  const [typedMessage, setTypedMessage] = useState("");
  const [composerText, setComposerText] = useState("");
  const [followUpMessages, setFollowUpMessages] = useState([]);
  const [visibleMessageCount, setVisibleMessageCount] = useState(0);
  const [demoInView, setDemoInView] = useState(false);
  const [documentActive, setDocumentActive] = useState(() => document.visibilityState === "visible" && document.hasFocus());
  const [typingComplete, setTypingComplete] = useState(false);
  const [showShortcutPrompt, setShowShortcutPrompt] = useState(false);
  const [shortcutPromptDismissed, setShortcutPromptDismissed] = useState(false);
  const [typingReady, setTypingReady] = useState(false);
  const replies = DEMO_REPLY_PRESETS[activePreset];
  const demoFocused = demoInView && documentActive;
  const canUseShortcut = showShortcutPrompt || shortcutPromptDismissed || overlayVisible;
  const chatInputEnabled = typingComplete && overlayOpened;
  const renderedMessages = [
    ...DEMO_CHAT_MESSAGES.slice(0, visibleMessageCount),
    ...followUpMessages
  ];

  useEffect(() => {
    const stage = stageRef.current;

    if (!stage) {
      return undefined;
    }

    const observer = new IntersectionObserver(
      ([entry]) => {
        setDemoInView(entry.isIntersecting && entry.intersectionRatio >= 0.52);
      },
      { rootMargin: "-12% 0px -12% 0px", threshold: 0.52 }
    );

    observer.observe(stage);

    return () => observer.disconnect();
  }, []);

  useEffect(() => {
    function updateDocumentActive() {
      setDocumentActive(document.visibilityState === "visible" && document.hasFocus());
    }

    updateDocumentActive();
    document.addEventListener("visibilitychange", updateDocumentActive);
    window.addEventListener("focus", updateDocumentActive);
    window.addEventListener("blur", updateDocumentActive);

    return () => {
      document.removeEventListener("visibilitychange", updateDocumentActive);
      window.removeEventListener("focus", updateDocumentActive);
      window.removeEventListener("blur", updateDocumentActive);
    };
  }, []);

  useEffect(() => {
    if (!demoFocused || selectedReply || visibleMessageCount >= DEMO_CHAT_MESSAGES.length) {
      return undefined;
    }

    const nextMessage = DEMO_CHAT_MESSAGES[visibleMessageCount];
    const messageTimer = window.setTimeout(
      () => setVisibleMessageCount((count) => Math.min(count + 1, DEMO_CHAT_MESSAGES.length)),
      nextMessage.delay
    );

    return () => window.clearTimeout(messageTimer);
  }, [demoFocused, selectedReply, visibleMessageCount]);

  useEffect(() => {
    if (!demoFocused || selectedReply || visibleMessageCount < DEMO_CHAT_MESSAGES.length || typingReady) {
      return undefined;
    }

    const typingStartTimer = window.setTimeout(() => {
      setTypingReady(true);
    }, DEMO_TYPING_START_DELAY);

    return () => window.clearTimeout(typingStartTimer);
  }, [demoFocused, selectedReply, typingReady, visibleMessageCount]);

  useEffect(() => {
    if (!demoFocused || !typingReady || selectedReply || visibleMessageCount < DEMO_CHAT_MESSAGES.length || typingComplete) {
      return undefined;
    }

    const characters = Array.from(DEMO_TYPED_MESSAGE);

    if (typedMessage.length >= characters.length) {
      setTypingComplete(true);
      return undefined;
    }

    const typingTimer = window.setTimeout(() => {
      const nextLength = Math.min(Array.from(typedMessage).length + 1, characters.length);
      setTypedMessage(characters.slice(0, nextLength).join(""));
    }, 30);

    return () => window.clearTimeout(typingTimer);
  }, [demoFocused, selectedReply, typedMessage, typingComplete, typingReady, visibleMessageCount]);

  useEffect(() => {
    if (!demoFocused || !typingComplete || showShortcutPrompt || shortcutPromptDismissed) {
      return undefined;
    }

    const promptTimer = window.setTimeout(() => {
      setShowShortcutPrompt(true);
    }, 1150);

    return () => window.clearTimeout(promptTimer);
  }, [demoFocused, shortcutPromptDismissed, showShortcutPrompt, typingComplete]);

  useEffect(() => {
    function handleShortcut(event) {
      if (event.altKey && event.code === "Space") {
        event.preventDefault();
        if (!canUseShortcut) {
          return;
        }
        setShowShortcutPrompt(false);
        setShortcutPromptDismissed(true);
        setOverlayVisible((visible) => {
          const nextVisible = !visible;
          if (nextVisible) {
            setOverlayOpened(true);
          }
          return nextVisible;
        });
      }
    }

    window.addEventListener("keydown", handleShortcut);

    return () => window.removeEventListener("keydown", handleShortcut);
  }, [canUseShortcut]);

  useEffect(() => {
    if (!chatThreadRef.current) {
      return;
    }

    chatThreadRef.current.scrollTo({
      top: chatThreadRef.current.scrollHeight,
      behavior: "smooth"
    });
  }, [renderedMessages.length]);

  function openOverlayFromPrompt() {
    setShowShortcutPrompt(false);
    setShortcutPromptDismissed(true);
    setOverlayOpened(true);
    setOverlayVisible(true);
  }

  function selectPreset(presetId) {
    setActivePreset(presetId);
    setShowCustom(presetId === "custom");
    setSelectedReply(null);
  }

  function selectReply(reply) {
    setSelectedReply(reply);
    if (chatInputEnabled) {
      setComposerText(reply.text);
    }
  }

  function submitDemoMessage() {
    const messageText = composerText.trim();

    if (!messageText) {
      return;
    }

    const timestamp = Date.now();
    const firstLoadingId = `isabel-loading-${timestamp}`;
    const secondLoadingId = `download-loading-${timestamp}`;

    setSelectedReply(null);
    setShowShortcutPrompt(false);
    setShortcutPromptDismissed(true);
    setComposerText("");
    setFollowUpMessages((messages) => [
      ...messages,
      { id: `user-${timestamp}`, side: "right", text: messageText }
    ]);

    window.setTimeout(() => {
      setFollowUpMessages((messages) => [
        ...messages,
        { id: firstLoadingId, side: "left", loading: true }
      ]);
    }, 520);

    window.setTimeout(() => {
      setFollowUpMessages((messages) => [
        ...messages.filter((message) => message.id !== firstLoadingId),
        { id: `isabel-reply-${timestamp}`, side: "left", text: "Actually, never mind. I have a boyfriend. Sorry." }
      ]);
    }, 1750);

    window.setTimeout(() => {
      setFollowUpMessages((messages) => [
        ...messages,
        { id: secondLoadingId, side: "left", loading: true }
      ]);
    }, 2450);

    window.setTimeout(() => {
      setFollowUpMessages((messages) => [
        ...messages.filter((message) => message.id !== secondLoadingId),
        {
          id: `download-reply-${timestamp}`,
          side: "left",
          text: "Go download Sayless and find another girl to hang out with.",
          link: DEMO_INSTALL_URL
        }
      ]);
    }, 3850);
  }

  function startOverlayDrag(event) {
    if (event.button !== undefined && event.button !== 0) {
      return;
    }

    if (event.target.closest("button, input, textarea, a")) {
      return;
    }

    event.preventDefault();
    event.currentTarget.setPointerCapture?.(event.pointerId);
    setIsDragging(true);

    const startX = event.clientX;
    const startY = event.clientY;
    const initialPosition = overlayPosition;
    const stageRect = stageRef.current?.getBoundingClientRect();
    const overlayRect = overlayRef.current?.getBoundingClientRect();

    function clamp(value, min, max) {
      return Math.min(Math.max(value, min), max);
    }

    function handlePointerMove(moveEvent) {
      const nextX = initialPosition.x + moveEvent.clientX - startX;
      const nextY = initialPosition.y + moveEvent.clientY - startY;

      if (!stageRect || !overlayRect) {
        setOverlayPosition({ x: nextX, y: nextY });
        return;
      }

      setOverlayPosition({
        x: clamp(
          nextX,
          initialPosition.x + stageRect.left - overlayRect.left,
          initialPosition.x + stageRect.right - overlayRect.right
        ),
        y: clamp(
          nextY,
          initialPosition.y + stageRect.top - overlayRect.top,
          initialPosition.y + stageRect.bottom - overlayRect.bottom
        )
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
    <div className={`demo-stage ${overlayVisible ? "has-overlay" : ""}`} ref={stageRef}>
      <div className="chat-window-demo">
        <div className="window-bar">
          <span />
          <span />
          <span />
        </div>
        <div className="conversation">
          <div className="chat-title">
            <strong>Isabel</strong>
            <span>Active now</span>
          </div>
          <div className="chat-thread" ref={chatThreadRef}>
            {renderedMessages.map((message) => (
              <div
                key={message.id ?? message.text}
                className={`chat-row ${message.side} ${message.compact ? "compact" : ""} ${message.loading ? "is-loading" : ""}`}
              >
                {message.loading ? (
                  <span className="chat-loading-dots" aria-label="Isabel is typing">
                    <span></span>
                    <span></span>
                    <span></span>
                  </span>
                ) : (
                  <>
                    {message.text}
                    {message.link && (
                      <a className="chat-download-card" href={message.link} aria-label="Download Sayless">
                        <img src="assets/img/app-icon.png" alt="" />
                        <span>
                          <strong>Download Sayless</strong>
                          <em>Open install page</em>
                        </span>
                      </a>
                    )}
                  </>
                )}
              </div>
            ))}
          </div>
          {chatInputEnabled ? (
            <textarea
              className={`input-line ${composerText ? "has-reply" : ""}`}
              value={composerText}
              onChange={(event) => {
                setComposerText(event.target.value);
                setSelectedReply(null);
              }}
              onKeyDown={(event) => {
                if (event.key === "Enter" && !event.shiftKey) {
                  event.preventDefault();
                  submitDemoMessage();
                }
              }}
              aria-label="Message Isabel"
              placeholder={DEMO_TYPED_MESSAGE}
              rows={2}
            />
          ) : (
            <div className={`input-line ${selectedReply ? "has-reply" : ""}`}>
              {selectedReply ? selectedReply.text : typedMessage}
              {!selectedReply && demoFocused && typingReady && visibleMessageCount === DEMO_CHAT_MESSAGES.length && !typingComplete && (
                <span className="typing-caret" aria-hidden="true"></span>
              )}
            </div>
          )}
        </div>
      </div>

      {showShortcutPrompt && !shortcutPromptDismissed && (
        <button className="shortcut-hint" type="button" onClick={openOverlayFromPrompt}>
          <span>Press</span>
          <kbd>Option</kbd>
          <kbd>Space</kbd>
        </button>
      )}

      {overlayVisible && (
        <div
          ref={overlayRef}
          className={`sayless-overlay-demo ${isDragging ? "is-dragging" : ""}`}
          style={{ "--overlay-x": `${overlayPosition.x}px`, "--overlay-y": `${overlayPosition.y}px` }}
          onPointerDown={startOverlayDrag}
        >
          <div className="overlay-head">
            <div className="overlay-brand">
              <span className="overlay-symbol">...</span>
              <strong>Sayless</strong>
              <em>Isabel</em>
            </div>
            <div className="overlay-actions">
              <button type="button" aria-label="Refresh suggestions">
                <RefreshCw size={13} />
              </button>
              <button type="button" aria-label="Close overlay" onClick={() => setOverlayVisible(false)}>
                <X size={13} />
              </button>
            </div>
          </div>
          <div className="overlay-suggestions">
            {replies.map((reply) => (
              <button
                key={reply.label}
                type="button"
                className={selectedReply?.text === reply.text ? "is-selected" : ""}
                onClick={() => selectReply(reply)}
              >
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
              placeholder="Type the exact vibe you want"
            />
          )}
        </div>
      )}
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
    { label: "LinkedIn", href: "https://www.linkedin.com/in/inseong-paik-7b2982354/", icon: <Linkedin size={19} /> },
    { label: "About me", href: "https://ispaik06.github.io/about/", icon: <CircleUser size={19} /> }
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
