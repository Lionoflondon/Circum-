(() => {
  const screen=document.querySelector('#story-screen');
  const slides=[...screen.querySelectorAll('[data-slide]')];
  const chapters=[...document.querySelectorAll('[data-chapter]')];
  const bars=[...screen.querySelectorAll('.demo-progress b')];
  const launch=document.querySelector('#story-launch');
  const previous=document.querySelector('#story-prev'),next=document.querySelector('#story-next');
  const labels=['The arrival','A personal message','The gift reveal','Why it was chosen','A memory to keep'];
  const duration=5600;
  let index=0,elapsed=0,playing=false,last=0,frame=0,started=false,visible=false;
  function paint(){bars.forEach((bar,i)=>bar.style.transform=`scaleX(${i<index?1:i===index?elapsed/duration:0})`)}
  function show(){
    slides.forEach((slide,i)=>{slide.hidden=i!==index;slide.classList.toggle('is-active',i===index)});
    chapters.forEach((button,i)=>{if(i===index)button.setAttribute('aria-current','step');else button.removeAttribute('aria-current')});
    previous.disabled=index===0;next.disabled=index===slides.length-1;
    document.querySelector('#story-status').textContent=`${index+1} of ${slides.length} · ${labels[index]}`;
    screen.dataset.chapter=String(index);paint();
  }
  function syncPlayback(){
    playing=started&&visible&&!document.hidden;screen.dataset.playing=String(playing);
    cancelAnimationFrame(frame);last=0;if(playing)frame=requestAnimationFrame(tick);
  }
  function tick(now){
    if(!playing)return;
    if(last)elapsed+=Math.min(now-last,200);last=now;
    if(elapsed>=duration){index=(index+1)%slides.length;elapsed=0;show()}
    paint();frame=requestAnimationFrame(tick);
  }
  function start(){launch.hidden=true;started=true;syncPlayback()}
  function select(i){index=Math.max(0,Math.min(i,slides.length-1));elapsed=0;show();start()}
  launch.addEventListener('click',()=>{start();screen.focus()});
  document.querySelector('#story-replay').addEventListener('click',()=>select(0));
  previous.addEventListener('click',()=>select(index-1));next.addEventListener('click',()=>select(index+1));
  chapters.forEach((button,i)=>button.addEventListener('click',()=>select(i)));
  screen.addEventListener('keydown',event=>{if(event.target!==screen)return;if(event.key==='ArrowRight'){event.preventDefault();select(index+1)}else if(event.key==='ArrowLeft'){event.preventDefault();select(index-1)}else if(event.key===' '){event.preventDefault();start()}});
  document.addEventListener('visibilitychange',syncPlayback);
  new IntersectionObserver(entries=>{visible=entries[0].isIntersecting;syncPlayback()},{threshold:0}).observe(screen);
  show();
})();
