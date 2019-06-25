window.asteroids= {
	init: function(target, ws_uri) {
		var self= this;
		this.shipPath= new Path2D();
		this.shipPath.moveTo(6,0);
		this.shipPath.lineTo(-4,4);
		this.shipPath.lineTo(-2,0);
		this.shipPath.lineTo(-4,-4);
		this.shipPath.closePath();
		this.canvas= target;
		this.ws_uri= ws_uri;
		this.state= { t: 0, client_t: 0, ships: [], bullets: [], asteroids: [] };
		this.ws= new WebSocket(ws_uri);
		this.ws.onmessage= function(event) {
			self.state= JSON.parse(event.data);
			self.state.client_t= .001 * new Date();
		};
		this.ws.onclose= function(event) { self.ws= null; };
		$(target).on('keydown', function(e) { return self.handle_key(e.originalEvent, true); });
		$(target).on('keyup', function(e) { return self.handle_key(e.originalEvent, false); });
		//var t= +new Date()*.001;
		//this.state= {
		//	t: t,
		//	client_t: t,
		//	ships: [
		//		{ t: t, x: 100, y: 100, dx: 1, dy: 1, a: 0, da: 0 }
		//	],
		//	bullets: [
		//		{ t: t, x: 200, y: 100, dx: 0, dy: 0 }
		//	],
		//	asteroids: [
		//	//	{ t: t, x: 300, y: 100, dx: .1, dy: .1, a: 0, da: .25,
		//	//		poly: [ [-10,-10], [-10,10], [10,10], [10,-10] ]
		//	//	}
		//	]
		//};
		this.timer= window.setInterval(function(){ self.render() }, 50);
		this.turn=0;
		this.thrust=0;
		this.shoot=0;
		console.log(this.canvas);
	},
	handle_key: function(e, press) {
		// Ignore keys for input elements within the slides
		if (e.keyCode == 39 /* ArrowRight */) {
			if (press && this.turn != 1)
				this.ws.send(JSON.stringify({ turn: this.turn= 1 }));
			else if (!press && this.turn == 1)
				this.ws.send(JSON.stringify({ turn: this.turn= 0 }));
		}
		else if (e.keyCode == 37 /* ArrowLeft */) {
			if (press && this.turn != -1)
				this.ws.send(JSON.stringify({ turn: this.turn= -1 }));
			else if (!press && this.turn == -1)
				this.ws.send(JSON.stringify({ turn: this.turn= 0 }));
		}
		//else if (e.keyCode == 40 /* ArrowDown */) {
		//	if (press && this.thrust != -1)
		//		this.ws.send(JSON.stringify({ thrust: this.thrust= -1 }));
		//	else if (!press && this.thrust == -1)
		//		this.ws.send(JSON.stringify({ thrust: this.thrust= 0 }));
		//}
		else if (e.keyCode == 38 /* ArrowUp */) {
			if (press && this.thrust != 1)
				this.ws.send(JSON.stringify({ thrust: this.thrust= 1 }));
			else if (!press && this.thrust == 1)
				this.ws.send(JSON.stringify({ thrust: this.thrust= 0 }));
		}
		else if (e.keyCode == 32 /* Space */) {
			this.ws.send(JSON.stringify({ shoot: press }));
		}
		else { return true; }
		return false;
	},
	render: function() {
		var cx= this.canvas.getContext('2d');
		var t= .001 * new Date() - this.state.client_t + this.state.t;
		cx.setTransform(1, 0, 0, 1, 0, 0);
		cx.clearRect(0, 0, this.canvas.width, this.canvas.height);
		for (var i= 0; i < this.state.bullets.length; i++) {
			if (this.state.bullets[i].end_t < t) {
				this.state.bullets[i]= this.state.bullets[this.state.bullets.length-1];
				this.state.bullets.pop();
				--i;
				continue;
			}
			this.drawBullet(cx, t, this.state.bullets[i]);
		}
		for (var i= 0; i < this.state.ships.length; i++)
			this.drawShip(cx, t, this.state.ships[i]);
		for (var i= 0; i < this.state.asteroids.length; i++)
			this.drawAsteroid(cx, t, this.state.asteroids[i]);
	},
	drawShip: function(cx, t, ship) {
		var $t= t - ship.t;
		var x, y;
		// convert angles to radians
		var $θ= ship.θ * 2 * Math.PI;
		var $cosθ= Math.cos($θ); var $sinθ= Math.sin($θ);
		var $dθ_dt= ship.dθ_dt * 2 * Math.PI;
		// If rotating, ship motion is determined by
		//  x(t) = ∫∫ a * cos(θ + dθ_dt * t) dt
		//  y(t) = ∫∫ a * sin(θ + dθ_dt * t) dt
		if ($dθ_dt) {
			var $cosθt= Math.cos($θ + $t * $dθ_dt);
			var $sinθt= Math.sin($θ + $t * $dθ_dt);
			var $a_over_dθdt= ship.a / $dθ_dt;
			var $a_over_dθdt2= $a_over_dθdt / $dθ_dt;
			// Calculate integration constants
			var $C1_x= ship.dx_dt - $a_over_dθdt * $sinθ;
			var $C1_y= ship.dy_dt + $a_over_dθdt * $cosθ;
			var $C0_x= ship.x + $a_over_dθdt2 * $cosθ;
			var $C0_y= ship.y + $a_over_dθdt2 * $sinθ;
			// New instantaneous position at time T:
			x= -$a_over_dθdt2 * $cosθt + $t*$C1_x + $C0_x;
			y= -$a_over_dθdt2 * $sinθt + $t*$C1_y + $C0_y;
		}
		// else (no rotation) ship motion is determined by
		//  x(t) = ∫∫ a dt
		else {
			var $ax= ship.a * $cosθ;
			var $ay= ship.a * $sinθ;
			// New instantaneous position at time T:
			x= ship.x + $ax/2 * $t*$t + ship.dx_dt*$t;
			y= ship.y + $ay/2 * $t*$t + ship.dy_dt*$t;
		}
		x= x % this.canvas.width;
		if (x < 0) x += this.canvas.width;
		y= y % this.canvas.height;
		if (y < 0) y += this.canvas.height;
		cx.setTransform(1, 0, 0, 1, x, y);
		cx.rotate($θ + $dθ_dt * $t);
		cx.lineWidth= 1;
		cx.strokeStyle= ship.color? ship.color : 'white';
		cx.stroke(this.shipPath);
		cx.setTransform(1, 0, 0, 1, 0, 0);
	},
	drawBullet: function(cx, t, bullet) {
		var dT= t - bullet.t;
		var x= (bullet.x + bullet.dx_dt * dT) % this.canvas.width;
		if (x < 0) x += this.canvas.width;
		var y= (bullet.y + bullet.dy_dt * dT) % this.canvas.height;
		if (y < 0) y += this.canvas.height;
		cx.fillStyle= 'white';
		cx.beginPath();
		cx.ellipse(x, y, 1, 1, 0, 0, Math.PI*2);
		cx.fill();
	},
	drawAsteroid: function(cx, t, asteroid) {
		var dT= t - asteroid.t;
		cx.setTransform(1, 0, 0, 1, asteroid.x + asteroid.dx*dT, asteroid.y + asteroid.dy*dT);
		cx.rotate((asteroid.a + asteroid.da * dT)*2*Math.PI);
		cx.lineWidth= 1;
		cx.strokeStyle= 'white';
		cx.beginPath();
		cx.moveTo(asteroid.poly[0][0], asteroid.poly[0][1]);
		for (var i= 1; i < asteroid.poly.length; i++)
			cx.lineTo(asteroid.poly[i][0], asteroid.poly[i][1]);
		cx.closePath();
		cx.stroke();
		cx.setTransform(1, 0, 0, 1, 0, 0);
	}
};
