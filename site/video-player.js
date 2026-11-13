(function () {
  'use strict';

  // Leave the native player in place unless every custom control is available.
  var player = document.querySelector('[data-video-player]');
  if (!player) return;
  var video = player.querySelector('video');
  var controls = player.querySelector('[data-player-controls]');
  var play = player.querySelector('[data-player-play]');
  var center = player.querySelector('[data-player-center]');
  var icon = player.querySelector('[data-player-icon]');
  var label = player.querySelector('[data-player-label]');
  var seek = player.querySelector('[data-player-seek]');
  var current = player.querySelector('[data-player-current]');
  var duration = player.querySelector('[data-player-duration]');
  var fullscreen = player.querySelector('[data-player-fullscreen]');
  var error = player.querySelector('[data-player-error]');
  if (!video || !controls || !play || !center || !icon || !label ||
      !seek || !current || !duration || !fullscreen || !error ||
      typeof video.play !== 'function') return;
  var custom = true;

  function time(seconds) {
    if (!Number.isFinite(seconds) || seconds < 0) seconds = 0;
    var whole = Math.floor(seconds);
    return Math.floor(whole / 60) + ':' + String(whole % 60).padStart(2, '0');
  }

  function updateTime() {
    var total = Number.isFinite(video.duration) && video.duration > 0 ? video.duration : 0;
    var now = Number.isFinite(video.currentTime) ? video.currentTime : 0;
    current.textContent = time(now);
    duration.textContent = time(total);
    seek.value = total ? String(Math.round(Math.min(now / total, 1) * 1000)) : '0';
    seek.disabled = !total;
    seek.setAttribute('aria-valuetext', time(now) + ' of ' + time(total));
  }

  function updateState() {
    var paused = video.paused || video.ended;
    icon.textContent = paused ? '▶' : '❚❚';
    label.textContent = paused ? (video.ended ? 'Replay' : 'Play') : 'Pause';
    play.setAttribute('aria-label', paused ? (video.ended ? 'Replay walkthrough' : 'Play walkthrough') : 'Pause walkthrough');
    center.setAttribute('aria-label', video.ended ? 'Replay walkthrough' : 'Play walkthrough');
    center.hidden = !paused;
  }

  function reportError() {
    custom = false;
    player.classList.remove('has-custom-video');
    error.hidden = false;
    // Restore browser controls if the custom path cannot play.
    video.controls = true;
    controls.hidden = true;
    center.hidden = true;
  }

  function toggle() {
    if (!custom) return;
    if (video.paused || video.ended) {
      if (video.ended) video.currentTime = 0;
      var started = video.play();
      if (started && typeof started.catch === 'function') {
        started.catch(function (reason) {
          if (reason && reason.name === 'AbortError') return;
          // Permission failures (for example mobile autoplay policy) are not media failures.
          // The native player remains available as a fallback.
          reportError();
        });
      }
    } else {
      video.pause();
    }
  }

  play.addEventListener('click', toggle);
  center.addEventListener('click', toggle);
  video.addEventListener('click', toggle);
  video.addEventListener('play', updateState);
  video.addEventListener('pause', updateState);
  video.addEventListener('ended', updateState);
  video.addEventListener('loadedmetadata', updateTime);
  video.addEventListener('durationchange', updateTime);
  video.addEventListener('timeupdate', updateTime);
  video.addEventListener('error', reportError);
  seek.addEventListener('input', function () {
    if (Number.isFinite(video.duration) && video.duration > 0) {
      video.currentTime = (Number(seek.value) / 1000) * video.duration;
      updateTime();
    }
  });
  if (typeof player.requestFullscreen === 'function') {
    fullscreen.addEventListener('click', function () {
      if (document.fullscreenElement === player && document.exitFullscreen) {
        document.exitFullscreen();
      } else {
        var request = player.requestFullscreen();
        if (request && typeof request.catch === 'function') request.catch(function () {});
      }
    });
  } else {
    fullscreen.hidden = true;
  }
  document.addEventListener('fullscreenchange', function () {
    fullscreen.setAttribute('aria-label', document.fullscreenElement === player ?
      'Exit fullscreen' : 'View walkthrough fullscreen');
  });
  updateTime();
  updateState();
  player.classList.add('has-custom-video');
  video.controls = false;
  controls.hidden = false;
  if (video.error) reportError();
})();
