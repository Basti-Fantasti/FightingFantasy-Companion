document.body.addEventListener('showFlash', (e) => {
  const {type, message} = e.detail;
  const cls = {success:'is-success', error:'is-danger', info:'is-info', warning:'is-warning'}[type] || 'is-info';
  const node = document.createElement('div');
  node.className = `notification ${cls}`;
  node.innerHTML = `<button class="delete" onclick="this.parentNode.remove()"></button>${message}`;
  document.getElementById('flash-area').appendChild(node);
  setTimeout(() => node.remove(), 5000);
});

document.body.addEventListener('close-modal', () => {
  document.querySelectorAll('.modal.is-active').forEach(m => m.classList.remove('is-active'));
});

document.body.addEventListener('graph-changed', () => {
  if (window.ffRefreshGraph) window.ffRefreshGraph();
});
