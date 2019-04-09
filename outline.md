Wide World of Websockets
------------------------

This talk covers background/motivation of WebSockets, background of event-driven programming,
description of lots of design options for working with websockets, and finally recommendation
on best strategies.

## What is a Websocket

  * Starts as an HTTP(S) request
  * Changes protocol from command/response to peer-to-peer
  * Messages are framed, not pure streams
  * Remains within SSL-encapsulated connection

## Why Websockets

  * Some problems are solved best with event-based design
  * HTTP awkward for exchanging events

### Example: Chat

  * Want to deliver messages in both directions in real time

### Example: Stock Ticker / Notification

  * Want to avoid lots of polling
  * Want to see event as soon as it happens.

### Example: Server watching presence of Client

  * Server gets to choose how often to poll for presence of client
  * Heavily loaded server will poll less.  If clients poll, server might go down.

### Example: Telephony

  * Server wants to know if it can deliver calls to client
  * Client is acting like a server for incoming calls

### Example: Mining BitCoin on Browsers

  (joke)

### Example: Waiting for job in queue, and job progress

  * 400 in queue, up to 400 websockets listening.
  * Each time back-end job starts, broadcast to web workers
  * 399 "new position" notifications go out
  * 1 connection gets progress updates until job complete

### Example: iPad Apps

  * Want responsive UI via web
  * Show off slide software

## Support for WebSockets

  * Final draft published end of 2011
  * No support on IE before IE10
  * Everyone else has support since 2012
  * Most proxies have added support by now

## Event Driven Programming

  * Single Thread Nonblocking vs Multi Thread Blocking
  * Java vs. Perl, scalability.
  * POSIX event sources:
    * File handle read/write/error
    * Timers
    * Signals
  * Linux:
    * Inotify (file)
	* Netlink (file)
	* POSIX message queues (signal)
  * Windows
    * Thread/Window Message Queue
	* Some things *can't* cause events, and must block
  * Listen to all events at once
  * Example of select-based loop
  * Event Loop
  * Limitations:
    * Blocking Libraries
      * Database
	  * DNS
	  * SSL
    * Slow code paths

## Event Loop Back-Ends

  * LibEvent
  * LibEV
  * Gtk, Glib, etc
  * Mojo::Reactor

## Event Loop wrappers

### POE

  * Large back-compat, stable API
  * Lots of structure, helps organize references
  * Awkward
  * Less ecosystem activity

### AnyEvent

  * Clean minimalist API
  * Lots of callbacks, beware memory leaks
  * Popular ecosystem
  * Some past drama with author

### IO::Async

  * More structured than AnyEvent
  * Less awkward than POE

### Mojo::IOLoop

  * Also minimalist API
  * Only two options - pure perl or LibEV
  * Tailored toward web service, lacks general features
  * Mentioning it mostly because I refer to it again later

### Coro

  * Different approach to event linkage
  * Pretend that code is making blocking calls
  * Avoids excessive callbacks
  * Lots of "magic" behind the scenes

### Others

## Websocket Design Considerations vs. MVC

  * MVC often uses worker pool, not single process.  WebSocket easiest
    with single process, though WebSocket worker pool is a good goal.
    Need to plan for IPC between websocket workers.
    * Example with directory of unix sockets
  * Most MVC not fully event-driven.  Rewrite is hard.
  * Can have Controller fork off slow tasks; Minion / MessageQueue

  * Worker pool can freely loose workers without interruption
  * WebSocket best with long-lived processes, though can reconnect
    automatically with Javascript

## Should My MVC Controller handle WebSockets?

  * Nice to share Session between WebSocket and controller
  * Probably also sharing a Model, but must be async capable
  * SSL must be handled upstream (TODO: check implementations)
  * To live in same process, controller must be fuly event-driven
  * Can receive request with controller then forward
    socket to WebSocket app.
  * Can fork off child to handle each websocket; resources permitting

## Websockets in Apps

### AnyEvent Websocket Server

  * Simplest example
  * Code focused on single purpose
  * Extra port, SSL to configure
  * No easy way to tie into web service session

### Mojo

  * Ecosystem designed for event-driven code
  * Seamless websocket integration with web service
  * Can only cooperate with AnyEvent if both use same backend, LibEV.

### PSGI

  * Awkward callback response allows for websockets
  * Requires special support from server
  * Connection details tangled in closures

### Plack

  * Plack::App::WebSocket
  * Basically just adapts AnyEvent::WebSocket::Server to PSGI

### Web::Simple

  * Supports returning PSGI apps, so can use Plack::App::WebSocket

### Catalyst

  * Catalyst *does not* support WebSocket
  * (unless you reach into private attributes and tweak things)
  * But based on Plack, so can support websockets in same process
  * Can't make use of Catalyst request / session from WebSocket code.

### Dancer

  * Dancer *mostly doesn't* support WebSocket
  * There is a websocket plugin for Dancer, but it just adds a single instance
    of Plack::App::WebSocket earlier on the PSGI stack and some convenient linkage
	to methods of the app.
  * Can't make use of Dancer request / session from the WebSocket code.
  * Dancer websocket plugin has dubious behavior of letting everyone connect

### Web::ConServe

  * Supported using AnyEvent-based plugin
  * One object per request; app object becomes connection context
  * Less closure mess

### CGI

  * Each request is own process
  * Can use blocking calls

### Forking from the App

  * If blocking app receives WebSocket handshake, can fork off a child
    as if it were a CGI request.
  * Must close descriptor to prevent normal response to request

## Recap of Strategies

  * One pool of http controller processes, another pool (or single process) for websockets
  * Event-driven http controllers that also handle websocket events
  * Process-per-websocket (for small / limited use cases, or very large servers)

### Blocking HTTP controllers with separate WS controllers

  * Use path-routing frontend, like Traefik, Nginx, or Apache
  * Use favorite web framework for http, and block as needed
  * Use AnyEvent or Mojolicious for second websocket service
  * Use Message broker as needed for linking events between processes

### Event-driven HTTP + WS controllers

  * Mojolicious
  * Raw Plack, or with helper like Web::Simple or Web::ConServe
  * Maybe job server, like Minion

Websocket Modules:
  * Protocol::Websocket (handshake and frame encoder/decoder)
  * Net::WebSocket
  * Plack::App::WebSocket
  * AnyEvent::WebSocket::Server
  * Mojolicious::WebSocket (only a decoder/encoder for websocket frames)
  * Web::Hippie
  * Mercury  (message broker for websockets based on Mojo)
