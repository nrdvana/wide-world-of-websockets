/** WebSocket Slide System
 *
 * Apply this to an HTML file and call slides.init(websocket_uri, show_user_interface) 
 *
 * The slides are represented by an "ol.slides" with each "li" being a slide.
 * Each slide can have a multi-stage animation caused by showing or hiding elements.
 * Each element can be included in one or more frames of animation by giving it data
 * of "data-step", which is either the frame it becomes visible, or a comma/dash
 * notation specifying a list of frames.  An element with class "auto-step" will have
 * its immediate child DOM elements given sequential data-step values.
 *
 * Each step can also have a "data-extern" indicating an external event that should 
 * "go into effect" when that element is shown.  The external event ends when the
 * element is hidden or when the server says it ends.
 */
window.slides= {
	slide_elems: [],
	step_elems: [],
	cur_slide: null,
	cur_extern: null,
	presenter_ui: false,
	
	init: function(ws_uri, show_ui) {
		var self= this;
		this.ws_uri= ws_uri;
		this.presenter_ui= show_ui;
		
		// make a list of DOM nodes for all immediate children of <ol class="slides">
		self.slide_elems= $('ol.slides > li');
		// give each of them a sequence number for quick reference
		self.slide_elems.each(function(idx, e) { self._init_slide(this, idx+1) });
		// register key and click handlers
		$(document).on('keypress', function(e) { return self.handle_key(e.originalEvent); });
		self.slide_elems.on('click', function(e) { self.handle_click(e) });
		// Inject "reconnect" button and register click handler
		$('body').prepend(
			'<div id="websocket-reconnect">'+
			'	<button>Reconnect</button>'+
			'</div>'
		);
		$('.ws-conn button').on('click', function(e) { self.reconnect() });
		// If opened in "control UI mode", inject buttons of UI
		if (show_ui) {
			$('body').prepend(
				'<div id="navbuttons">'+
				'	<button id="nav_prev">Prev</button>'+
				'	<button id="nav_step">Step</button>'+
				'	<button id="nav_next">Next</button>'+
				'</div>'+
				'<div id="presenternotes">'+
				'	<pre></pre>'+
				'</div>'
			);
			$('#nav_prev').on('click', function() { self.change_slide(-1); });
			$('#nav_next').on('click', function() { self.change_slide(1); });
			$('#nav_step').on('click', function() { self.step(1); });
		}
		// Initialize slides in not-slideshow mode
		this.show_slide(null);
		this.reconnect();
	},
	_init_slide: function(slide_dom_node, slide_num) {
		$(slide_dom_node).addClass('slide').data('slide_num', slide_num);
		// Look for .auto-step, and apply step numbers
		var step_num= 1;
		$(slide_dom_node).find('.auto-step').each(function(idx, e) {
			// If it has a step number, and only one, then start the count of its children from that
			var start_step= $(e).data('step');
			if (start_step && start_step.match(/^[0-9]+$/))
				step_num= parseInt(start_step);
			$(e).children().each(function(){ $(this).data('step', [[step_num++]]) });
		});
		// do a deep search to find any element with 'data-step' and give it the class of
		// 'slide-step' for easier selecting later.
		$(slide_dom_node).find('*').each(function(){
			if ($(this).data('step'))
				$(this).addClass('slide-step');
		});
		// Parse each "data-step" specification and replace with an array of ranges
		// Also calculate the step count
		var max_step= 0;
		$(slide_dom_node).find('.slide-step').each(function() {
			var show_list= $(this).data('step');
			if (!Array.isArray(show_list)) {
				show_list= show_list.split(',');
				for (var i= 0; i < show_list.length; i++) {
					show_list[i]= show_list[i].split(/-/);
					show_list[i][0]= parseInt(show_list[i][0]);
					// If a step  has both a start frame and an end frame, then it is "temporary".
					if (show_list.length > 1) {
						show_list[i][1]= parseInt(show_list[i][1]);
						$(this).addClass('temporary-step');
					}
				}
				$(this).data('step', show_list);
			}
			var last= show_list[show_list.length-1];
			if (max_step < last[last.length-1])
				max_step= last[last.length-1];
		});
		$(slide_dom_node).data('max_step', max_step);
	},
	reconnect: function() {
		var self= this;
		// Connect WebSocket to local event server
		this.ws= new WebSocket(this.ws_uri);
		this.ws.onmessage= function(event) { self.handle_extern_event(JSON.parse(event.data)); };
		this.ws.onopen= function(event) { $('#websocket-reconnect').hide(); };
		this.ws.onclose= function(event) { $('#websocket-reconnect').show(); };
	},
	handle_key: function(e) {
		//console.log('handle_key', e);
		if (e.key == 'ArrowRight') {
			self.show_slide(self.cur_slide+1, 1);
			this.change_slide(1);
			return false;
		}
		else if (e.key == 'ArrowLeft') {
			this.change_slide(-1);
			return false;
		}
		else if (e.key == 'ArrowDown' || e.code == 'Space') {
			this.step(1);
			return false;
		}
		return true;
	},
	handle_click: function(e) {
		self= this;
		var slide_num= $(e.currentTarget).data('slide_num');
		if (slide_num) {
			if (slide_num != self.cur_slide) {
				self.show_slide(slide_num, 0)
					&& self.relay_slide_position();
			}
			else {
				self.show_slide(null, null)
					&& self.relay_slide_position();
			}
		}
	},
	handle_extern_event: function(e) {
		//console.log('recv', e);
		// If extern visual has closed, advance to the next slide or step
		if (e['extern_ended'] && e.extern_ended == this.cur_extern)
			this.step_anim(1);
		// If given a slide position, show it
		if ('slide_num' in e)
			this.show_slide(e['slide_num'] || 0, e['step_num'] || 0);
	},
	emit_extern_event: function(obj) {
		//console.log('send',obj);
		if (this.ws)
			this.ws.send( JSON.stringify(obj) );
		else
			console.log("Can't send: ", obj);
	},
	change_slide: function(ofs) {
		var next_idx= (this.cur_slide? this.cur_slide : 0) + ofs;
		if (next_idx < 0) next_idx += this.slide_elems.length + 1;
		if (next_idx > this.slide_elems.length) next_idx -= this.slide_elems.length + 1;
		this.show_slide(next_idx, ofs > 0? 1 : -1)
			&& self.relay_slide_position();
	},
	step: function(ofs) {
		if (!this.cur_slide) {
			this.show_slide(1,0);
		}
		else {
			var next_slide= this.cur_slide;
			var next_step= this.cur_step + ofs;
			while (next_step < 0) {
				if (! --next_slide) {
					if (next_step == -1) { next_step= 0; break; }
					else { next_slide= this.slide_elems.length-1; next_step += 2; }
				}
				next_step += $(this.slide_elems[next_slide-1]).data('max_step')+1;
			}
			while (next_step > $(this.slide_elems[next_slide-1]).data('max_step')) {
				next_step -= $(this.slide_elems[next_slide-1]).data('max_step')+1;
				if (++next_slide > this.slide_elems.length) {
					if (next_step == 0) { next_slide= 0; break; }
					else { next_slide= 1; }
				}
			}
			this.show_slide(next_slide, next_step);
		}
		this.relay_slide_position();
	},
	client_rect: function(elem) {
		var r= elem.getBoundingClientRect();
		//console.log(elem, r);
		return { top: r.top, left: r.left, right: r.right, bottom: r.bottom };
	},
	show_slide: function(slide_num, step_num) {
		//console.log('show_slide(',slide_num,',',step_num,')');
		var self= this;
		if (!slide_num) {
			// return to scrolling-page mode
			$(document.documentElement).css('overflow','auto');
			// Show all steps for each slide
			this.slide_elems.find('.slide-step')
				.css('visibility','visible')
				.css('position','relative')
				.css('opacity',1);
			// Show all slides
			this.slide_elems.show()
				.css('height','auto')
				.css('border','1px solid grey');
			if (this.cur_slide) {
				var slide= this.slide_elems[this.cur_slide-1];
				document.documentElement.scrollTop= $(slide).offset().top;
			}
			this.cur_slide= null;
			this.cur_step= null;
			this.cur_extern= null;
			this.emit_extern_event({ slide_num: null, cur_extern: this.presenter_ui? null : '-' });
		}
		else {
			var elem= this.slide_elems[ slide_num > 0 ? slide_num-1 : this.slide_elems.length + slide_num ];
			var changed= false;
			if (!this.cur_slide || this.cur_slide != slide_num) {
				// Make sure page is in single-slide mode
				$(document.documentElement).css('overflow','hidden');
				// Hide all slides
				this.slide_elems.hide();
				// Then show this one slide, sized to the height of the viewport
				var h = Math.max(document.documentElement.clientHeight, window.innerHeight || 0);
				$(elem).show()
					.css('border','none')
					.height(h);
				// mark this one as the current slide
				this.cur_slide= slide_num;
				this.cur_step= null;
				changed= true;
			}
			var max_step= $(elem).data('max_step');
			if (step_num < 0) step_num= max_step + 1 + step_num;
			if (step_num < 0) step_num= 0;
			if (changed || step_num != this.cur_step) {
				$(elem).find('.slide-step').each(function() {
					// If a step is not visible, behavior depends on whether we are the presenter
					// and whether the element is temporary.  Non-temporary elements need to remain
					// in the document flow so that the layout of the rest doesn't jump around.
					// But temporary have to be removed from the layout so that they don't occupy
					// space.  Meanwhile the presenter gets to see all hidden elements.
					if (self._is_shown_on_step(this, step_num))
						$(this).css('visibility','visible').css('position','relative');
					else {
						if (this.presenter_ui)
							$(this).css('visibility','visible').css('opacity', .3);
						else
							$(this).css('visibility','hidden');
						if ($(this).hasClass('temporary-step'))
							$(this).css('position','absolute');
					}
				});
				this.cur_step= step_num;
				changed= true;
			}
			var figure= $(elem).find('figure');
			this.cur_figure= figure.length? figure[0] : null;
			var prev_extern= this.cur_extern;
			this.cur_extern= figure.length? figure.data('extern') : null;
			this.cur_notes= $(elem).find('pre.hidden').text();
			if (this.presenter_ui) {
				$('#presenternotes pre').text(this.cur_notes);
			}
			else if (changed && (prev_extern || this.cur_extern)) {
				this.emit_extern_event({
					extern: this.presenter_ui? null : this.cur_extern? this.cur_extern : '-',
					elem_rect:
						this.cur_figure? this.client_rect(this.cur_figure)
						: this.slide_num? this.client_rect(this.slide_elems[this.slide_num-1])
						: null
				});
			}
		}
		return changed;
	},
	_is_shown_on_step: function(elem, step_num) {
		var show_on= $(elem).data('step');
		var shown= false;
		if (show_on)
			$.each(show_on, function(i, range) {
				if (step_num >= range[0] && (range.length==1 || step_num <= range[1]))
					shown= true;
			});
		return shown;
	},
	relay_slide_position: function() {
		this.emit_extern_event({
			slide_num: this.cur_slide,
			step_num: this.cur_step,
		});
	}
};
$(document).ready(function() {
	var ws_uri= 'ws://' + window.location.host + '/link.io';
	var show_ui= window.location.hash && window.location.hash.match(/ui/);
	window.slides.init(ws_uri, show_ui);
});
