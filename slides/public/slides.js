window.slides= {
	slide_elems: [],
	cur_slide: null,
	cur_bullets: [],
	cur_bullet_idx: 0,
	cur_extern: null,
	presenter_ui: false,
	
	init: function(ws_uri, show_ui) {
		var self= this;
		this.ws_uri= ws_uri;
		this.presenter_ui= show_ui;
		
		// make a list of DOM nodes for all immediate children of <ol class="slides">
		self.slide_elems= $('ol.slides > li');
		// give each of them a sequence number for quick reference
		self.slide_elems.each(function(idx, e) { $(e).data('slide_num', idx) });
		// register key and click handlers
		$(document).on('keypress', function(e) { return self.handle_key(e.originalEvent); });
		self.slide_elems.on('click', function(e) { self.handle_click(e) });
		// Inject "reconnect" button and register click handler
		$('body').prepend(
			'<div class="ws-conn">'+
			'	<button>Reconnect</button>'+
			'</div>'
		);
		$('.ws-conn button').on('click', function(e) { self.reconnect() });
		// If opened in "control UI mode", inject buttons of UI
		if (show_ui) {
			$('body').prepend(
				'<div id="navbuttons" class="presenter-ui">'+
				'	<button id="nav_prev">Prev</button>'+
				'	<button id="nav_step">Step</button>'+
				'	<button id="nav_next">Next</button>'+
				'</div>'+
				'<div id="presenternotes" class="presenter-ui">'+
				'	<pre></pre>'+
				'</div>'
			);
			$('#nav_prev').on('click', function() { self.next_slide(-1); });
			$('#nav_next').on('click', function() { self.next_slide(1); });
			$('#nav_step').on('click', function() { self.next_step(1); });
		}
		// Initialize slides in not-slideshow mode
		this.show_slide(null);
		this.reconnect();
	},
	reconnect: function() {
		var self= this;
		// Connect WebSocket to local event server
		this.ws= new WebSocket(this.ws_uri);
		this.ws.onmessage= function(event) { self.handle_extern_event(JSON.parse(event.data)); };
		this.ws.onopen= function(event) { $('.ws-conn').css('visibility','hidden'); };
		this.ws.onclose= function(event) { $('.ws-conn').css('visibility','visible'); };
	},
	handle_key: function(e) {
		//console.log('handle_key', e);
		if (e.key == 'ArrowRight') {
			this.next_slide(1);
			return false;
		}
		else if (e.key == 'ArrowLeft') {
			this.next_slide(-1);
			return false;
		}
		else if (e.key == 'ArrowDown' || e.code == 'Space') {
			this.next_step();
			return false;
		}
		return true;
	},
	handle_click: function(e) {
		self= this;
		//console.log(e);
		if (e.currentTarget == self.cur_slide) {
			self.show_slide(null)
		}
		else {
			self.show_slide(e.currentTarget, 1)
		}
	},
	handle_extern_event: function(e) {
		console.log('recv', e);
		// If extern visual has closed, advance to the next slide or step
		if (e['extern_ended'] && e.extern_ended == this.cur_extern) {
			console.log('end of '+e['extern_ended']+', stepping');
			if (!self.step_anim(1)) self.next_slide(1,true);
		}
		var cur_slide_num= this.cur_slide? $(this.cur_slide).data('slide_num') : null;
		if (e['slide_num'] && cur_slide_num != e.slide_num) {
			console.log("at slide",cur_slide_num,'need',e.slide_num, e['step_num']);
			this.show_slide(this.slide_elems[e.slide_num], e['step_num']!==null, true);
		}
		if (('step_num' in e) && e.step_num && e.step_num != this.cur_bullet_idx) {
			console.log('step_num = ', e['step_num'], 'cur_bullet_idx=', this.cur_bullet_idx);
			this.cur_bullet_idx= parseInt(e.step_num);
			this.step_anim(0, true);
		}
		cur_slide_num= this.cur_slide? $(this.cur_slide).data('slide_num') : null;
		console.log('now at',cur_slide_num,this.cur_bullet_idx,'of',this.cur_bullets.length);
	},
	emit_extern_event: function(obj) {
		console.log('send',obj);
		if (this.ws)
			this.ws.send( JSON.stringify(obj) );
		else
			console.log("Can't send: ", obj);
	},
	next_slide: function(ofs, anim, slave) {
		//console.log('next_slide',ofs, anim);
		if (!this.cur_slide) {
			var slide_num= ofs < 0? this.slide_elems.length-ofs : ofs;
			this.show_slide(this.slide_elems[slide_num], anim, slave);
		}
		else {
			var slide_num= $(this.cur_slide).data('slide_num');
			this.show_slide(this.slide_elems[slide_num+ofs], anim, slave);
		}
	},
	next_step: function(ofs) {
		if (!this.step_anim(1)) this.next_slide(1,true);
	},
	step_anim: function(ofs, slave) {
		console.log('step_anim',ofs,slave);
		if (this.cur_bullets.length) {
			this.cur_bullet_idx+= ofs;
			if (this.cur_bullet_idx < this.cur_bullets.length) {
				$(this.cur_slide).find('.anim .once').css('position','absolute').css('visibility','hidden');
				if (this.presenter_ui) {
					$(this.cur_bullets[this.cur_bullet_idx]).css('opacity',1);
					if (!slave)
						this.emit_extern_event({
							slide_num: $(this.cur_slide).data('slide_num'),
							step_num: this.cur_bullet_idx
						});
				}
				else {
					$(this.cur_bullets[this.cur_bullet_idx]).css('position','relative').css('visibility','visible');
					var extern= $(this.cur_bullets[this.cur_bullet_idx]).attr('data-extern');
					if (extern) {
						this.cur_extern= extern;
						this.emit_extern_event({
							slide_num: slave? null : $(this.cur_slide).data('slide_num'),
							step_num: slave? null : this.cur_bullet_idx,
							extern: this.cur_extern,
							elem_rect: this.client_rect(this.cur_bullets[this.cur_bullet_idx])
						});
					}
				}
				return true;
			}
		}
		return false;
	},
	client_rect: function(elem) {
		var r= elem.getBoundingClientRect();
		//console.log(elem, r);
		return { top: r.top, left: r.left, right: r.right, bottom: r.bottom };
	},
	show_slide: function(elem, anim, slave) {
		console.log(elem, anim, slave, 'cur_extern=',this.cur_extern);
		if (!elem) {
			$(document.documentElement).css('overflow','auto');
			// Show all anim items
			$('div.slide .anim li')
				.css('position','relative').css('visibility','visible');
			// Show all slides
			$('div.slide')
				.css('visibility','visible')
				.css('display','block')
				.css('height','auto')
				.css('border','1px solid grey');
			this.cur_bullets= [];
			if (this.cur_slide) {
				var slide= this.cur_slide;
				document.documentElement.scrollTop= $(slide).offset().top;
			}
			this.cur_slide= null;
			this.cur_extern= null;
			this.emit_extern_event({ slide_num: null, cur_extern: this.presenter_ui? null : '-' });
		}
		else {
			$(document.documentElement).css('overflow','hidden');
			$('div.slide')
				.css('visibility','hidden')
				.css('display','none');
			var h = Math.max(document.documentElement.clientHeight, window.innerHeight || 0);
			$(elem).css('visibility','visible')
				.css('display','block')
				.css('border','none')
				.height(h);
			this.cur_slide= elem;
			var figure= $(elem).find('figure');
			var prev_extern= this.cur_extern;
			this.cur_extern= figure.data('extern');
			if (anim) {
				this.cur_bullets= $(elem).find('ul.anim li');
				var from_zero= $(elem).find('ul.from0').length > 0;
				if (this.cur_bullets.length) {
					if (this.presenter_ui) {
						this.cur_bullets.css('opacity', .3);
					} else {
						this.cur_bullets.css('visibility','hidden');
						$(elem).find('.once').css('position','absolute');
					}
					this.cur_bullet_idx= -1;
					if (!from_zero)
						this.step_anim(1, slave);
				}
				else
					this.cur_bullet_idx= null;
			} else {
				this.cur_bullet_idx= null;
				this.cur_bullets= [];
				$(elem).find('ul.anim li').css('visibility','visible');
			}
			var notes= $(elem).find('pre.hidden').text();
			$('#presenternotes pre').text(notes);
			this.emit_extern_event({
				slide_num: slave? null : $(elem).data('slide_num'),
				step_num: slave? null : anim? this.cur_bullet_idx : null,
				extern: this.presenter_ui? null : this.cur_extern? this.cur_extern : prev_extern? '-' : null,
				elem_rect: this.presenter_ui? null : this.client_rect(figure.length? figure[0] : elem),
				notes: notes
			});
		}
	}
};
$(document).ready(function() {
	var ws_uri= 'ws://' + window.location.host + '/link.io';
	var show_ui= window.location.hash && window.location.hash.match(/ui/);
	window.slides.init(ws_uri, show_ui);
});
