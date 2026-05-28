document.body.addEventListener('showFlash', (e) => {
  const {type, message} = e.detail;
  const cls = {success:'is-success', error:'is-danger', info:'is-info', warning:'is-warning'}[type] || 'is-info';
  const node = document.createElement('div');
  node.className = `notification ${cls}`;
  node.innerHTML = `<button class="delete" onclick="this.parentNode.remove()"></button>${message}`;
  document.getElementById('flash-area').appendChild(node);
  setTimeout(() => node.remove(), 5000);
});

// Listen on `document`, not `document.body`: inline cancel/background handlers
// dispatch on `document`, and htmx HX-Trigger events fired on `body` bubble up.
document.addEventListener('close-modal', () => {
  document.querySelectorAll('.modal.is-active').forEach(m => m.classList.remove('is-active'));
});

document.body.addEventListener('graph-changed', () => {
  if (window.ffRefreshGraph) window.ffRefreshGraph();
});

document.body.addEventListener('step-logged', () => {
  if (window.ffAdventureId) {
    htmx.ajax('GET', '/adventures/' + window.ffAdventureId + '/timeline', '#timeline-area');
  }
});

// Accessible tab switcher: wires any `[data-ff-tabs]` group to its `[role=tabpanel]`s
// via aria-controls. Replaces inline onclick show/hide.
document.addEventListener('DOMContentLoaded', () => {
  document.querySelectorAll('[data-ff-tabs]').forEach(group => {
    const tabs = Array.from(group.querySelectorAll('[role="tab"]'));
    const panels = tabs.map(t => document.getElementById(t.getAttribute('aria-controls')));
    function activate(idx) {
      tabs.forEach((t, i) => {
        const on = i === idx;
        t.setAttribute('aria-selected', on ? 'true' : 'false');
        t.tabIndex = on ? 0 : -1;
        if (panels[i]) panels[i].hidden = !on;
      });
    }
    tabs.forEach((t, i) => {
      t.addEventListener('click', () => activate(i));
      t.addEventListener('keydown', e => {
        if (e.key === 'ArrowRight') { activate((i + 1) % tabs.length); tabs[(i + 1) % tabs.length].focus(); }
        if (e.key === 'ArrowLeft')  { activate((i - 1 + tabs.length) % tabs.length); tabs[(i - 1 + tabs.length) % tabs.length].focus(); }
      });
    });
  });
});
