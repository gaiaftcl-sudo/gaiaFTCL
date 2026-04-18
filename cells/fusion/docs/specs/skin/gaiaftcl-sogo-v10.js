/* ============================================
   GaiaFTCL SOGo Avatar & Dark Mode Fix v10.0
   - Extracts actual initials from sender emails
   - Forces dark mode on email content
   ============================================ */

(function() {
  'use strict';
  
  console.log('[GaiaFTCL v10] Loading...');
  
  const CONFIG = {
    gradient: 'linear-gradient(135deg, #00d4ff 0%, #8b5cf6 100%)',
    textColor: '#0a0a0a',
    darkBg: '#151515',
    whiteText: '#f5f5f5',
    cyanLink: '#00d4ff'
  };
  
  // Extract initial from email address or name
  function getInitial(text) {
    if (!text || text.trim() === '') return 'G';
    
    text = text.trim();
    
    // Handle "Name <email@domain.com>" format
    const nameMatch = text.match(/^([^<]+)</);
    if (nameMatch) {
      const name = nameMatch[1].trim();
      if (name && name.length > 0) {
        return name.charAt(0).toUpperCase();
      }
    }
    
    // Handle plain email
    if (text.includes('@')) {
      const localPart = text.split('@')[0];
      // Handle special cases
      if (localPart.toLowerCase() === 'mailer-daemon') return 'M';
      if (localPart.toLowerCase() === 'mail delivery system') return 'M';
      return localPart.charAt(0).toUpperCase();
    }
    
    // Handle "Mail Delivery System" type names
    if (text.toLowerCase().includes('mail delivery')) return 'M';
    if (text.toLowerCase().includes('mailer')) return 'M';
    
    // Just use first character
    return text.charAt(0).toUpperCase();
  }
  
  // Style an avatar element with the correct initial
  function styleAvatar(element, initial) {
    if (!element) return;
    
    element.style.cssText = `
      background: ${CONFIG.gradient} !important;
      border-radius: 50% !important;
      display: flex !important;
      align-items: center !important;
      justify-content: center !important;
      overflow: hidden !important;
      min-width: 40px !important;
      min-height: 40px !important;
    `;
    
    // Remove any existing content (SVG icons, etc.)
    element.innerHTML = '';
    
    // Create the initial span
    const span = document.createElement('span');
    span.textContent = initial;
    span.style.cssText = `
      color: ${CONFIG.textColor} !important;
      font-weight: 700 !important;
      font-size: 16px !important;
      font-family: 'Space Grotesk', 'Inter', -apple-system, sans-serif !important;
      line-height: 1 !important;
    `;
    element.appendChild(span);
    
    element.dataset.gaiaInitial = initial;
  }
  
  // Process mail list avatars
  function processMailList() {
    const items = document.querySelectorAll('md-list-item.sg-tile, .sg-mail-list md-list-item');
    
    items.forEach(item => {
      const avatar = item.querySelector('.sg-avatar, .md-avatar, .sg-tile-image, md-icon[md-svg-icon]');
      if (!avatar) return;
      
      // Find the sender info
      let senderText = '';
      
      // Try to find email in the item
      const senderEl = item.querySelector('.sg-tile-content h4, .sg-md-subhead, .sg-from, [ng-bind*="from"]');
      if (senderEl) {
        senderText = senderEl.textContent.trim();
      }
      
      // Also look for any email pattern in the row
      if (!senderText) {
        const emailMatch = item.textContent.match(/[\w.-]+@[\w.-]+\.\w+/);
        if (emailMatch) {
          senderText = emailMatch[0];
        }
      }
      
      // Look for "Mail Delivery System" text
      if (!senderText && item.textContent.includes('Mail Delivery')) {
        senderText = 'Mail Delivery System';
      }
      
      const initial = getInitial(senderText);
      
      // Only update if different or not yet processed
      if (avatar.dataset.gaiaInitial !== initial) {
        styleAvatar(avatar, initial);
      }
    });
  }
  
  // Process the message viewer avatar
  function processMessageViewer() {
    const viewer = document.querySelector('.sg-message-viewer, .sg-mail-viewer, [ui-view="message"]');
    if (!viewer) return;
    
    const avatar = viewer.querySelector('.sg-avatar, .md-avatar');
    if (!avatar) return;
    
    // Find sender in the message header
    let senderText = '';
    
    const fromLink = viewer.querySelector('a[href*="mailto:"], .sg-message-from a, [ng-bind*="from"]');
    if (fromLink) {
      senderText = fromLink.textContent.trim() || fromLink.getAttribute('href')?.replace('mailto:', '') || '';
    }
    
    // Look for MAILER-DAEMON
    if (!senderText) {
      const anyEmail = viewer.querySelector('[ng-bind-html]')?.textContent.match(/[\w.-]+@[\w.-]+/);
      if (anyEmail) senderText = anyEmail[0];
    }
    
    // Check for Mail Delivery System
    const headerText = viewer.querySelector('.sg-message-header, .sg-message-info')?.textContent || '';
    if (headerText.includes('Mail Delivery') || headerText.includes('MAILER-DAEMON')) {
      senderText = 'Mail Delivery System';
    }
    
    const initial = getInitial(senderText);
    
    if (avatar.dataset.gaiaInitial !== initial) {
      styleAvatar(avatar, initial);
    }
  }
  
  // Process user avatar in sidebar
  function processUserAvatar() {
    const userSection = document.querySelector('md-sidenav .sg-user, .sg-account-box');
    if (!userSection) return;
    
    const avatar = userSection.querySelector('.sg-avatar, .md-avatar');
    if (!avatar || avatar.dataset.gaiaProcessed === 'user') return;
    
    // Get current user email
    let email = '';
    const emailEl = document.querySelector('.sg-user-email, [ng-bind*="account.email"], md-sidenav .sg-email');
    if (emailEl) {
      email = emailEl.textContent.trim();
    }
    
    // Default to F for Founder if founder@
    if (email.includes('founder@')) {
      styleAvatar(avatar, 'F');
    } else {
      styleAvatar(avatar, getInitial(email));
    }
    
    avatar.dataset.gaiaProcessed = 'user';
  }
  
  // Force dark mode on email content
  function forceEmailDarkMode() {
    // Target all possible email body containers
    const selectors = [
      '.sg-message-body',
      '.sg-mail-body',
      '.sg-viewer-body',
      '.sg-message-content',
      'div[ng-bind-html]',
      '[ng-bind-html="viewer.message.content"]',
      '.mailer_bodytext',
      'md-content.sg-content',
      '.sg-message-viewer md-content',
      '.sg-message-header',
      'md-card',
      '.md-card-content'
    ];
    
    selectors.forEach(selector => {
      document.querySelectorAll(selector).forEach(el => {
        // Set dark background
        el.style.setProperty('background-color', CONFIG.darkBg, 'important');
        el.style.setProperty('background', CONFIG.darkBg, 'important');
        el.style.setProperty('color', CONFIG.whiteText, 'important');
        
        // Process all children
        el.querySelectorAll('*').forEach(child => {
          const computed = window.getComputedStyle(child);
          
          // Fix background colors that are light
          const bg = computed.backgroundColor;
          if (bg && (bg.includes('255, 255, 255') || bg.includes('rgb(255') || bg === 'white')) {
            child.style.setProperty('background-color', 'transparent', 'important');
          }
          
          // Fix text colors that are dark
          const color = computed.color;
          if (color && (color.includes('0, 0, 0') || color.includes('rgb(0') || color === 'black')) {
            child.style.setProperty('color', CONFIG.whiteText, 'important');
          }
          
          // Keep links cyan
          if (child.tagName === 'A') {
            child.style.setProperty('color', CONFIG.cyanLink, 'important');
          }
        });
      });
    });
    
    // Also fix md-chips (recipient chips)
    document.querySelectorAll('md-chip, .md-chip').forEach(chip => {
      chip.style.setProperty('background-color', CONFIG.darkBg, 'important');
      chip.style.setProperty('background', CONFIG.darkBg, 'important');
      chip.style.setProperty('border', '1px solid ' + CONFIG.cyanLink, 'important');
      chip.style.setProperty('color', CONFIG.whiteText, 'important');
      
      chip.querySelectorAll('*').forEach(child => {
        child.style.setProperty('color', CONFIG.whiteText, 'important');
      });
    });
  }
  
  // Main processing function
  function processAll() {
    processMailList();
    processMessageViewer();
    processUserAvatar();
    forceEmailDarkMode();
  }
  
  // Debounce
  let timeout;
  function debouncedProcess() {
    clearTimeout(timeout);
    timeout = setTimeout(processAll, 50);
  }
  
  // Set up observer for dynamic content
  const observer = new MutationObserver((mutations) => {
    let shouldProcess = false;
    
    for (const mutation of mutations) {
      if (mutation.addedNodes.length > 0 || mutation.type === 'attributes') {
        shouldProcess = true;
        break;
      }
    }
    
    if (shouldProcess) {
      debouncedProcess();
    }
  });
  
  // Initialize
  function init() {
    console.log('[GaiaFTCL v10] Initializing...');
    
    // Initial run
    processAll();
    
    // Watch for changes
    observer.observe(document.body, {
      childList: true,
      subtree: true,
      attributes: true,
      attributeFilter: ['class', 'style']
    });
    
    // Also run on hash changes (SOGo uses ui-router)
    window.addEventListener('hashchange', debouncedProcess);
    
    // Run periodically to catch any missed updates
    setInterval(processAll, 1000);
    
    console.log('[GaiaFTCL v10] Loaded successfully');
  }
  
  // Start when ready
  if (document.readyState === 'loading') {
    document.addEventListener('DOMContentLoaded', init);
  } else {
    init();
  }
  
})();
