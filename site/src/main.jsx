import React, { useEffect, useRef, useState } from "react";
import { createRoot } from "react-dom/client";
import {
  ArrowDown,
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
const LANG_STORAGE_KEY = "sayless-site-language";

const COPY = {
  en: {
    nav: {
      product: "Product",
      privacy: "Privacy",
      install: "Install",
      download: "Download",
      toggleLabel: "Switch language",
      toggleText: "KO"
    },
    home: {
      eyebrow: "AI communication wingman for macOS",
      title: "Your next reply, already in context.",
      subtitle:
        "Sayless reads the visible chat and gives you short replies that fit the moment.",
      downloadCta: "Download for macOS",
      demoCta: "See how it works",
      note: "Requires macOS, Accessibility permission, and a Sayless account.",
      proof: ["Reads visible context", "Understands the room", "Gives you the line"],
      productKicker: "No prompt theater",
      productTitle: "An assistant for the chat you are already in.",
      productText:
        "Sayless is not a tone converter. It is a context-aware reply assistant that lives beside your text input. Open it when you are stuck, pick the option that sounds closest, and keep the conversation moving.",
      features: [
        {
          title: "Reads the room",
          text: "Uses the latest visible messages to understand what is happening before suggesting anything."
        },
        {
          title: "Sounds like a reply",
          text: "Gives concise, usable lines instead of long AI paragraphs that need another edit."
        },
        {
          title: "Adjusts fast",
          text: "Ask for shorter, warmer, cleaner, funnier, or custom versions until the line fits."
        },
        {
          title: "Native on Mac",
          text: "A menu bar app with a shortcut-first overlay designed to stay out of the way."
        }
      ],
      workflowKicker: "How it feels",
      workflowTitle: "Less explaining. More replying.",
      steps: [
        { title: "You are in KakaoTalk", text: "No copying the whole conversation into a separate AI app." },
        {
          title: "Sayless sees the context",
          text: "The assistant reads what is visible and prepares replies around the current moment."
        },
        { title: "You choose the line", text: "Send it as-is, tweak the tone, or use it as the starting point." }
      ],
      privacyKicker: "Trust by design",
      privacyTitle: "You stay in control.",
      privacyText:
        "Sayless appears when you ask for help. The current macOS build requires Accessibility permission so it can read supported visible text and place a lightweight assistant next to your conversation.",
      finalKicker: "Ready when the chat is not",
      finalTitle: "Read the room. Reply with Sayless.",
      finalCta: "Review install notes",
      platformsKicker: "Works with",
      platformsTitle: "Works with your favorite messaging apps",
      platformsText: "KakaoTalk, Instagram, Discord, Slack, and more.",
      platformStatusReady: "Available now",
      platformStatusPlanned: "Planned",
      platformsDisclaimer:
        "All product names, logos, and brands are property of their respective owners. Sayless is not affiliated with or endorsed by Kakao, Meta, Discord, Slack, or any listed platform.",
      platforms: [
        {
          id: "kakao",
          title: "KakaoTalk",
          status: "ready",
          logo: "/logos/kakaotalk.svg"
        },
        {
          id: "instagram",
          title: "Instagram",
          status: "ready",
          logo: "/logos/instagram.svg"
        },
        {
          id: "discord",
          title: "Discord",
          status: "planned",
          logo: "/logos/discord.svg"
        },
        {
          id: "slack",
          title: "Slack",
          status: "planned",
          logo: "/logos/slack.svg"
        }
      ],
      visualSubtitle: "Mac-first AI communication assistant",
      menuBar: "Menu bar",
      shortcutReady: "Always one shortcut away",
      contextReady: "Context ready",
      repliesPrepared: "3 replies prepared"
    },
    install: {
      eyebrow: "Installation notes",
      title: "Install Sayless for macOS.",
      intro:
        "Review the first-launch steps, then unlock the download. The current release is distributed outside the Mac App Store, so macOS may ask you to allow it manually.",
      appLabel: "macOS menu bar app",
      summary: "Accessibility permission required on first launch.",
      notesKicker: "Installation notes",
      notesTitle: "macOS may block the app once.",
      notesText:
        "Sayless is distributed outside the Mac App Store. If macOS shows the \"'Sayless' Not Opened\" alert, allow it manually in System Settings.",
      developerNoteTitle: "Why this warning appears",
      developerNote:
        "This warning appears because the developer has not paid Apple the $99/year developer program fee yet 😭. It does not mean Sayless contains malware or anything designed to harm your computer. You just need to allow it manually once.",
      steps: [
        <>Click <strong>Done</strong> on the macOS warning.</>,
        <>Open <strong>System Settings</strong> and go to <strong>Privacy &amp; Security</strong>.</>,
        <>Scroll down to the <strong>Security</strong> section.</>,
        <>Click <strong>Open Anyway</strong> next to the Sayless message.</>,
        <>Launch Sayless again, then grant Accessibility permission when prompted.</>
      ],
      confirmed: "Installation notes confirmed",
      acknowledge: "I have read the installation notes",
      download: "Download latest DMG",
      downloadHelp: "Downloads the latest macOS build directly.",
      scrollHint: "Download button is below",
      scrollHintSubtext: "Review the notes, then scroll down."
    },
    demo: {
      person: "Isabel",
      status: "Active now",
      typedMessage: "Hey, Isabel... I was thinking, maybe we could grab dinner tomorrow...?",
      chatMessages: [
        { side: "left", delay: 420, text: "Hey! I had a great time tonight." },
        { side: "left", compact: true, delay: 780, text: "The movie was fun 🙂" },
        { side: "right", delay: 1650, text: "Me too! Really enjoyed hanging out with you 🍿" },
        { side: "left", delay: 800, text: "Let's do it again soon! 😌" }
      ],
      replyPresets: {
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
      },
      adjustments: [
        { id: "rizz", label: "Rizz" },
        { id: "sweet", label: "Sweet" },
        { id: "playful", label: "Playful" },
        { id: "custom", label: "Custom" }
      ],
      customPlaceholder: "Type the exact vibe you want",
      loadingLabel: "Isabel is typing",
      downloadCardTitle: "Download Sayless",
      downloadCardSubtitle: "Open install page",
      downloadAria: "Download Sayless",
      refreshAria: "Refresh suggestions",
      closeAria: "Close overlay",
      adjustmentAria: "Reply adjustment controls",
      messageAria: "Message Isabel",
      firstReply: "Actually, never mind. I have a boyfriend. Sorry.",
      downloadReply: "Go download Sayless and find another girl to hang out with 🥀"
    },
    footer: {
      rights: "© 2026 Sayless. All rights reserved.",
      createdBy: "Created by Inseong Paik"
    }
  },
  ko: {
    nav: {
      product: "제품",
      privacy: "개인정보",
      install: "설치",
      download: "다운로드",
      toggleLabel: "언어 전환",
      toggleText: "EN"
    },
    home: {
      eyebrow: "macOS용 AI 대화 윙맨",
      title: "답장 고민,\n이제 Sayless에\n맡기세요",
      subtitle:
        "보이는 대화를 읽고, 지금 바로 보낼 만한 짧은 답장을 준비합니다.",
      downloadCta: "macOS용 다운로드",
      demoCta: "작동 방식 알아보기",
      note: "macOS, 손쉬운 사용 권한, Sayless 계정이 필요합니다.",
      proof: ["보이는 대화 읽기", "분위기 파악하기", "보낼 말 건네주기"],
      productKicker: "프롬프트 쇼 안 해도 됨",
      productTitle: "채팅창 바로 옆,\n나만의 대화\n어시스턴트",
      productText:
        "Sayless는 말투만 바꿔주는 앱이 아닙니다. 지금 대화의 맥락을 읽고 입력창 옆에서 바로 쓸 수 있는 답장을 준비합니다. 말문이 막힐 때 열고, 제일 너다운 답을 고르고, 흐름을 놓치지 마세요.",
      features: [
        {
          title: "분위기를 읽음",
          text: "최근에 보이는 메시지를 바탕으로 지금 둘 사이에 무슨 흐름인지 먼저 파악합니다."
        },
        {
          title: "진짜 답장처럼",
          text: "AI가 쓴 긴 문단 말고, 바로 보내도 어색하지 않은 짧고 쓸만한 문장을 줍니다."
        },
        {
          title: "느낌 조절 빠르게",
          text: "더 짧게, 더 다정하게, 더 장난스럽게, 더 깔끔하게. 원하는 온도까지 바로 바꿀 수 있습니다."
        },
        {
          title: "맥에 자연스럽게",
          text: "메뉴바에 있다가 단축키 한 번으로 나타나는, 방해되지 않는 macOS 오버레이입니다."
        }
      ],
      workflowKicker: "실제로는 이런 느낌",
      workflowTitle: "설명은 줄이고. 답장은 빨리.",
      steps: [
        { title: "카톡을 보고 있다가", text: "대화 전체를 다른 AI 앱에 복붙할 필요가 없습니다." },
        {
          title: "Sayless가 흐름을 읽고",
          text: "화면에 보이는 현재 대화를 바탕으로 지금 보낼 만한 답장을 준비합니다."
        },
        { title: "네가 골라 보내면 됨", text: "그대로 보내도 되고, 톤을 살짝 바꾸거나 시작점으로 써도 됩니다." }
      ],
      privacyKicker: "통제권은 사용자에게",
      privacyTitle: "필요할 때만 나타납니다.",
      privacyText:
        "Sayless는 네가 도움을 요청할 때만 나타납니다. 현재 macOS 빌드는 화면에 보이는 지원 가능한 텍스트를 읽고 대화 옆에 가벼운 assistant를 띄우기 위해 손쉬운 사용 권한이 필요합니다.",
      finalKicker: "채팅이 어려울 때 바로",
      finalTitle: "눈치 빠른 AI와 함께하는 대화",
      finalCta: "지금 바로 Sayless 써보기",
      platformsKicker: "Works with",
      platformsTitle: "Works with your favorite messaging apps",
      platformsText: "KakaoTalk, Instagram, Discord, Slack, and more.",
      platformStatusReady: "현재 지원",
      platformStatusPlanned: "확장 예정",
      platformsDisclaimer:
        "All product names, logos, and brands are property of their respective owners. Sayless is not affiliated with or endorsed by Kakao, Meta, Discord, Slack, or any listed platform.",
      platforms: [
        {
          id: "kakao",
          title: "카카오톡",
          status: "ready",
          logo: "/logos/kakaotalk.svg"
        },
        {
          id: "instagram",
          title: "Instagram",
          status: "ready",
          logo: "/logos/instagram.svg"
        },
        {
          id: "discord",
          title: "Discord",
          status: "planned",
          logo: "/logos/discord.svg"
        },
        {
          id: "slack",
          title: "Slack",
          status: "planned",
          logo: "/logos/slack.svg"
        }
      ],
      visualSubtitle: "맥을 먼저 생각한 AI 대화 assistant",
      menuBar: "메뉴바",
      shortcutReady: "단축키 한 번이면 준비",
      contextReady: "맥락 준비됨",
      repliesPrepared: "답장 3개 준비됨"
    },
    install: {
      eyebrow: "설치 안내",
      title: "macOS에 Sayless 설치하기.",
      intro:
        "처음 실행할 때 필요한 단계를 확인한 뒤 다운로드를 열 수 있습니다. 현재 릴리즈는 Mac App Store 밖에서 배포되기 때문에 macOS가 수동 허용을 요청할 수 있습니다.",
      appLabel: "macOS 메뉴바 앱",
      summary: "처음 실행할 때 손쉬운 사용 권한이 필요합니다.",
      notesKicker: "설치 안내",
      notesTitle: "macOS가 앱을 한 번 막을 수 있습니다.",
      notesText:
        "Sayless는 Mac App Store 밖에서 배포됩니다. macOS에서 \"'Sayless'을(를) 열 수 없음\" 같은 경고가 뜨면 시스템 설정에서 한 번만 직접 허용해 주세요.",
      developerNoteTitle: "왜 이런 경고가 뜨나요?",
      developerNote:
        "개발자가 아직 Apple에게 연 99달러를 안 줘서 이런 알림이 뜹니다 ㅠㅠ. Sayless에 악성코드가 있거나 컴퓨터를 해치려는 기능이 있다는 뜻은 아닙니다. 처음 한 번만 직접 허용해 주시면 됩니다. 죄송합니다.",
      steps: [
        <>macOS 경고창에서 <strong>완료</strong>를 누릅니다.</>,
        <><strong>시스템 설정</strong>을 열고 <strong>개인정보 보호 및 보안</strong>으로 이동합니다.</>,
        <><strong>보안</strong> 섹션까지 아래로 스크롤합니다.</>,
        <>Sayless 관련 메시지 옆의 <strong>그래도 열기</strong>를 누릅니다.</>,
        <>Sayless를 다시 실행한 뒤, 안내가 나오면 손쉬운 사용 권한을 허용합니다.</>
      ],
      confirmed: "설치 안내 확인 완료",
      acknowledge: "설치 안내를 읽었습니다",
      download: "최신 DMG 다운로드",
      downloadHelp: "최신 macOS 빌드를 바로 다운로드합니다.",
      scrollHint: "아래에 다운로드 버튼이 있어요",
      scrollHintSubtext: "설치 안내 확인 후 내려가세요."
    },
    demo: {
      person: "설윤아",
      status: "방금 전 활동",
      typedMessage: "윤아야... 오늘 같이 있어서 계속 생각났는데, 내일 저녁 같이 먹을래?",
      chatMessages: [
        { side: "left", delay: 420, text: "오늘 진짜 재밌었어." },
        { side: "left", compact: true, delay: 780, text: "영화도 생각보다 좋았고 🙂" },
        { side: "right", delay: 1650, text: "나도! 같이 있어서 더 좋았던 듯 🍿" },
        { side: "left", delay: 800, text: "우리 또 보자 😌" }
      ],
      replyPresets: {
        rizz: [
          { label: "은근 설렘", text: "오늘 너랑 있는 거 진짜 좋았어. 내일 저녁은 내가 사도 돼?" },
          { label: "직진", text: "솔직히 오늘 이후로 계속 생각나. 내일 저녁, 우리 둘이 볼래?" },
          { label: "부드럽게", text: "오늘 여기서 끝내기엔 좀 아쉬운데. 내일 저녁 같이 먹자." }
        ],
        sweet: [
          { label: "다정하게", text: "오늘 너랑 보내는 시간이 되게 좋았어. 괜찮으면 내일 저녁 같이 먹을래?" },
          { label: "따뜻하게", text: "오늘 덕분에 기분이 오래 남을 것 같아. 내일도 잠깐 볼 수 있을까?" },
          { label: "조심스럽게", text: "부담 주려는 건 아닌데, 내일 저녁에 너랑 한 번 더 보고 싶어" }
        ],
        playful: [
          { label: "장난스럽게", text: "헤어진 지 얼마나 됐다고 벌써 나 보고 싶냐 ㅋㅋㅋ 내일 저녁에 또 놀아드림" },
          { label: "귀엽게", text: "영화도 좋았는데, 내일 너랑 저녁 먹으면 그게 더 재밌을 것 같은데?" },
          { label: "자신감", text: "나랑 노는 게 제일 재밌지? 그럴 줄 알고 내일 저녁 스케줄 미리 비워뒀음" }
        ],
        custom: [
          { label: "커스텀", text: "조금 떨리지만 자신감 있게, 너무 부담스럽지 않게 말해줘" },
          { label: "시도", text: "너무 진지하지 않게, 그래도 호감은 확실히 느껴지게" },
          { label: "초안", text: "따뜻하고 짧게. 상대가 부담 없이 웃을 수 있게" }
        ]
      },
      adjustments: [
        { id: "rizz", label: "설렘" },
        { id: "sweet", label: "다정" },
        { id: "playful", label: "장난" },
        { id: "custom", label: "직접 입력" }
      ],
      customPlaceholder: "원하는 말투를 그대로 적어보세요",
      loadingLabel: "이서벨이 입력 중",
      downloadCardTitle: "Sayless 다운로드",
      downloadCardSubtitle: "설치 페이지 열기",
      downloadAria: "Sayless 다운로드",
      refreshAria: "답장 새로고침",
      closeAria: "오버레이 닫기",
      adjustmentAria: "답장 톤 조절",
      messageAria: "이서벨에게 메시지 입력",
      firstReply: "아 근데 미안. 나 남자친구 있어.",
      downloadReply: "Sayless 다운받고 다른 사람 찾아보는 게 좋을 듯 🥀"
    },
    footer: {
      rights: "© 2026 Sayless. All rights reserved",
      createdBy: "Created by Inseong Paik"
    }
  }
};

function App() {
  const path = window.location.pathname;
  const isInstallPage = path.endsWith("/install.html") || path.endsWith("/install");
  const [lang, setLang] = useState(() => {
    if (typeof window === "undefined") {
      return "ko";
    }

    return window.localStorage.getItem(LANG_STORAGE_KEY) === "en" ? "en" : "ko";
  });
  const t = COPY[lang];

  useEffect(() => {
    window.localStorage.setItem(LANG_STORAGE_KEY, lang);
    document.documentElement.lang = lang;
  }, [lang]);

  return isInstallPage ? <InstallPage lang={lang} setLang={setLang} t={t} /> : <HomePage lang={lang} setLang={setLang} t={t} />;
}

function Shell({ children, install = false, lang, setLang, t }) {
  return (
    <div className="site-shell">
      <header className="topbar">
        <a className="brand" href="index.html" aria-label="Sayless home">
          <img src="assets/img/app-icon.png" alt="" />
          <span>Sayless</span>
        </a>
        <nav className="nav-links" aria-label="Primary navigation">
          <a href={install ? "index.html#product" : "#product"}>{t.nav.product}</a>
          <a href={install ? "index.html#privacy" : "#privacy"}>{t.nav.privacy}</a>
          <a href={INSTALL_URL}>{t.nav.install}</a>
        </nav>
        <div className="topbar-actions">
          <button
            className="language-toggle"
            type="button"
            aria-label={t.nav.toggleLabel}
            onClick={() => setLang(lang === "en" ? "ko" : "en")}
          >
            <span className={lang === "en" ? "is-active" : ""}>EN</span>
            <span className={lang === "ko" ? "is-active" : ""}>KO</span>
          </button>
        </div>
      </header>
      {children}
    </div>
  );
}

function HomePage({ lang, setLang, t }) {
  return (
    <Shell lang={lang} setLang={setLang} t={t}>
      <main>
        <section className="hero">
          <div className="hero-copy">
            <div className="eyebrow">
              <Sparkles size={16} />
              {t.home.eyebrow}
            </div>
            <h1>{t.home.title}</h1>
            <p className="hero-subtitle">{t.home.subtitle}</p>
            <div className="hero-actions">
              <a className="primary-button" href={INSTALL_URL}>
                <Download size={19} />
                {t.home.downloadCta}
              </a>
              <a className="secondary-button" href="#demo">
                {t.home.demoCta}
                <ChevronRight size={18} />
              </a>
            </div>
            <p className="hero-note">{t.home.note}</p>
          </div>

          <div className="hero-visual" aria-label="Sayless app preview">
            <HeroAppVisual t={t} />
          </div>
        </section>

        <section className="demo-section" id="demo">
          <AssistantMockup key={lang} demo={t.demo} />
        </section>

        <PlatformsSection t={t} />

        <section className="proof-band" aria-label="Sayless workflow">
          {t.home.proof.map((item, index) => (
            <div key={item}>
              <span>{String(index + 1).padStart(2, "0")}</span>
              {item}
            </div>
          ))}
        </section>

        <section className="section split" id="product">
          <div>
            <p className="section-kicker">{t.home.productKicker}</p>
            <h2>{t.home.productTitle}</h2>
            <p>{t.home.productText}</p>
          </div>
          <div className="feature-grid">
            <FeatureCard
              icon={<Eye />}
              title={t.home.features[0].title}
              text={t.home.features[0].text}
            />
            <FeatureCard
              icon={<MessageSquareText />}
              title={t.home.features[1].title}
              text={t.home.features[1].text}
            />
            <FeatureCard
              icon={<Wand2 />}
              title={t.home.features[2].title}
              text={t.home.features[2].text}
            />
            <FeatureCard
              icon={<Command />}
              title={t.home.features[3].title}
              text={t.home.features[3].text}
            />
          </div>
        </section>

        <section className="section workflow">
          <p className="section-kicker">{t.home.workflowKicker}</p>
          <h2>{t.home.workflowTitle}</h2>
          <div className="workflow-grid">
            {t.home.steps.map((step, index) => (
              <Step key={step.title} number={String(index + 1)} title={step.title} text={step.text} />
            ))}
          </div>
        </section>

        <section className="section privacy" id="privacy">
          <div className="privacy-panel">
            <LockKeyhole size={28} />
            <div>
              <p className="section-kicker">{t.home.privacyKicker}</p>
              <h2>{t.home.privacyTitle}</h2>
              <p>{t.home.privacyText}</p>
            </div>
          </div>
        </section>

        <section className="final-cta">
          <div>
            <p className="section-kicker">{t.home.finalKicker}</p>
            <h2>{t.home.finalTitle}</h2>
          </div>
          <a className="primary-button light" href={INSTALL_URL}>
            {t.home.finalCta}
            <ArrowRight size={19} />
          </a>
        </section>
      </main>
      <Footer t={t} />
    </Shell>
  );
}

function InstallPage({ lang, setLang, t }) {
  const [acknowledged, setAcknowledged] = useState(false);
  const [showScrollHint, setShowScrollHint] = useState(true);
  const gateRef = useRef(null);

  useEffect(() => {
    const timer = window.setTimeout(() => setShowScrollHint(false), 4200);
    return () => window.clearTimeout(timer);
  }, []);

  return (
    <Shell install lang={lang} setLang={setLang} t={t}>
      <main className="install-page">
        <button
          className={`install-scroll-hint ${showScrollHint ? "is-visible" : ""}`}
          type="button"
          aria-hidden={!showScrollHint}
          tabIndex={showScrollHint ? 0 : -1}
          onClick={() => {
            setShowScrollHint(false);
            gateRef.current?.scrollIntoView({ behavior: "smooth", block: "center" });
          }}
        >
          <span>{t.install.scrollHint}</span>
          <small>{t.install.scrollHintSubtext}</small>
          <ArrowDown size={16} />
        </button>

        <section className="install-hero">
          <div>
            <div className="eyebrow">
              <Sparkles size={16} />
              {t.install.eyebrow}
            </div>
            <h1>{t.install.title}</h1>
            <p>{t.install.intro}</p>
          </div>
          <div className="install-summary">
            <img src="assets/img/app-icon.png" alt="Sayless app icon" />
            <span>{t.install.appLabel}</span>
            <strong>{t.install.summary}</strong>
          </div>
        </section>

        <section className="install-layout">
          <div className="install-notes">
            <p className="section-kicker">{t.install.notesKicker}</p>
            <h2>{t.install.notesTitle}</h2>
            <p>{t.install.notesText}</p>
            <div className="developer-note">
              <strong>{t.install.developerNoteTitle}</strong>
              <p>{t.install.developerNote}</p>
            </div>
            <ol>
              {t.install.steps.map((step, index) => (
                <li key={index}>{step}</li>
              ))}
            </ol>
          </div>
          <MacSecurityMockup lang={lang} />
        </section>

        <section className="install-gate" ref={gateRef} aria-label="Download confirmation">
          <button
            className={`read-button ${acknowledged ? "is-complete" : ""}`}
            type="button"
            onClick={() => setAcknowledged(true)}
          >
            <CheckCircle2 size={20} />
            {acknowledged ? t.install.confirmed : t.install.acknowledge}
          </button>
          <div className={`download-reveal ${acknowledged ? "is-visible" : ""}`}>
            <a className="primary-button" href={DOWNLOAD_URL}>
              <Download size={19} />
              {t.install.download}
            </a>
            <p>{t.install.downloadHelp}</p>
          </div>
        </section>
      </main>
      <Footer t={t} />
    </Shell>
  );
}

function HeroAppVisual({ t }) {
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
        <p>{t.home.visualSubtitle}</p>
      </div>
      <div className="floating-status top">
        <span>{t.home.menuBar}</span>
        <strong>{t.home.shortcutReady}</strong>
      </div>
      <div className="floating-status bottom">
        <span>{t.home.contextReady}</span>
        <strong>{t.home.repliesPrepared}</strong>
      </div>
    </div>
  );
}

const DEMO_TYPING_START_DELAY = 1000;
const DEMO_INSTALL_URL = "https://ispaik06.github.io/Sayless/install.html";

function AssistantMockup({ demo }) {
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
  const replies = demo.replyPresets[activePreset];
  const demoFocused = demoInView && documentActive;
  const canUseShortcut = showShortcutPrompt || shortcutPromptDismissed || overlayVisible;
  const chatInputEnabled = typingComplete && overlayOpened;
  const renderedMessages = [
    ...demo.chatMessages.slice(0, visibleMessageCount),
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
    if (!demoFocused || selectedReply || visibleMessageCount >= demo.chatMessages.length) {
      return undefined;
    }

    const nextMessage = demo.chatMessages[visibleMessageCount];
    const messageTimer = window.setTimeout(
      () => setVisibleMessageCount((count) => Math.min(count + 1, demo.chatMessages.length)),
      nextMessage.delay
    );

    return () => window.clearTimeout(messageTimer);
  }, [demo.chatMessages, demoFocused, selectedReply, visibleMessageCount]);

  useEffect(() => {
    if (!demoFocused || selectedReply || visibleMessageCount < demo.chatMessages.length || typingReady) {
      return undefined;
    }

    const typingStartTimer = window.setTimeout(() => {
      setTypingReady(true);
    }, DEMO_TYPING_START_DELAY);

    return () => window.clearTimeout(typingStartTimer);
  }, [demo.chatMessages.length, demoFocused, selectedReply, typingReady, visibleMessageCount]);

  useEffect(() => {
    if (!demoFocused || !typingReady || selectedReply || visibleMessageCount < demo.chatMessages.length || typingComplete) {
      return undefined;
    }

    const characters = Array.from(demo.typedMessage);

    if (typedMessage.length >= characters.length) {
      setTypingComplete(true);
      return undefined;
    }

    const typingTimer = window.setTimeout(() => {
      const nextLength = Math.min(Array.from(typedMessage).length + 1, characters.length);
      setTypedMessage(characters.slice(0, nextLength).join(""));
    }, 30);

    return () => window.clearTimeout(typingTimer);
  }, [demo.chatMessages.length, demo.typedMessage, demoFocused, selectedReply, typedMessage, typingComplete, typingReady, visibleMessageCount]);

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
        { id: `isabel-reply-${timestamp}`, side: "left", text: demo.firstReply }
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
          text: demo.downloadReply,
          link: DEMO_INSTALL_URL
        }
      ]);
    }, 4550);
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
            <strong>{demo.person}</strong>
            <span>{demo.status}</span>
          </div>
          <div className="chat-thread" ref={chatThreadRef}>
            {renderedMessages.map((message) => (
              <div
                key={message.id ?? message.text}
                className={`chat-row ${message.side} ${message.compact ? "compact" : ""} ${message.loading ? "is-loading" : ""}`}
              >
                {message.loading ? (
                  <span className="chat-loading-dots" aria-label={demo.loadingLabel}>
                    <span></span>
                    <span></span>
                    <span></span>
                  </span>
                ) : (
                  <>
                    {message.text}
                    {message.link && (
                      <a className="chat-download-card" href={message.link} aria-label={demo.downloadAria}>
                        <img src="assets/img/app-icon.png" alt="" />
                        <span>
                          <strong>{demo.downloadCardTitle}</strong>
                          <em>{demo.downloadCardSubtitle}</em>
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
              className={`input-line chat-composer ${composerText ? "has-reply" : ""}`}
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
              aria-label={demo.messageAria}
              placeholder={demo.typedMessage}
              rows={2}
            />
          ) : (
            <div className={`input-line ${selectedReply ? "has-reply" : ""}`}>
              {selectedReply ? selectedReply.text : typedMessage}
              {!selectedReply && demoFocused && typingReady && visibleMessageCount === demo.chatMessages.length && !typingComplete && (
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
              <button type="button" aria-label={demo.refreshAria}>
                <RefreshCw size={13} />
              </button>
              <button type="button" aria-label={demo.closeAria} onClick={() => setOverlayVisible(false)}>
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
          <div className="overlay-adjustments" aria-label={demo.adjustmentAria}>
            {demo.adjustments.map((adjustment) => (
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
              placeholder={demo.customPlaceholder}
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

function PlatformsSection({ t }) {
  return (
    <section className="section platform-section" aria-label={t.home.platformsKicker}>
      <div className="platform-heading">
        <p className="section-kicker">{t.home.platformsKicker}</p>
        <h2>{t.home.platformsTitle}</h2>
        <p>{t.home.platformsText}</p>
      </div>
      <div className="platform-grid">
        {t.home.platforms.map((platform) => (
          <PlatformCard
            key={platform.id}
            platform={platform}
            readyLabel={t.home.platformStatusReady}
            plannedLabel={t.home.platformStatusPlanned}
          />
        ))}
      </div>
      <p className="platform-disclaimer">{t.home.platformsDisclaimer}</p>
    </section>
  );
}

function PlatformCard({ platform, readyLabel, plannedLabel }) {
  const ready = platform.status === "ready";
  return (
    <article className={`platform-card ${ready ? "is-ready" : "is-planned"}`}>
      <PlatformLogo platform={platform} />
      <div className="platform-card-copy">
        <span className="platform-status">{ready ? readyLabel : plannedLabel}</span>
        <h3>{platform.title}</h3>
      </div>
    </article>
  );
}

function PlatformLogo({ platform }) {
  const [loaded, setLoaded] = useState(false);
  const [failed, setFailed] = useState(false);

  if (!platform.logo || failed) {
    return <div className="platform-logo-placeholder" aria-hidden="true">{platform.title}</div>;
  }

  return (
    <div className="platform-logo-frame">
      {!loaded && <span>{platform.title}</span>}
      <img
        src={platform.logo}
        alt={`${platform.title} logo`}
        loading="lazy"
        className={loaded ? "is-loaded" : ""}
        onLoad={() => setLoaded(true)}
        onError={() => setFailed(true)}
      />
    </div>
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

function MacSecurityMockup({ lang }) {
  const labels = lang === "ko"
    ? {
        notOpened: '"Sayless"을(를) 열 수 없음',
        verify: 'Apple이 "Sayless"에 악성코드가 없는지 확인할 수 없습니다.',
        done: "완료",
        search: "검색",
        privacy: "개인정보 보호 및 보안",
        security: "보안",
        allowFrom: "다음에서 다운로드한 앱 허용",
        appStore: "App Store 및 확인된 개발자",
        blocked: '"Sayless"이(가) Mac을 보호하기 위해 차단되었습니다.',
        openAnyway: "그래도 열기",
        on: "켬",
        accessories: "새 액세서리 요청"
      }
    : {
        notOpened: '"Sayless" Not Opened',
        verify: 'Apple could not verify "Sayless" is free of malware that may harm your Mac or compromise your privacy.',
        done: "Done",
        search: "Search",
        privacy: "Privacy & Security",
        security: "Security",
        allowFrom: "Allow applications from",
        appStore: "App Store & Known Developers",
        blocked: '"Sayless" was blocked to protect your Mac.',
        openAnyway: "Open Anyway",
        on: "On",
        accessories: "Ask for new accessories"
      };

  return (
    <div className="mac-install-guide" aria-label="macOS Privacy and Security settings showing the Open Anyway button">
      <div className="gatekeeper-alert">
        <div className="alert-help">?</div>
        <div className="alert-icon-wrap">
          <img src="assets/img/app-icon.png" alt="" className="alert-app-icon" />
          <span className="alert-warning">!</span>
        </div>
        <h3>{labels.notOpened}</h3>
        <p>{labels.verify}</p>
        <div className="alert-done">{labels.done}</div>
      </div>

      <div className="settings-window">
        <div className="settings-sidebar">
          <div className="settings-traffic-lights" aria-hidden="true">
            <span className="dot red"></span>
            <span className="dot yellow"></span>
            <span className="dot green"></span>
          </div>
          <div className="settings-search">{labels.search}</div>
          <div className="settings-side-row"><span className="settings-side-icon pink"></span>Notifications</div>
          <div className="settings-side-row"><span className="settings-side-icon purple"></span>Focus</div>
          <div className="settings-side-row"><span className="settings-side-icon gray"></span>Screen Time</div>
          <div className="settings-side-row"><span className="settings-side-icon black"></span>Lock Screen</div>
          <div className="settings-side-row active"><span className="settings-side-icon blue"></span>{labels.privacy}</div>
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
            <h3>{labels.privacy}</h3>
          </div>
          <div className="settings-list">
            <div className="settings-row"><span className="settings-row-icon teal"></span>Speech Recognition <strong>0</strong></div>
            <div className="settings-row"><span className="settings-row-icon azure"></span>Sensitive Content Warning <strong>Off</strong></div>
            <div className="settings-row"><span className="settings-row-icon red"></span>Blocked Contacts</div>
            <div className="settings-row"><span className="settings-row-icon indigo"></span>Analytics &amp; Improvements</div>
            <div className="settings-row"><span className="settings-row-icon blue"></span>Apple Advertising</div>
          </div>
          <div className="security-label">{labels.security}</div>
          <div className="security-panel">
            <div className="allow-row">
              <span>{labels.allowFrom}</span>
              <strong>{labels.appStore}</strong>
            </div>
            <div className="blocked-row">
              <div>
                <strong>{labels.blocked}</strong>
                <p>{labels.verify}</p>
              </div>
              <button type="button" className="open-anyway-callout">{labels.openAnyway}</button>
            </div>
          </div>
          <div className="settings-list settings-list-bottom">
            <div className="settings-row"><span className="settings-row-icon gray"></span>FileVault <strong>{labels.on}</strong></div>
            <div className="settings-row"><span className="settings-row-icon slate"></span>Accessories <strong>{labels.accessories}</strong></div>
          </div>
        </div>
      </div>
    </div>
  );
}

function Footer({ t }) {
  const socials = [
    { label: "Instagram", href: "https://www.instagram.com/_ispaik/", icon: <Instagram size={19} /> },
    { label: "GitHub", href: "https://github.com/ispaik06", icon: <Github size={19} /> },
    { label: "LinkedIn", href: "https://www.linkedin.com/in/inseong-paik-7b2982354/", icon: <Linkedin size={19} /> },
    { label: "About me", href: "https://ispaik06.github.io/about/", icon: <CircleUser size={19} /> }
  ];

  return (
    <footer className="footer">
      <div className="footer-left">
        <span>{t.footer.rights}</span>
        <a href="appcast.xml">Appcast</a>
      </div>
      <div className="footer-right" aria-label="Creator links">
        <span>{t.footer.createdBy}</span>
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
