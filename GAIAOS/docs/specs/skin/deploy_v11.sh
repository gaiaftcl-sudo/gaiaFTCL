#!/bin/bash
# deploy_v11.sh - Deploy GaiaFTCL SOGo branding v11
# Includes email action button styling (Reply, Forward, Delete, etc.)

set -e

echo "=============================================="
echo "GaiaFTCL SOGo Branding v11.0"
echo "=============================================="

cd /opt/mailcow-dockerized

SOGO=$(docker compose ps -q sogo-mailcow)

if [ -z "$SOGO" ]; then
    echo "ERROR: sogo-mailcow container not found"
    exit 1
fi

echo "[1/3] Creating CSS with action button styling..."

cat > /tmp/gaiaftcl-v11.css << 'CSSEOF'
:root{--gaia-black:#0a0a0a;--gaia-darker:#050505;--gaia-dark:#151515;--gaia-white:#f5f5f5;--gaia-blue:#00d4ff;--gaia-purple:#8b5cf6;--gaia-green:#10b981;--gaia-red:#ef4444;--gaia-yellow:#f59e0b;--gaia-orange:#f97316;--gaia-gray:#374151;--gaia-gray-light:#6b7280;--gaia-gradient:linear-gradient(135deg,#00d4ff 0%,#8b5cf6 100%)}

/* Action toolbar */
.sg-message-toolbar,.sg-viewer-toolbar,.sg-mail-toolbar,md-toolbar.sg-toolbar{background-color:var(--gaia-dark)!important;border-bottom:1px solid rgba(255,255,255,0.1)!important}

/* Action buttons base */
.sg-message-toolbar .md-button,.sg-viewer-toolbar .md-button,.md-icon-button,md-toolbar .md-button{color:var(--gaia-white)!important;background-color:transparent!important;border-radius:8px!important;transition:all 0.2s!important}
.sg-message-toolbar .md-button:hover,.md-icon-button:hover,md-toolbar .md-button:hover{background-color:rgba(0,212,255,0.1)!important}

/* Action button icons */
.sg-message-toolbar md-icon,.sg-viewer-toolbar md-icon,.md-icon-button md-icon,md-toolbar .md-button md-icon{color:var(--gaia-blue)!important}
.md-icon-button:hover md-icon,md-toolbar .md-button:hover md-icon{color:var(--gaia-white)!important}

/* Reply - Cyan */
button[ng-click*="reply"],[aria-label*="Reply"]:not([aria-label*="All"]){color:var(--gaia-blue)!important}
button[ng-click*="reply"]:hover,[aria-label*="Reply"]:not([aria-label*="All"]):hover{background-color:rgba(0,212,255,0.15)!important}

/* Reply All - Purple */
button[ng-click*="replyAll"],[aria-label*="Reply All"],[aria-label*="Reply all"]{color:var(--gaia-purple)!important}
button[ng-click*="replyAll"]:hover,[aria-label*="Reply All"]:hover{background-color:rgba(139,92,246,0.15)!important}

/* Forward - Green */
button[ng-click*="forward"],[aria-label*="Forward"]{color:var(--gaia-green)!important}
button[ng-click*="forward"]:hover,[aria-label*="Forward"]:hover{background-color:rgba(16,185,129,0.15)!important}

/* Delete - Red */
button[ng-click*="delete"],[aria-label*="Delete"],[aria-label*="Trash"]{color:var(--gaia-red)!important}
button[ng-click*="delete"]:hover,[aria-label*="Delete"]:hover{background-color:rgba(239,68,68,0.15)!important}

/* Archive - Blue */
button[ng-click*="archive"],[aria-label*="Archive"]{color:#3b82f6!important}
button[ng-click*="archive"]:hover,[aria-label*="Archive"]:hover{background-color:rgba(59,130,246,0.15)!important}

/* Star/Flag - Yellow */
button[ng-click*="flag"],button[ng-click*="star"],[aria-label*="Star"],[aria-label*="Flag"]{color:var(--gaia-yellow)!important}
button[ng-click*="flag"]:hover,[aria-label*="Star"]:hover{background-color:rgba(245,158,11,0.15)!important}
.sg-flagged md-icon,.sg-starred md-icon{color:var(--gaia-yellow)!important}

/* Move - Orange */
button[ng-click*="move"],[aria-label*="Move"]{color:var(--gaia-orange)!important}

/* Print - Gray */
button[ng-click*="print"],[aria-label*="Print"]{color:var(--gaia-gray-light)!important}
button[ng-click*="print"]:hover{color:var(--gaia-white)!important}

/* Junk - Yellow */
button[ng-click*="junk"],[aria-label*="Junk"],[aria-label*="Spam"]{color:var(--gaia-yellow)!important}

/* Dropdown menus */
md-menu-content,.md-menu-content{background-color:var(--gaia-darker)!important;border:1px solid rgba(255,255,255,0.1)!important;border-radius:8px!important;box-shadow:0 10px 40px rgba(0,0,0,0.5)!important}
md-menu-item{color:var(--gaia-white)!important}
md-menu-item:hover{background-color:rgba(0,212,255,0.1)!important}
md-menu-item md-icon{color:var(--gaia-blue)!important;margin-right:12px!important}
md-menu-item[aria-label*="Reply All"] md-icon{color:var(--gaia-purple)!important}
md-menu-item[aria-label*="Forward"] md-icon{color:var(--gaia-green)!important}
md-menu-item[aria-label*="Delete"] md-icon{color:var(--gaia-red)!important}
md-menu-item[aria-label*="Archive"] md-icon{color:#3b82f6!important}
md-menu-item[aria-label*="Flag"] md-icon{color:var(--gaia-yellow)!important}
md-menu-item[aria-label*="Move"] md-icon{color:var(--gaia-orange)!important}
md-menu-divider{background-color:rgba(255,255,255,0.1)!important}

/* Compose buttons */
button[ng-click*="send"],[aria-label*="Send"]{background:var(--gaia-gradient)!important;color:var(--gaia-black)!important;font-weight:600!important;border-radius:8px!important}
button[ng-click*="send"]:hover{box-shadow:0 4px 20px rgba(0,212,255,0.4)!important}
button[ng-click*="attach"],[aria-label*="Attach"]{color:var(--gaia-blue)!important}
button[ng-click*="save"],[aria-label*="Save"],[aria-label*="Draft"]{color:var(--gaia-green)!important}
button[ng-click*="discard"],[aria-label*="Discard"]{color:var(--gaia-red)!important}
button[ng-click*="cc"],button[ng-click*="bcc"],[aria-label*="Cc"],[aria-label*="Bcc"]{color:var(--gaia-gray-light)!important}
button[ng-click*="cc"]:hover,button[ng-click*="bcc"]:hover{color:var(--gaia-blue)!important}

/* Tooltips */
md-tooltip,.md-tooltip{background-color:var(--gaia-darker)!important;color:var(--gaia-white)!important;border:1px solid rgba(0,212,255,0.2)!important;border-radius:4px!important}

/* Email body dark mode */
.sg-message-viewer,.sg-mail-viewer,[ui-view="message"],md-content.sg-content{background-color:var(--gaia-dark)!important}
.sg-message-header,.sg-message-header-row,md-card.sg-message-header{background-color:var(--gaia-dark)!important;color:var(--gaia-white)!important}
.sg-message-body,.sg-mail-body,div[ng-bind-html],.mailer_bodytext,blockquote{background-color:var(--gaia-dark)!important;color:var(--gaia-white)!important}
.sg-message-body *,.sg-mail-body *,div[ng-bind-html] *{color:var(--gaia-white)!important;background-color:transparent!important}
.sg-message-body a,div[ng-bind-html] a{color:var(--gaia-blue)!important}

/* Chips */
md-chip,.md-chip{background-color:var(--gaia-dark)!important;border:1px solid var(--gaia-blue)!important;color:var(--gaia-white)!important;border-radius:16px!important}
md-chip *{color:var(--gaia-white)!important}
md-chip .md-chip-remove:hover md-icon{color:var(--gaia-red)!important}

/* Avatars */
.sg-avatar,.md-avatar,.sg-tile-image{background:var(--gaia-gradient)!important;border-radius:50%!important;display:flex!important;align-items:center!important;justify-content:center!important}
.sg-avatar svg,.md-avatar svg,.sg-avatar md-icon,.md-avatar md-icon{display:none!important}

/* Cards */
md-card,.md-card,md-card-content,.md-whiteframe-1dp{background-color:var(--gaia-dark)!important;color:var(--gaia-white)!important}
md-content,.md-content{background-color:var(--gaia-dark)!important;color:var(--gaia-white)!important}

/* FAB */
.sg-compose-fab,.md-fab.md-primary{background:var(--gaia-gradient)!important;box-shadow:0 4px 20px rgba(0,212,255,0.4)!important}
.sg-compose-fab:hover{box-shadow:0 6px 30px rgba(0,212,255,0.6)!important;transform:scale(1.05)!important}
.sg-compose-fab md-icon,.md-fab md-icon{color:var(--gaia-black)!important}

/* Mail list */
.sg-mail-list md-list-item.sg-active{background-color:rgba(0,212,255,0.1)!important;border-left:3px solid var(--gaia-blue)!important}
.sg-mail-list md-list-item:hover{background-color:rgba(0,212,255,0.05)!important}

/* Toolbar */
md-toolbar,.md-toolbar-tools{background:linear-gradient(135deg,#0a0a0a 0%,#1a1a2e 100%)!important}
md-toolbar md-icon{color:var(--gaia-blue)!important}

/* Dialogs */
md-dialog,md-dialog-content{background-color:var(--gaia-black)!important;color:var(--gaia-white)!important;border:1px solid rgba(0,212,255,0.2)!important;border-radius:12px!important}
md-dialog-actions{background-color:var(--gaia-darker)!important;border-top:1px solid rgba(255,255,255,0.1)!important}

/* Inputs */
md-input-container input,md-input-container textarea,.md-input,input,textarea{color:var(--gaia-white)!important;background-color:var(--gaia-dark)!important;border-color:var(--gaia-gray)!important;caret-color:var(--gaia-blue)!important}
md-input-container.md-input-focused input{border-color:var(--gaia-blue)!important}
label{color:var(--gaia-gray-light)!important}

/* Scrollbars */
::-webkit-scrollbar{width:8px}::-webkit-scrollbar-track{background:var(--gaia-black)}::-webkit-scrollbar-thumb{background:var(--gaia-gray);border-radius:4px}::-webkit-scrollbar-thumb:hover{background:var(--gaia-blue)}

/* Tables */
table,table tr,table td,table th{background-color:transparent!important;color:var(--gaia-white)!important;border-color:rgba(255,255,255,0.1)!important}
CSSEOF

echo "  ✓ CSS created"

echo "[2/3] Creating JS for avatar initials..."

cat > /tmp/gaiaftcl-v11.js << 'JSEOF'
(function(){'use strict';console.log('[GaiaFTCL v11] Loading...');
const C={gradient:'linear-gradient(135deg, #00d4ff 0%, #8b5cf6 100%)',text:'#0a0a0a',dark:'#151515',white:'#f5f5f5',cyan:'#00d4ff'};
function getI(t){if(!t||!t.trim())return'G';t=t.trim();let m=t.match(/^([^<]+)</);if(m&&m[1].trim())return m[1].trim().charAt(0).toUpperCase();if(t.includes('@')){let l=t.split('@')[0].toLowerCase();if(l==='mailer-daemon')return'M';return l.charAt(0).toUpperCase();}if(t.toLowerCase().includes('mail delivery'))return'M';return t.charAt(0).toUpperCase();}
function styleA(el,i){if(!el)return;el.style.cssText='background:'+C.gradient+'!important;border-radius:50%!important;display:flex!important;align-items:center!important;justify-content:center!important;overflow:hidden!important;min-width:40px!important;min-height:40px!important;';el.innerHTML='<span style="color:'+C.text+'!important;font-weight:700!important;font-size:16px!important;">'+i+'</span>';el.dataset.gi=i;}
function procList(){document.querySelectorAll('md-list-item.sg-tile,.sg-mail-list md-list-item').forEach(item=>{let av=item.querySelector('.sg-avatar,.md-avatar,.sg-tile-image,md-icon');if(!av)return;let s='',el=item.querySelector('.sg-tile-content h4,.sg-md-subhead');if(el)s=el.textContent;if(!s){let m=item.textContent.match(/[\w.-]+@[\w.-]+/);if(m)s=m[0];}if(item.textContent.includes('Mail Delivery'))s='Mail Delivery';let i=getI(s);if(av.dataset.gi!==i)styleA(av,i);});}
function procViewer(){let v=document.querySelector('.sg-message-viewer,.sg-mail-viewer,[ui-view="message"]');if(!v)return;let av=v.querySelector('.sg-avatar,.md-avatar');if(!av)return;let s='',a=v.querySelector('a[href*="mailto:"],.sg-message-from a');if(a)s=a.textContent||a.href.replace('mailto:','')||'';let h=v.querySelector('.sg-message-header,.sg-message-info');if(h&&(h.textContent.includes('Mail Delivery')||h.textContent.includes('MAILER-DAEMON')))s='Mail Delivery';let i=getI(s);if(av.dataset.gi!==i)styleA(av,i);}
function procUser(){let sec=document.querySelector('md-sidenav .sg-user,.sg-account-box');if(!sec)return;let av=sec.querySelector('.sg-avatar,.md-avatar');if(!av||av.dataset.gu)return;let e='',el=document.querySelector('[ng-bind*="account.email"],.sg-user-email');if(el)e=el.textContent;styleA(av,e.includes('founder@')?'F':getI(e));av.dataset.gu='1';}
function forceDark(){['.sg-message-body','.sg-mail-body','div[ng-bind-html]','.sg-message-header','md-card','.md-card-content','md-content.sg-content'].forEach(sel=>{document.querySelectorAll(sel).forEach(el=>{el.style.setProperty('background-color',C.dark,'important');el.style.setProperty('color',C.white,'important');el.querySelectorAll('*').forEach(c=>{let bg=getComputedStyle(c).backgroundColor;if(bg&&(bg.includes('255,255,255')||bg.includes('255, 255, 255')))c.style.setProperty('background-color','transparent','important');let col=getComputedStyle(c).color;if(col&&(col.includes('0, 0, 0')||col.includes('0,0,0')))c.style.setProperty('color',C.white,'important');if(c.tagName==='A')c.style.setProperty('color',C.cyan,'important');});});});document.querySelectorAll('md-chip,.md-chip').forEach(ch=>{ch.style.setProperty('background-color',C.dark,'important');ch.style.setProperty('border','1px solid '+C.cyan,'important');ch.querySelectorAll('*').forEach(c=>c.style.setProperty('color',C.white,'important'));});}
function run(){procList();procViewer();procUser();forceDark();}
let to;function drun(){clearTimeout(to);to=setTimeout(run,50);}
const obs=new MutationObserver(m=>{for(let x of m)if(x.addedNodes.length||x.type==='attributes'){drun();break;}});
function init(){console.log('[GaiaFTCL v11] Init');run();obs.observe(document.body,{childList:true,subtree:true,attributes:true,attributeFilter:['class','style']});window.addEventListener('hashchange',drun);setInterval(run,1000);console.log('[GaiaFTCL v11] Loaded');}
if(document.readyState==='loading')document.addEventListener('DOMContentLoaded',init);else init();})();
JSEOF

echo "  ✓ JS created"

echo "[3/3] Deploying to container..."

# Copy files
docker cp /tmp/gaiaftcl-v11.css $SOGO:/usr/lib/GNUstep/SOGo/WebServerResources/css/
docker cp /tmp/gaiaftcl-v11.js $SOGO:/usr/lib/GNUstep/SOGo/WebServerResources/js/

# Inject into HTML
docker exec $SOGO bash -c '
HTML="/usr/lib/GNUstep/SOGo/WebServerResources/index.html"

# Remove old versions
sed -i "/gaiaftcl-v10/d" "$HTML" 2>/dev/null || true
sed -i "/gaiaftcl-sogo-v9/d" "$HTML" 2>/dev/null || true

# Check if v11 already injected
if ! grep -q "gaiaftcl-v11.css" "$HTML" 2>/dev/null; then
  sed -i "s|</head>|<link rel=\"stylesheet\" href=\"css/gaiaftcl-v11.css\">\n</head>|" "$HTML"
  sed -i "s|</body>|<script src=\"js/gaiaftcl-v11.js\"></script>\n</body>|" "$HTML"
  echo "HTML injected"
else
  echo "Already injected"
fi
'

# Restart SOGo
echo "Restarting SOGo..."
docker compose restart sogo-mailcow

sleep 5

if docker compose ps | grep -q "sogo-mailcow.*Up"; then
    echo "  ✓ SOGo restarted"
else
    echo "  ⚠ Check SOGo status"
fi

echo ""
echo "=============================================="
echo "v11 DEPLOYED SUCCESSFULLY"
echo "=============================================="
echo ""
echo "Hard refresh: Cmd+Shift+R (Mac) / Ctrl+Shift+R (Win)"
echo ""
echo "Action buttons styled:"
echo "  Reply      → Cyan"
echo "  Reply All  → Purple"
echo "  Forward    → Green"
echo "  Delete     → Red"
echo "  Archive    → Blue"
echo "  Star/Flag  → Yellow"
echo "  Move       → Orange"
echo "  Print      → Gray"
echo "  Send       → Gradient (primary)"
echo ""
echo "Plus all v10 fixes (dark email body, avatars, etc.)"
echo ""
