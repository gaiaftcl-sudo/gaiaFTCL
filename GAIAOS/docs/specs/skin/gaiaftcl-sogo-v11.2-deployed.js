// GaiaFTCL SOGo Theme v11.2 - Fixed message count bar
(function() {
    "use strict";

    if (document.querySelector('input[name="userName"]') || window.location.href.indexOf('/SOGo/so/') === -1) return;

    var css = `
:root{--gaia-black:#0a0a0a;--gaia-darker:#050505;--gaia-dark:#151515;--gaia-white:#f5f5f5;--gaia-blue:#00d4ff;--gaia-purple:#8b5cf6;--gaia-green:#10b981;--gaia-red:#ef4444;--gaia-yellow:#f59e0b;--gaia-orange:#f97316;--gaia-gray:#374151;--gaia-gray-light:#6b7280;--gaia-gradient:linear-gradient(135deg,#00d4ff 0%,#8b5cf6 100%)}

/* BASE - FORCE ALL DARK */
html,body,md-content,.layout-row,.layout-column{background:#0a0a0a!important;color:#f5f5f5!important}

/* MESSAGE COUNT BAR - THE "16 messages / Order Received" BAR */
.md-subheader,md-subheader,.md-subheader-inner,.md-subheader-content{background:#0a0a0a!important;color:#f5f5f5!important;border-bottom:1px solid rgba(255,255,255,0.08)!important}
.md-subheader *{color:#999!important}
.sg-toolbar-secondary,.toolbar-secondary{background:#0a0a0a!important}
[ng-if*="messages"],[ng-bind*="messages"]{color:#888!important}

/* Any remaining white bars in mail list area */
.view-list .md-toolbar,.view-list md-toolbar,#listView .md-toolbar,#listView md-toolbar{background:#0a0a0a!important}
.view-list > div,.view-list > md-content > div{background:#0a0a0a!important}

/* MAIL LIST CONTAINER */
.view-list,#listView,.sg-view-list,md-virtual-repeat-container,.md-virtual-repeat-container,.md-virtual-repeat-scroller,.md-virtual-repeat-sizer,.md-virtual-repeat-offsetter{background:#0a0a0a!important}
md-list{background:#0a0a0a!important}
.layout-fill{background:#0a0a0a!important}

/* Toolbar */
md-toolbar,.md-toolbar-tools,.sg-toolbar{background:linear-gradient(135deg,#0a0a0a 0%,#1a1a2e 100%)!important;border-bottom:1px solid rgba(255,255,255,0.1)!important}
md-toolbar *{color:#f5f5f5!important}
md-toolbar md-icon{color:#00d4ff!important;filter:drop-shadow(0 0 4px rgba(0,212,255,0.4))!important}

/* UNREAD BUTTON - BRIGHT CYAN (includes Mark as Unread) */
[aria-label*="Mark as Unread"],[aria-label*="Mark as unread"],[aria-label*="mark as unread"],[aria-label*="Mark as Read"],[aria-label*="Mark as read"],[aria-label*="mark as read"]{color:#00d4ff!important;background:rgba(0,212,255,0.15)!important;border-radius:6px!important}
[aria-label*="Mark as Unread"] md-icon,[aria-label*="Mark as unread"] md-icon,[aria-label*="Mark as Read"] md-icon,[aria-label*="Mark as read"] md-icon,[aria-label*="mail"] md-icon,[aria-label*="Mail"] md-icon{color:#00d4ff!important;filter:drop-shadow(0 0 8px rgba(0,212,255,0.7))!important}

[aria-label*="Unread"],[aria-label*="unread"],button[ng-click*="unread"]{color:#00d4ff!important;background:rgba(0,212,255,0.15)!important;border:1px solid rgba(0,212,255,0.3)!important;border-radius:6px!important}
[aria-label*="Unread"] md-icon{color:#00d4ff!important;filter:drop-shadow(0 0 6px rgba(0,212,255,0.5))!important}

/* Action buttons */
.md-button,.md-icon-button{color:#f5f5f5!important;background-color:transparent!important;border-radius:8px!important}
.md-button:hover,.md-icon-button:hover{background-color:rgba(0,212,255,0.1)!important}

/* Semantic action colors */
[aria-label*="Reply"]:not([aria-label*="All"]) md-icon{color:#00d4ff!important}
[aria-label*="Reply All"] md-icon,[aria-label*="Reply all"] md-icon{color:#8b5cf6!important}
[aria-label*="Forward"] md-icon{color:#10b981!important}
[aria-label*="Delete"] md-icon,[aria-label*="Trash"] md-icon{color:#ef4444!important}
[aria-label*="Flag"] md-icon,[aria-label*="Star"] md-icon{color:#f59e0b!important}
[aria-label*="Move"] md-icon{color:#f97316!important}

/* Sidebar */
md-sidenav{background:#050505!important;border-right:1px solid rgba(255,255,255,0.08)!important}
md-sidenav *{color:#f5f5f5!important}
md-sidenav md-icon{color:#00d4ff!important}

/* Mail list items */
md-list-item{background:#151515!important;border:1px solid rgba(255,255,255,0.05)!important;border-radius:8px!important;margin:3px 6px!important;box-shadow:0 2px 8px rgba(0,0,0,0.4)!important}
md-list-item:hover{background:#1c1c1c!important}
md-list-item.sg-active{background:#1c1c1c!important;border:1px solid rgba(0,212,255,0.3)!important}
md-list-item.sg-unread{border-left:3px solid #00d4ff!important}
.sg-tile-content h3{color:#f5f5f5!important;font-weight:600!important}
.sg-tile-content h4{color:#e0e0e0!important}
.sg-tile-content p{color:#999!important}

/* Avatars */
.sg-avatar,.md-avatar,sg-avatar-image .sg-icon-badge-container{background:linear-gradient(135deg,#00d4ff 0%,#8b5cf6 100%)!important;border-radius:10px!important;display:flex!important;align-items:center!important;justify-content:center!important;width:38px!important;height:38px!important;box-shadow:0 4px 12px rgba(0,0,0,0.5),0 0 15px rgba(0,212,255,0.3)!important}
.sg-avatar md-icon,.md-avatar md-icon,sg-avatar-image .sg-icon-badge-container > md-icon{visibility:hidden!important}

/* Email view */
.view-detail,#detailView,.sg-view-detail,[ui-view="message"]{background:#050505!important;border-left:1px solid rgba(255,255,255,0.05)!important}
.view-detail *,#detailView *{background-color:transparent!important}

/* Email body */
.mailer_mailcontent,.mailer_mailcontentpart,.UIxMailPartTextViewer,.UIxMailPartHTMLViewer,.sg-message-part,[ng-bind-html]{background:#151515!important;color:#f5f5f5!important;padding:18px!important;border-radius:10px!important;margin:10px!important;border:1px solid rgba(255,255,255,0.06)!important;box-shadow:0 4px 16px rgba(0,0,0,0.5)!important}
.mailer_mailcontent *,.sg-message-part *,[ng-bind-html] *{background:transparent!important;color:#f5f5f5!important}
.mailer_mailcontent a{color:#00d4ff!important}

/* Chips */
md-chip{background:#151515!important;color:#f5f5f5!important;border:1px solid #00d4ff!important;border-radius:16px!important}
md-chip *{color:#f5f5f5!important}

/* FAB */
.md-button.md-fab{background:linear-gradient(135deg,#00d4ff 0%,#8b5cf6 100%)!important;box-shadow:0 8px 24px rgba(0,0,0,0.6),0 0 25px rgba(0,212,255,0.5)!important}
.md-button.md-fab md-icon{color:#0a0a0a!important}

/* Menus */
md-menu-content{background:#050505!important;border:1px solid rgba(255,255,255,0.08)!important;border-radius:10px!important;box-shadow:0 12px 36px rgba(0,0,0,0.7)!important}
md-menu-item{color:#f5f5f5!important}
md-menu-item:hover{background:rgba(0,212,255,0.1)!important}
md-menu-item md-icon{color:#00d4ff!important}
md-menu-item[aria-label*="Reply All"] md-icon{color:#8b5cf6!important}
md-menu-item[aria-label*="Forward"] md-icon{color:#10b981!important}
md-menu-item[aria-label*="Delete"] md-icon{color:#ef4444!important}
md-menu-item[aria-label*="Flag"] md-icon{color:#f59e0b!important}

/* Dialogs */
md-dialog{background:#050505!important;border-radius:14px!important;box-shadow:0 16px 48px rgba(0,0,0,0.8),0 0 20px rgba(0,212,255,0.2)!important;border:1px solid rgba(255,255,255,0.08)!important}
md-dialog-content{background:transparent!important;color:#f5f5f5!important}

/* Inputs */
md-input-container input,md-input-container textarea{color:#f5f5f5!important;background:#151515!important;border:1px solid rgba(255,255,255,0.1)!important;border-radius:6px!important}
md-input-container input:focus{border-color:#00d4ff!important}

/* Badge */
.sg-badge{background:linear-gradient(135deg,#00d4ff 0%,#8b5cf6 100%)!important;color:#0a0a0a!important;font-weight:700!important}

/* Scrollbar */
::-webkit-scrollbar{width:8px}::-webkit-scrollbar-track{background:#0a0a0a}::-webkit-scrollbar-thumb{background:#333;border-radius:4px}::-webkit-scrollbar-thumb:hover{background:#00d4ff}

/* Hide checkboxes */
md-checkbox{display:none!important}

/* Links */
a{color:#00d4ff!important}

/* Franklin Chat */
#franklin-trigger{position:fixed!important;bottom:20px!important;right:20px!important;width:54px!important;height:54px!important;border-radius:14px!important;background:linear-gradient(135deg,#00d4ff 0%,#8b5cf6 100%)!important;border:none!important;cursor:pointer!important;z-index:2147483647!important;box-shadow:0 8px 24px rgba(0,0,0,0.6),0 0 25px rgba(0,212,255,0.5)!important;display:flex!important;align-items:center!important;justify-content:center!important}
#franklin-trigger:hover{transform:scale(1.1)!important}
#franklin-trigger svg{width:24px!important;height:24px!important}
#franklin-popup{position:fixed!important;bottom:84px!important;right:20px!important;width:340px!important;height:440px!important;background:#050505!important;border:1px solid rgba(255,255,255,0.08)!important;border-radius:16px!important;box-shadow:0 16px 48px rgba(0,0,0,0.8),0 0 20px rgba(0,212,255,0.2)!important;z-index:2147483646!important;display:none!important;flex-direction:column!important}
#franklin-popup.open{display:flex!important}
.fp-header{background:#151515!important;padding:14px!important;border-bottom:1px solid rgba(255,255,255,0.06)!important;display:flex!important;align-items:center!important;justify-content:space-between!important}
.fp-header-left{display:flex!important;align-items:center!important;gap:10px!important}
.fp-avatar{width:38px!important;height:38px!important;border-radius:10px!important;background:linear-gradient(135deg,#00d4ff 0%,#8b5cf6 100%)!important;display:flex!important;align-items:center!important;justify-content:center!important;color:#0a0a0a!important;font-weight:800!important;font-size:18px!important}
.fp-title{color:#f5f5f5!important;font-weight:700!important;font-size:15px!important}
.fp-badge{display:inline-block!important;background:rgba(0,212,255,0.15)!important;color:#00d4ff!important;font-size:9px!important;padding:2px 6px!important;border-radius:4px!important;margin-left:6px!important;font-weight:600!important;text-transform:uppercase!important}
.fp-close{background:#151515!important;border:1px solid rgba(255,255,255,0.06)!important;color:#888!important;width:32px!important;height:32px!important;border-radius:8px!important;cursor:pointer!important;display:flex!important;align-items:center!important;justify-content:center!important;font-size:16px!important}
.fp-close:hover{background:#1c1c1c!important;color:#f5f5f5!important}
.fp-messages{flex:1!important;overflow-y:auto!important;padding:16px!important}
.fp-msg{margin-bottom:10px!important;padding:12px!important;border-radius:10px!important;font-size:13px!important;line-height:1.5!important}
.fp-msg.system{background:#151515!important;color:#999!important;border:1px solid rgba(255,255,255,0.04)!important}
.fp-msg.user{background:rgba(0,212,255,0.12)!important;color:#f5f5f5!important;margin-left:30px!important;border:1px solid rgba(0,212,255,0.2)!important}
.fp-msg.bot{background:#151515!important;color:#f5f5f5!important;margin-right:30px!important}
.fp-input-area{padding:14px!important;background:#151515!important;border-top:1px solid rgba(255,255,255,0.06)!important;display:flex!important;gap:10px!important}
.fp-input{flex:1!important;background:#1c1c1c!important;border:1px solid rgba(255,255,255,0.08)!important;border-radius:10px!important;padding:12px!important;color:#f5f5f5!important;font-size:13px!important}
.fp-input:focus{border-color:#00d4ff!important;outline:none!important}
.fp-send{background:linear-gradient(135deg,#00d4ff 0%,#8b5cf6 100%)!important;border:none!important;border-radius:10px!important;padding:12px 20px!important;color:#0a0a0a!important;font-weight:700!important;font-size:13px!important;cursor:pointer!important}
`;

    var old = document.getElementById("gaiaftcl-css");
    if (old) old.remove();
    var style = document.createElement("style");
    style.id = "gaiaftcl-css";
    style.textContent = css;
    document.head.appendChild(style);

    var C = {gradient: "linear-gradient(135deg, #00d4ff 0%, #8b5cf6 100%)", text: "#0a0a0a"};

    function getI(t) {
        if (!t || !t.trim()) return "G";
        t = t.trim();
        var m = t.match(/^([^<]+)</);
        if (m && m[1].trim()) return m[1].trim().charAt(0).toUpperCase();
        if (t.includes("@")) {
            var l = t.split("@")[0].toLowerCase();
            if (l === "mailer-daemon") return "M";
            return l.charAt(0).toUpperCase();
        }
        if (t.toLowerCase().includes("mail delivery")) return "M";
        return t.charAt(0).toUpperCase();
    }

    function styleA(el, i) {
        if (!el) return;
        el.style.cssText = "background:" + C.gradient + "!important;border-radius:10px!important;display:flex!important;align-items:center!important;justify-content:center!important;overflow:hidden!important;min-width:38px!important;min-height:38px!important;box-shadow:0 4px 12px rgba(0,0,0,0.5),0 0 15px rgba(0,212,255,0.3)!important;";
        el.innerHTML = "<span style=\"color:" + C.text + "!important;font-weight:800!important;font-size:16px!important;\">" + i + "</span>";
        el.dataset.gi = i;
    }

    function procList() {
        document.querySelectorAll("md-list-item").forEach(function(item) {
            var av = item.querySelector("sg-avatar-image .sg-icon-badge-container,.sg-avatar,.md-avatar");
            if (!av) return;
            var s = "", el = item.querySelector(".sg-tile-content h4,.sg-md-subhead");
            if (el) s = el.textContent;
            if (!s) { var m = item.textContent.match(/[\w.-]+@[\w.-]+/); if (m) s = m[0]; }
            if (item.textContent.includes("Mail Delivery")) s = "Mail Delivery";
            var i = getI(s);
            if (av.dataset.gi !== i) styleA(av, i);
        });
    }

    function procViewer() {
        var v = document.querySelector(".view-detail,#detailView,.sg-view-detail");
        if (!v) return;
        var av = v.querySelector("sg-avatar-image .sg-icon-badge-container,.sg-avatar,.md-avatar");
        if (!av) return;
        var s = "", a = v.querySelector("a[href*=\"mailto:\"]");
        if (a) s = a.textContent || a.href.replace("mailto:", "") || "";
        var i = getI(s);
        if (av.dataset.gi !== i) styleA(av, i);
    }

    function forceDark() {
        // Force dark on message count bar (md-subheader)
        document.querySelectorAll(".md-subheader,md-subheader,.md-subheader-inner,.md-subheader-content").forEach(function(el) {
            el.style.setProperty("background", "#0a0a0a", "important");
            el.style.setProperty("color", "#888", "important");
        });
        // Force dark on mail list container
        document.querySelectorAll(".view-list,#listView,.md-virtual-repeat-container,md-list,.layout-fill").forEach(function(el) {
            el.style.setProperty("background", "#0a0a0a", "important");
        });
        document.querySelectorAll(".view-detail,#detailView").forEach(function(el) {
            el.style.setProperty("background", "#050505", "important");
        });
    }

    function createChat() {
        if (document.getElementById("franklin-trigger")) return;
        var btn = document.createElement("button");
        btn.id = "franklin-trigger";
        btn.innerHTML = "<svg viewBox=\"0 0 24 24\"><path d=\"M20 2H4c-1.1 0-2 .9-2 2v18l4-4h14c1.1 0 2-.9 2-2V4c0-1.1-.9-2-2-2z\" fill=\"#050505\"/><circle cx=\"8\" cy=\"10\" r=\"1.5\" fill=\"#00d4ff\"/><circle cx=\"12\" cy=\"10\" r=\"1.5\" fill=\"#00d4ff\"/><circle cx=\"16\" cy=\"10\" r=\"1.5\" fill=\"#00d4ff\"/></svg>";
        document.body.appendChild(btn);
        var pop = document.createElement("div");
        pop.id = "franklin-popup";
        pop.innerHTML = "<div class=\"fp-header\"><div class=\"fp-header-left\"><div class=\"fp-avatar\">F</div><div><span class=\"fp-title\">Franklin</span><span class=\"fp-badge\">Discovery</span></div></div><button class=\"fp-close\">×</button></div><div class=\"fp-messages\"><div class=\"fp-msg system\">Welcome to GaiaFTCL Discovery. This is read-only — actions require email handoff.</div></div><div class=\"fp-input-area\"><input class=\"fp-input\" placeholder=\"Ask about games, pricing...\"><button class=\"fp-send\">Send</button></div>";
        document.body.appendChild(pop);
        btn.onclick = function() { pop.classList.toggle("open"); };
        pop.querySelector(".fp-close").onclick = function() { pop.classList.remove("open"); };
        var inp = pop.querySelector(".fp-input"), snd = pop.querySelector(".fp-send"), msg = pop.querySelector(".fp-messages");
        function send() {
            var t = inp.value.trim(); if (!t) return;
            var u = document.createElement("div"); u.className = "fp-msg user"; u.textContent = t; msg.appendChild(u);
            setTimeout(function() { var b = document.createElement("div"); b.className = "fp-msg bot"; b.textContent = "Email games@gaiaftcl.com for actions."; msg.appendChild(b); msg.scrollTop = msg.scrollHeight; }, 300);
            inp.value = ""; msg.scrollTop = msg.scrollHeight;
        }
        snd.onclick = send;
        inp.onkeypress = function(e) { if (e.key === "Enter") send(); };
    }

    function run() { forceDark(); procList(); procViewer(); createChat(); }
    run();
    setInterval(run, 500);
    new MutationObserver(run).observe(document.body, { childList: true, subtree: true });
    console.log("GaiaFTCL v11.2 - Fixed message count bar");
})();
