(function(){
'use strict';
var d=document,root=d.documentElement;root.classList.add('js');
/* route finder */
var picks={
 open:['Auto','Let OryvexVPN choose between WireGuard and MASQUE. If it keeps failing, switch to Tor.'],
 dpi:['MASQUE, then Tor','MASQUE looks like ordinary web traffic. If connections still drop, add Tor with bridges.'],
 blocked:['Tor with bridges','Bridges hide that you are using Tor. Try an obfuscated bridge first, then another one.'],
 mozilla:['Fox with your own relay','Deploy the Cloudflare relay from Fox settings so Fox account requests can reach Mozilla.']
};
var ans=d.querySelector('.answer'),t=d.getElementById('ans-title'),b=d.getElementById('ans-body');
[].forEach.call(d.querySelectorAll('[data-pick]'),function(btn){
  btn.addEventListener('click',function(){
    [].forEach.call(d.querySelectorAll('[data-pick]'),function(o){var on=o===btn;o.classList.toggle('on',on);o.setAttribute('aria-checked',on);});
    var p=picks[btn.getAttribute('data-pick')];t.textContent=p[0];b.textContent=p[1];
    ans.classList.remove('swap');void ans.offsetWidth;ans.classList.add('swap');
  });
});
/* reveal on scroll */
var els=[].slice.call(d.querySelectorAll('.section .head,.route,.choice,.answer,.dl,.cards article,.faq details,.places,.dialog,.relay-grid>div:first-child,.prose section'));
if('IntersectionObserver' in window){
  var io=new IntersectionObserver(function(es){es.forEach(function(e){if(e.isIntersecting){e.target.classList.add('in');io.unobserve(e.target);}});},{threshold:.12,rootMargin:'0px 0px -6% 0px'});
  els.forEach(function(e,i){e.classList.add('reveal');e.style.transitionDelay=(i%3)*70+'ms';io.observe(e);});
  /* once shown, hand transitions back to hover styles */
  d.addEventListener('transitionend',function(ev){var t=ev.target;if(t.classList&&t.classList.contains('in')&&ev.propertyName==='opacity'){t.classList.remove('reveal','in');t.style.transitionDelay='';}});
}
/* close mobile menu after navigation */
[].forEach.call(d.querySelectorAll('.mobile-nav a'),function(a){a.addEventListener('click',function(){var m=d.querySelector('.mobile-nav');if(m)m.removeAttribute('open');});});
d.addEventListener('keydown',function(e){if(e.key==='Escape'){var m=d.querySelector('.mobile-nav[open]');if(m){m.removeAttribute('open');m.querySelector('summary').focus();}}});
})();
