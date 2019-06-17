window.stats= {
	init: function() {
		var self= this;
		self.connect();
	},
	connect: function() {
		var self= this;
		if (!this.ws) {
			// Connect WebSocket and initialize events
			this.ws= new WebSocket('ws://' + window.location.host + '/stats.io');
			this.ws.onmessage= function(event) {
				var stats= JSON.parse(event.data);
				$('.stats-monitor').html(
					'Connections: '+stats['viewer_count']+'<br>'+
					'Wifi RX: <span style="display:inline-block;width:4em; text-align:right">'+parseInt(stats['rx_rate'])+'</span><br>'+
					'Wifi TX: <span style="display:inline-block;width:4em; text-align:right">'+parseInt(stats['tx_rate'])+'</span><br>'
				);
			};
			this.ws.onclose= function(event) {
				self.ws= null;
			};
		}
	},
};
