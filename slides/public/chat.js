window.chat= {
	init: function() {
		var self= this;
		$('.chat-app').append(
			 '<div class="chatlog"></div>'
			+'<div class="chatline"><input type="text"/><button>Send</button></div>'
			+'<div class="chat-connect">User Name <input type="text"/><button>Connect</button></div>'
		);
		$('.chatline input').on('keypress', function(event) { return self.onkeypress(event.originalEvent); });
		$('.chatline button').on('click', function(event) { self.onsend(event); return false; });
		$('.chat-connect button').on('click', function(event) { self.connect(); return false; });
		$('.chatline').hide();
	},
	connect: function() {
		var self= this;
		if (!this.ws) {
			// Connect WebSocket and initialize events
			var username= $('.chat-connect input').val();
			if (!username) {
				window.alert("Please pick a user name");
				return;
			}
			this.ws= new WebSocket('ws://' + window.location.host + '/chat.io?username='+encodeURIComponent(username));
			this.ws.onopen= function(event) {
				$('.chat-connect').hide();
				$('.chatline').show();
			};
			this.ws.onmessage= function(event) {
				$('.chatlog').append(document.createTextNode(event.data+"\n"))
					.scrollTop($('.chatlog')[0].scrollHeight);
			};
			this.ws.onclose= function(event) {
				$('.chatline').hide();
				$('.chat-connect').show();
				self.ws= null;
			};
		}
	},
	onkeypress: function(event) {
		if (event.key == 'Enter') {
			this.onsend();
			return false;
		}
	},
	onsend: function(event) {
		var text= $('.chatline input').val();
		if (text) {
			this.ws.send(text);
			$('.chatline input').val('');
		}
	}
};

$(document).ready(function() { window.chat.init(); });
