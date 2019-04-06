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

### Example: Mining BitCoin on Browsers

  (joke)

### Example: Telephony

  * Server wants to know if it can deliver calls to client
  * Client is acting like a server for incoming calls

### Example: iPad Apps

  * Want responsive UI via web
  * Show off slide software

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
  * See mailing list for past drama

### IO::Async

  * 

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

## Event-Driven Limitations


## Websocket Design Considerations vs. MVC

  * MVC worker pool is useful
  * Lose that when establishing long-lived connections
  * Can reconnect automatically with Javascript

## Websockets in Apps

### Standalone Websocket Server

  * Simplest example
  * SSL awkward, need extra port configured
  * Workarounds, will come back to this
  * Nice connection object

### Mojo

  * Ecosystem designed for event-driven, makes websockets easy
  * (TODO: more research)

### Plack

  * Awkward callback system allows for websockets
  * Requires special support from server
  * Connection details tangled in closures

### Web::Simple

  * Mostly same as Plack

### Catalyst

  * Catalyst uses Plack callback responder
  * Hold onto $c
  * Example

### Dancer

  * Also Plack, and can use responder
  * Dancer uses lots of globals, so event-driven requires special API
  * Dancer is pretty, event-driven Dancer not so much

### Web::ConServe

  * One object per request, app object becomes connection object
  * Less closure mess

### CGI

  * Each request is own process
  * Can use blocking calls

### Forking from the App

  * Careful handoff of filehandles can work

## Deployment

  * Need to consider worker pool

### Docker

  * probably set each continer to be worker pool

### Nginx

  * Cn reverse-proxy to standalone websocket server!

### Traefik

  * Better reverse proxy
  * Ties into docker better



Websocket Modules:
  * Protocol::Websocket
  * Net::WebSocket
  * Mojolicious::WebSocket
